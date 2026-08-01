import { describe, expect, it } from 'vitest'
import {
  buildConflictGraph, solve, validate,
  type SetToSchedule, type SolverInput,
} from './timetable'

const rooms = [
  { id: 'r1', code: 'R1', roomType: 'classroom', capacity: 40 },
  { id: 'r2', code: 'R2', roomType: 'classroom', capacity: 40 },
  { id: 'lab', code: 'LAB', roomType: 'science_lab', capacity: 32 },
]

function mkSet(over: Partial<SetToSchedule> & { id: string }): SetToSchedule {
  return {
    name: over.id, periodsPerCycle: 4, doublePeriods: 0,
    educatorIds: ['e1'], studentIds: ['s1', 's2'], size: 30,
    requiredRoomType: null, preferredRoomId: null,
    ...over,
  }
}

const base = (sets: SetToSchedule[]): SolverInput => ({
  cycleLength: 5,
  periods: [1, 2, 3, 4, 5, 6],
  rooms,
  educators: [{ id: 'e1', unavailable: [] }, { id: 'e2', unavailable: [] }],
  sets,
  seed: 7,
  timeBudgetMs: 300,
})

describe('conflict graph', () => {
  it('links sets sharing a pupil', () => {
    const g = buildConflictGraph([
      mkSet({ id: 'a', educatorIds: ['e1'], studentIds: ['s1'] }),
      mkSet({ id: 'b', educatorIds: ['e2'], studentIds: ['s1'] }),
      mkSet({ id: 'c', educatorIds: ['e2'], studentIds: ['s9'] }),
    ])
    expect(g.get('a')!.has('b')).toBe(true)
    expect(g.get('a')!.has('c')).toBe(false)
  })

  it('links sets sharing an educator even with no common pupils', () => {
    const g = buildConflictGraph([
      mkSet({ id: 'a', educatorIds: ['e1'], studentIds: ['s1'] }),
      mkSet({ id: 'b', educatorIds: ['e1'], studentIds: ['s2'] }),
    ])
    expect(g.get('a')!.has('b')).toBe(true)
  })
})

describe('solver', () => {
  it('places every period of every set when capacity allows', () => {
    const sets = [
      mkSet({ id: 'maths', educatorIds: ['e1'] }),
      mkSet({ id: 'english', educatorIds: ['e2'] }),
    ]
    const r = solve(base(sets))
    expect(r.unplaced).toEqual([])
    expect(r.placements.length).toBe(8)
  })

  it('never double-books an educator', () => {
    const sets = [
      mkSet({ id: 'a', educatorIds: ['e1'], studentIds: ['s1'] }),
      mkSet({ id: 'b', educatorIds: ['e1'], studentIds: ['s2'] }),
    ]
    const r = solve(base(sets))
    const seen = new Set<string>()
    for (const p of r.placements) {
      const k = `${p.educatorId}:${p.cycleDay}:${p.period}`
      expect(seen.has(k)).toBe(false)
      seen.add(k)
    }
  })

  it('never puts two sets sharing a pupil in the same slot', () => {
    const sets = [
      mkSet({ id: 'a', educatorIds: ['e1'], studentIds: ['s1'] }),
      mkSet({ id: 'b', educatorIds: ['e2'], studentIds: ['s1'] }),
    ]
    const r = solve(base(sets))
    const v = validate(r.placements, base(sets))
    expect(v.problems.filter((p) => p.includes('Pupil clash'))).toEqual([])
  })

  it('respects required room type', () => {
    const sets = [mkSet({ id: 'bio', requiredRoomType: 'science_lab', size: 30 })]
    const r = solve(base(sets))
    for (const p of r.placements) expect(p.roomId).toBe('lab')
  })

  it('reports what it could not place, with a reason, rather than dropping it', () => {
    // A lab set of 40 cannot fit the 32-seat lab.
    const sets = [mkSet({ id: 'huge', requiredRoomType: 'science_lab', size: 40 })]
    const r = solve(base(sets))
    expect(r.unplaced).toHaveLength(1)
    expect(r.unplaced[0]!.reason).toContain('no room of type science_lab')
  })

  it('honours educator unavailability', () => {
    const input = base([mkSet({ id: 'a', educatorIds: ['e1'], periodsPerCycle: 2 })])
    input.educators = [{ id: 'e1', unavailable: [[1, 1], [1, 2], [1, 3], [1, 4], [1, 5], [1, 6]] }]
    const r = solve(input)
    expect(r.placements.every((p) => p.cycleDay !== 1)).toBe(true)
  })

  it('is deterministic for a given seed', () => {
    const sets = [mkSet({ id: 'a' }), mkSet({ id: 'b', educatorIds: ['e2'] })]
    const a = solve({ ...base(sets), seed: 99 })
    const b = solve({ ...base(sets), seed: 99 })
    expect(a.placements.length).toBe(b.placements.length)
    expect(a.score).toBe(b.score)
  })
})

describe('validate', () => {
  it('catches a room too small for the set', () => {
    const sets = [mkSet({ id: 'a', size: 35 })]
    const v = validate(
      [{ setId: 'a', cycleDay: 1, period: 1, roomId: 'lab', educatorId: 'e1', isDoubleStart: false }],
      base(sets),
    )
    expect(v.ok).toBe(false)
    expect(v.problems.join(' ')).toContain('seats 32')
  })

  it('accepts a clean timetable', () => {
    const sets = [mkSet({ id: 'a', periodsPerCycle: 1 })]
    const r = solve(base(sets))
    expect(validate(r.placements, base(sets)).ok).toBe(true)
  })
})

describe('soft score', () => {
  // Regression: cycle days are 1-based and the per-day array is 0-based.
  // Indexing by the raw day number wrote past the end and yielded NaN, which
  // made every local-search comparison false and silently disabled the search.
  it('is always a finite number', () => {
    const sets = [
      mkSet({ id: 'a', educatorIds: ['e1'] }),
      mkSet({ id: 'b', educatorIds: ['e2'] }),
    ]
    const r = solve(base(sets))
    expect(Number.isFinite(r.score)).toBe(true)
    expect(Number.isNaN(r.score)).toBe(false)
  })

  it('local search improves on the constructed solution', () => {
    const sets = Array.from({ length: 12 }, (_, i) =>
      mkSet({
        id: `s${i}`,
        educatorIds: [`e${i % 3}`],
        studentIds: [`p${i % 4}a`, `p${i % 4}b`],
      }),
    )
    const constructed = solve({ ...base(sets), timeBudgetMs: 0 })
    const improved = solve({ ...base(sets), timeBudgetMs: 600 })
    expect(Number.isFinite(constructed.score)).toBe(true)
    expect(improved.score).toBeLessThanOrEqual(constructed.score)
    expect(improved.iterations).toBeGreaterThan(0)
  })
})
