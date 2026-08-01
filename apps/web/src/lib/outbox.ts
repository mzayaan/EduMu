/**
 * Offline outbox.
 *
 * Registers are taken in corridors and classrooms where the connection drops.
 * Mutations are written to IndexedDB first, applied optimistically, and drained
 * when connectivity returns. Every entry targets a natural key, so a replayed
 * entry is an idempotent upsert rather than a duplicate.
 */
import { del, get, set } from 'idb-keyval'
import { supabase } from './supabase'

const KEY = 'edumu.outbox.v2'

interface Target {
  table: string
  onConflict: string
}

const TARGETS: Record<OutboxKind, Target> = {
  'attendance.mark': {
    table: 'attendance_record',
    onConflict: 'attendance_session_id,student_id',
  },
  'period.mark': {
    table: 'period_attendance',
    onConflict: 'subject_set_id,date,timetable_slot_id,student_id',
  },
}

export type OutboxKind = 'attendance.mark' | 'period.mark'

export interface OutboxEntry {
  /** Natural key of the thing being written — used to collapse repeat taps. */
  id: string
  kind: OutboxKind
  payload: Record<string, unknown>
  queuedAt: number
  attempts: number
}

type Listener = (pending: number) => void
const listeners = new Set<Listener>()

export function onOutboxChange(fn: Listener) {
  listeners.add(fn)
  return () => listeners.delete(fn)
}

async function read(): Promise<OutboxEntry[]> {
  return (await get<OutboxEntry[]>(KEY)) ?? []
}

async function write(entries: OutboxEntry[]) {
  if (entries.length === 0) await del(KEY)
  else await set(KEY, entries)
  listeners.forEach((l) => l(entries.length))
}

/**
 * Collapse repeated marks for the same target: only the final status matters,
 * so a teacher tapping through four options still syncs once.
 */
async function enqueue(entry: Omit<OutboxEntry, 'queuedAt' | 'attempts'>) {
  const entries = await read()
  const deduped = entries.filter((e) => !(e.kind === entry.kind && e.id === entry.id))
  deduped.push({ ...entry, queuedAt: Date.now(), attempts: 0 })
  await write(deduped)
}

export function enqueueAttendanceMark(p: {
  school_id: string
  attendance_session_id: string
  student_id: string
  status: string
  minutes_late?: number | null
}) {
  return enqueue({
    id: `${p.attendance_session_id}:${p.student_id}`,
    kind: 'attendance.mark',
    payload: p,
  })
}

export function enqueuePeriodMark(p: {
  school_id: string
  date: string
  timetable_slot_id: string
  subject_set_id: string
  student_id: string
  status: string
}) {
  return enqueue({
    id: `${p.timetable_slot_id}:${p.student_id}`,
    kind: 'period.mark',
    payload: p,
  })
}

export async function pendingCount(): Promise<number> {
  return (await read()).length
}

let draining = false

export async function drain(): Promise<{ synced: number; failed: number }> {
  if (draining || !navigator.onLine) return { synced: 0, failed: 0 }
  draining = true
  let synced = 0
  let failed = 0
  try {
    const entries = await read()
    const remaining: OutboxEntry[] = []

    for (const entry of entries) {
      const target = TARGETS[entry.kind]
      const { error } = await supabase
        .from(target.table)
        .upsert(entry.payload, { onConflict: target.onConflict })

      if (error) {
        failed++
        // A 4xx from RLS will never succeed on retry. Drop after 5 attempts
        // rather than blocking the queue behind a permanently doomed entry.
        if (entry.attempts < 5) remaining.push({ ...entry, attempts: entry.attempts + 1 })
      } else {
        synced++
      }
    }
    await write(remaining)
  } finally {
    draining = false
  }
  return { synced, failed }
}

export function startOutboxSync() {
  void drain()
  window.addEventListener('online', () => void drain())
  setInterval(() => void drain(), 30_000)
}
