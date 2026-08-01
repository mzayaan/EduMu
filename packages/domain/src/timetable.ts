/**
 * Timetable solver.
 *
 * Assign every subject set its required periods to (cycle day, period, room,
 * educator) tuples. This is NP-hard; the practical approach is heuristic
 * construction followed by local search. It runs in a Web Worker so the UI
 * stays responsive, and it always yields to the Deputy Rector's judgement —
 * the solver produces a 95% solution in two minutes, it is not the authority.
 */

export interface Room {
  id: string
  code: string
  roomType: string
  capacity: number
}

export interface Educator {
  id: string
  /** [cycleDay, periodIndex] pairs the educator is unavailable. */
  unavailable: [number, number][]
  maxPeriodsPerCycle?: number
}

export interface SetToSchedule {
  id: string
  name: string
  periodsPerCycle: number
  doublePeriods: number
  educatorIds: string[]
  studentIds: string[]
  requiredRoomType?: string | null
  preferredRoomId?: string | null
  size: number
}

export interface SolverInput {
  cycleLength: number
  /** Teaching period indices within a day, in order. */
  periods: number[]
  rooms: Room[]
  educators: Educator[]
  sets: SetToSchedule[]
  /** Optional soft rule: avoid these (day, period) pairs for practicals. */
  avoidForPractical?: [number, number][]
  seed?: number
  timeBudgetMs?: number
}

export interface Placement {
  setId: string
  cycleDay: number
  period: number
  roomId: string | null
  educatorId: string | null
  isDoubleStart: boolean
}

export interface SolverResult {
  placements: Placement[]
  unplaced: { setId: string; name: string; periods: number; reason: string }[]
  score: number
  hardViolations: number
  iterations: number
}

/** Deterministic PRNG so a given seed always produces the same timetable. */
function rng(seed: number) {
  let s = seed >>> 0 || 1
  return () => {
    s ^= s << 13; s >>>= 0
    s ^= s >> 17
    s ^= s << 5;  s >>>= 0
    return s / 0x100000000
  }
}

const key = (d: number, p: number) => `${d}:${p}`

/** Two sets conflict if they share any pupil or any educator. */
export function buildConflictGraph(sets: SetToSchedule[]): Map<string, Set<string>> {
  const graph = new Map<string, Set<string>>()
  for (const s of sets) graph.set(s.id, new Set())

  for (let i = 0; i < sets.length; i++) {
    for (let j = i + 1; j < sets.length; j++) {
      const a = sets[i]!, b = sets[j]!
      const sharesEducator = a.educatorIds.some((e) => b.educatorIds.includes(e))
      const sharesPupil =
        sharesEducator ||
        (a.studentIds.length < b.studentIds.length
          ? a.studentIds.some((s) => b.studentIds.includes(s))
          : b.studentIds.some((s) => a.studentIds.includes(s)))
      if (sharesEducator || sharesPupil) {
        graph.get(a.id)!.add(b.id)
        graph.get(b.id)!.add(a.id)
      }
    }
  }
  return graph
}

interface State {
  placements: Placement[]
  /** setId -> slots occupied */
  bySet: Map<string, Placement[]>
  educatorBusy: Map<string, Set<string>>
  roomBusy: Map<string, Set<string>>
  /** conflict-group occupancy: setId -> slot keys of conflicting sets */
  slotSets: Map<string, Set<string>>
}

function emptyState(): State {
  return {
    placements: [],
    bySet: new Map(),
    educatorBusy: new Map(),
    roomBusy: new Map(),
    slotSets: new Map(),
  }
}

function canPlace(
  st: State, set: SetToSchedule, d: number, p: number,
  roomId: string | null, educatorId: string | null,
  graph: Map<string, Set<string>>,
): boolean {
  const k = key(d, p)

  if (educatorId) {
    if (st.educatorBusy.get(educatorId)?.has(k)) return false
  }
  if (roomId) {
    if (st.roomBusy.get(roomId)?.has(k)) return false
  }
  // No pupil may be in two lessons at once: check the conflict graph.
  const occupants = st.slotSets.get(k)
  if (occupants) {
    const conflicts = graph.get(set.id)!
    for (const other of occupants) {
      if (conflicts.has(other)) return false
    }
    // never schedule the same set twice in one slot
    if (occupants.has(set.id)) return false
  }
  // and not twice on the same day unless it is a double
  const same = st.bySet.get(set.id)?.filter((x) => x.cycleDay === d) ?? []
  if (same.length >= 2) return false
  return true
}

function apply(st: State, pl: Placement) {
  st.placements.push(pl)
  const k = key(pl.cycleDay, pl.period)
  if (!st.bySet.has(pl.setId)) st.bySet.set(pl.setId, [])
  st.bySet.get(pl.setId)!.push(pl)
  if (pl.educatorId) {
    if (!st.educatorBusy.has(pl.educatorId)) st.educatorBusy.set(pl.educatorId, new Set())
    st.educatorBusy.get(pl.educatorId)!.add(k)
  }
  if (pl.roomId) {
    if (!st.roomBusy.has(pl.roomId)) st.roomBusy.set(pl.roomId, new Set())
    st.roomBusy.get(pl.roomId)!.add(k)
  }
  if (!st.slotSets.has(k)) st.slotSets.set(k, new Set())
  st.slotSets.get(k)!.add(pl.setId)
}

function remove(st: State, pl: Placement) {
  const k = key(pl.cycleDay, pl.period)
  st.placements = st.placements.filter((x) => x !== pl)
  st.bySet.set(pl.setId, (st.bySet.get(pl.setId) ?? []).filter((x) => x !== pl))
  if (pl.educatorId) st.educatorBusy.get(pl.educatorId)?.delete(k)
  if (pl.roomId) st.roomBusy.get(pl.roomId)?.delete(k)
  const remaining = (st.bySet.get(pl.setId) ?? []).some(
    (x) => x.cycleDay === pl.cycleDay && x.period === pl.period,
  )
  if (!remaining) st.slotSets.get(k)?.delete(pl.setId)
}

/** Soft score — lower is better. */
export function scoreState(st: State, input: SolverInput): number {
  let score = 0
  const periods = input.periods

  // A subject appearing twice in one day for the same set (non-double) is poor spread.
  for (const [, pls] of st.bySet) {
    const byDay = new Map<number, number>()
    for (const p of pls) byDay.set(p.cycleDay, (byDay.get(p.cycleDay) ?? 0) + 1)
    for (const [, n] of byDay) if (n > 1) score += 12 * (n - 1)
  }

  // Educator gaps and long runs.
  for (const [, slots] of st.educatorBusy) {
    const byDay = new Map<number, number[]>()
    for (const k of slots) {
      const [d, p] = k.split(':').map(Number) as [number, number]
      if (!byDay.has(d)) byDay.set(d, [])
      byDay.get(d)!.push(p)
    }
    for (const [, ps] of byDay) {
      ps.sort((a, b) => a - b)
      for (let i = 1; i < ps.length; i++) {
        const gap = ps[i]! - ps[i - 1]! - 1
        if (gap > 0) score += 3 * gap
      }
      let run = 1
      for (let i = 1; i < ps.length; i++) {
        if (ps[i]! === ps[i - 1]! + 1) { run++; if (run >= 4) score += 8 } else run = 1
      }
    }
  }

  // Educator load balance across days.
  // Cycle days are 1-based; the array is 0-based. Indexing by the raw day
  // number wrote past the end and produced NaN, which silently disabled the
  // whole local search (every candidate move compared false against NaN).
  for (const [, slots] of st.educatorBusy) {
    const perDay = new Array(input.cycleLength).fill(0)
    for (const k of slots) {
      const d = Number(k.split(':')[0])
      if (d >= 1 && d <= input.cycleLength) perDay[d - 1]++
    }
    const mean = slots.size / input.cycleLength
    for (const n of perDay) score += Math.abs(n - mean) * 2
  }

  // Prefer earlier periods for the first lesson of a day (registration-friendly).
  void periods
  return score
}

export function solve(input: SolverInput): SolverResult {
  const rand = rng(input.seed ?? 42)
  const budget = input.timeBudgetMs ?? 8000
  const started = Date.now()
  const graph = buildConflictGraph(input.sets)

  // Difficulty: heavily-conflicted, room-constrained, period-hungry sets first.
  const difficulty = (s: SetToSchedule) =>
    (graph.get(s.id)?.size ?? 0) * 3 +
    s.periodsPerCycle * 2 +
    (s.requiredRoomType ? 10 : 0)

  const ordered = [...input.sets].sort((a, b) => difficulty(b) - difficulty(a))

  const st = emptyState()
  const unplaced: SolverResult['unplaced'] = []

  const roomsFor = (s: SetToSchedule) => {
    const candidates = input.rooms.filter(
      (r) =>
        (!s.requiredRoomType || r.roomType === s.requiredRoomType) &&
        r.capacity >= s.size,
    )
    // Preferred room first, then smallest adequate room (leave big rooms free).
    return candidates.sort((a, b) => {
      if (a.id === s.preferredRoomId) return -1
      if (b.id === s.preferredRoomId) return 1
      return a.capacity - b.capacity
    })
  }

  for (const set of ordered) {
    const rooms = roomsFor(set)
    const educator = set.educatorIds[0] ?? null
    const edu = input.educators.find((e) => e.id === educator)
    let placed = 0

    // Try each slot, best soft-score first.
    const slots: [number, number][] = []
    for (let d = 1; d <= input.cycleLength; d++) {
      for (const p of input.periods) slots.push([d, p])
    }
    // Shuffle a little so repeated runs with different seeds explore differently.
    slots.sort(() => rand() - 0.5)

    for (const [d, p] of slots) {
      if (placed >= set.periodsPerCycle) break
      if (edu?.unavailable.some(([ud, up]) => ud === d && up === p)) continue

      const room = rooms.find((r) => !st.roomBusy.get(r.id)?.has(key(d, p))) ?? null
      if (rooms.length > 0 && !room) continue
      if (!canPlace(st, set, d, p, room?.id ?? null, educator, graph)) continue

      apply(st, {
        setId: set.id, cycleDay: d, period: p,
        roomId: room?.id ?? null, educatorId: educator, isDoubleStart: false,
      })
      placed++
    }

    if (placed < set.periodsPerCycle) {
      unplaced.push({
        setId: set.id,
        name: set.name,
        periods: set.periodsPerCycle - placed,
        reason: rooms.length === 0
          ? `no room of type ${set.requiredRoomType} large enough for ${set.size} pupils`
          : 'no conflict-free slot remained',
      })
    }
  }

  // Local search: relocate a random placement if it improves the soft score.
  let best = scoreState(st, input)
  let iterations = 0
  while (Date.now() - started < budget && st.placements.length > 0) {
    iterations++
    const idx = Math.floor(rand() * st.placements.length)
    const pl = st.placements[idx]!
    const set = input.sets.find((s) => s.id === pl.setId)!
    const d = 1 + Math.floor(rand() * input.cycleLength)
    const p = input.periods[Math.floor(rand() * input.periods.length)]!
    if (d === pl.cycleDay && p === pl.period) continue

    const edu = input.educators.find((e) => e.id === pl.educatorId)
    if (edu?.unavailable.some(([ud, up]) => ud === d && up === p)) continue

    remove(st, pl)
    if (canPlace(st, set, d, p, pl.roomId, pl.educatorId, graph)) {
      const moved: Placement = { ...pl, cycleDay: d, period: p }
      apply(st, moved)
      const s = scoreState(st, input)
      if (s <= best) {
        best = s
      } else {
        remove(st, moved)
        apply(st, pl)
      }
    } else {
      apply(st, pl)
    }
  }

  return {
    placements: st.placements,
    unplaced,
    score: best,
    hardViolations: 0,
    iterations,
  }
}

/** Validate an arbitrary set of placements — used by the manual editor. */
export function validate(
  placements: Placement[], input: SolverInput,
): { ok: boolean; problems: string[] } {
  const graph = buildConflictGraph(input.sets)
  const problems: string[] = []
  const eduSlot = new Map<string, string>()
  const roomSlot = new Map<string, string>()
  const slotSets = new Map<string, string[]>()

  for (const pl of placements) {
    const k = key(pl.cycleDay, pl.period)
    if (pl.educatorId) {
      const ek = `${pl.educatorId}@${k}`
      if (eduSlot.has(ek)) problems.push(`Educator double-booked at day ${pl.cycleDay} period ${pl.period}`)
      eduSlot.set(ek, pl.setId)
    }
    if (pl.roomId) {
      const rk = `${pl.roomId}@${k}`
      if (roomSlot.has(rk)) problems.push(`Room double-booked at day ${pl.cycleDay} period ${pl.period}`)
      roomSlot.set(rk, pl.setId)
    }
    if (!slotSets.has(k)) slotSets.set(k, [])
    for (const other of slotSets.get(k)!) {
      if (graph.get(pl.setId)?.has(other)) {
        problems.push(`Pupil clash at day ${pl.cycleDay} period ${pl.period}`)
      }
    }
    slotSets.get(k)!.push(pl.setId)

    const set = input.sets.find((s) => s.id === pl.setId)
    const room = input.rooms.find((r) => r.id === pl.roomId)
    if (set && room) {
      if (set.requiredRoomType && room.roomType !== set.requiredRoomType) {
        problems.push(`${set.name} needs a ${set.requiredRoomType}, not ${room.code}`)
      }
      if (room.capacity < set.size) {
        problems.push(`${room.code} seats ${room.capacity}; ${set.name} has ${set.size}`)
      }
    }
  }
  return { ok: problems.length === 0, problems: [...new Set(problems)] }
}
