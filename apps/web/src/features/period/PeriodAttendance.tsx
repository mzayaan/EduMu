import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { AttendanceStatus } from '@/types/database'
import { displayName, formatLongDate, todayInMauritius } from '@/lib/format'
import { enqueuePeriodMark, drain } from '@/lib/outbox'
import type { EduClaims } from '@/lib/supabase'
import { fetchMyLessons, fetchSetRoster, prefillPeriod, type Lesson } from './api'
import { SyncBadge } from '@/components/SyncBadge'

const STATUSES: { value: AttendanceStatus; short: string; label: string; cls: string }[] = [
  { value: 'present',       short: 'P', label: 'Present',            cls: 'bg-present text-white border-present' },
  { value: 'absent_unauth', short: 'A', label: 'Absent',             cls: 'bg-absent text-white border-absent' },
  { value: 'late',          short: 'L', label: 'Late',               cls: 'bg-late text-white border-late' },
  { value: 'absent_auth',   short: 'AA', label: 'Authorised absence', cls: 'bg-authorised text-white border-authorised' },
]

export function PeriodAttendance({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const schoolId = claims.school_id ?? null
  const [date, setDate] = useState(todayInMauritius())
  const [slotId, setSlotId] = useState<string | null>(null)
  const [local, setLocal] = useState<Record<string, AttendanceStatus>>({})

  const lessons = useQuery({
    queryKey: ['my-lessons', date],
    queryFn: () => fetchMyLessons(date),
  })

  // Default to the lesson happening now, else the first unmarked one.
  useEffect(() => {
    const list = lessons.data ?? []
    if (list.length === 0) { setSlotId(null); return }
    if (slotId && list.some((l) => l.timetable_slot_id === slotId)) return
    const now = new Date().toTimeString().slice(0, 8)
    const current = list.find((l) => l.starts_at <= now && now <= l.ends_at)
    const unmarked = list.find((l) => l.marked_count === 0)
    setSlotId((current ?? unmarked ?? list[0])!.timetable_slot_id)
  }, [lessons.data, slotId])

  useEffect(() => { setLocal({}) }, [slotId, date])

  const lesson: Lesson | undefined = useMemo(
    () => (lessons.data ?? []).find((l) => l.timetable_slot_id === slotId),
    [lessons.data, slotId],
  )

  const roster = useQuery({
    queryKey: ['set-roster', lesson?.subject_set_id, date],
    queryFn: () => fetchSetRoster(lesson!.subject_set_id, date),
    enabled: Boolean(lesson),
  })

  const prefill = useMutation({
    mutationFn: () => prefillPeriod(lesson!.timetable_slot_id, lesson!.subject_set_id, date),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['set-roster'] })
      void qc.invalidateQueries({ queryKey: ['my-lessons', date] })
    },
  })

  const statuses = useMemo(() => {
    const merged: Record<string, AttendanceStatus> = {}
    for (const s of roster.data ?? []) {
      if (s.period_status) merged[s.student_id] = s.period_status
    }
    return { ...merged, ...local }
  }, [roster.data, local])

  const started = (lesson?.marked_count ?? 0) > 0 || Object.keys(local).length > 0

  async function mark(studentId: string, status: AttendanceStatus) {
    if (!lesson || !schoolId) return
    setLocal((s) => ({ ...s, [studentId]: status }))
    await enqueuePeriodMark({
      school_id: schoolId,
      date,
      timetable_slot_id: lesson.timetable_slot_id,
      subject_set_id: lesson.subject_set_id,
      student_id: studentId,
      status,
    })
    void drain()
  }

  const counts = useMemo(() => {
    const list = roster.data ?? []
    let present = 0, absent = 0
    for (const s of list) {
      const st = statuses[s.student_id]
      if (st === 'present' || st === 'late' || st === 'school_activity') present++
      else if (st === 'absent_unauth' || st === 'absent_auth') absent++
    }
    return { total: list.length, present, absent }
  }, [roster.data, statuses])

  return (
    <div className="mx-auto w-full max-w-3xl pb-32">
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h1 className="text-lg font-semibold">Lesson Attendance</h1>
            <p className="text-sm text-slate-500">{formatLongDate(date)}</p>
          </div>
          <SyncBadge />
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-2">
          <input
            type="date" value={date} onChange={(e) => setDate(e.target.value)}
            className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium"
          />
          {lesson && (
            <span className="text-xs text-slate-500">
              Cycle day {lesson.cycle_day}
            </span>
          )}
        </div>

        {(lessons.data ?? []).length > 0 && (
          <div className="-mx-4 mt-3 flex gap-2 overflow-x-auto px-4 pb-1">
            {(lessons.data ?? []).map((l) => {
              const active = l.timetable_slot_id === slotId
              const done = l.marked_count > 0
              return (
                <button
                  key={l.timetable_slot_id}
                  onClick={() => setSlotId(l.timetable_slot_id)}
                  className={`shrink-0 rounded-lg border px-3 py-2 text-left ${
                    active ? 'border-brand bg-brand-light' : 'border-slate-200 bg-white'
                  }`}
                >
                  <p className="text-xs font-semibold">
                    {l.period_name} · {l.starts_at.slice(0, 5)}
                  </p>
                  <p className="text-xs text-slate-600">{l.subject_name}</p>
                  <p className="text-[10px] text-slate-400">
                    {l.class_hint} · {l.room_code}
                    {done && ` · ✓ ${l.marked_count}/${l.roster_count}`}
                  </p>
                </button>
              )
            })}
          </div>
        )}

        {lesson && started && (
          <div className="mt-3 flex flex-wrap gap-3 text-sm">
            <Stat label="In set" value={counts.total} />
            <Stat label="Present" value={counts.present} tone="text-present" />
            <Stat label="Absent" value={counts.absent} tone="text-absent" />
          </div>
        )}
      </header>

      {lessons.isLoading && <p className="px-4 py-8 text-sm text-slate-500">Loading…</p>}

      {!lessons.isLoading && (lessons.data ?? []).length === 0 && (
        <div className="px-4 py-12 text-center">
          <p className="text-sm font-medium text-slate-700">No lessons on this date</p>
          <p className="mt-1 text-xs text-slate-400">
            Either you teach nothing this cycle day, or it is not a teaching day.
          </p>
        </div>
      )}

      {lesson && !started && (
        <div className="px-4 py-12 text-center">
          <p className="text-sm font-medium text-slate-700">
            {lesson.subject_name} · {lesson.period_name}
          </p>
          <p className="mt-1 text-xs text-slate-400">
            Starts from this morning's register, so you only change who left.
          </p>
          <button
            onClick={() => prefill.mutate()}
            disabled={prefill.isPending}
            className="mt-4 h-11 rounded-lg bg-brand px-5 text-sm font-semibold text-white disabled:opacity-50"
          >
            {prefill.isPending ? 'Preparing…' : 'Take lesson attendance'}
          </button>
        </div>
      )}

      {lesson && started && (
        <ul className="divide-y divide-slate-100">
          {(roster.data ?? []).map((s) => {
            const current = statuses[s.student_id]
            const absentThisMorning =
              s.register_status === 'absent_unauth' || s.register_status === 'absent_auth'
            return (
              <li key={s.student_id} className="flex items-center gap-3 px-4 py-2.5">
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium">{displayName(s)}</p>
                  <p className="text-xs text-slate-400">
                    {s.admission_number}
                    {absentThisMorning && (
                      <span className="ml-1.5 rounded bg-red-50 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-absent">
                        Absent AM
                      </span>
                    )}
                  </p>
                </div>
                <div className="flex shrink-0 gap-1">
                  {STATUSES.map((st) => {
                    const active = current === st.value
                    return (
                      <button
                        key={st.value}
                        aria-label={`${displayName(s)}: ${st.label}`}
                        aria-pressed={active}
                        title={st.label}
                        onClick={() => void mark(s.student_id, st.value)}
                        className={`status-pill ${
                          active ? st.cls
                                 : 'border-slate-200 bg-white text-slate-400 hover:border-slate-300'
                        }`}
                      >
                        {st.short}
                      </button>
                    )
                  })}
                </div>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}

function Stat({ label, value, tone = 'text-slate-700' }: {
  label: string; value: number; tone?: string
}) {
  return (
    <span className="inline-flex items-baseline gap-1">
      <span className={`text-base font-semibold tabular-nums ${tone}`}>{value}</span>
      <span className="text-xs text-slate-500">{label}</span>
    </span>
  )
}
