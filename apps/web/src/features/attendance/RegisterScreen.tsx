import { useEffect, useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import type { AttendanceStatus, SessionType } from '@/types/database'
import { displayName, formatLongDate, todayInMauritius } from '@/lib/format'
import { roleScopeIds, type EduClaims } from '@/lib/supabase'
import { fetchMyClasses, fetchNearestTeachingDay, fetchSchoolDay } from './api'
import { useRegister } from './useRegister'
import { SyncBadge } from '@/components/SyncBadge'

const STATUSES: { value: AttendanceStatus; short: string; label: string; cls: string }[] = [
  { value: 'present',       short: 'P',  label: 'Present',            cls: 'bg-present text-white border-present' },
  { value: 'absent_unauth', short: 'A',  label: 'Absent',             cls: 'bg-absent text-white border-absent' },
  { value: 'late',          short: 'L',  label: 'Late',               cls: 'bg-late text-white border-late' },
  { value: 'absent_auth',   short: 'AA', label: 'Authorised absence', cls: 'bg-authorised text-white border-authorised' },
]

export function RegisterScreen({ claims }: { claims: EduClaims }) {
  const schoolId = claims.school_id ?? null
  const [date, setDate] = useState(todayInMauritius())
  const [session, setSession] = useState<SessionType>(
    new Date().getHours() < 12 ? 'am' : 'pm',
  )
  const [classId, setClassId] = useState<string | null>(null)
  const [query, setQuery] = useState('')

  const classes = useQuery({ queryKey: ['my-classes'], queryFn: fetchMyClasses })

  // Narrow the picker to classes this person is Form Teacher of. Someone with
  // attendance.mark.any (Usher, Deputy Rector) keeps the whole list.
  const myClassIds = roleScopeIds(claims, 'form_teacher')
  const canMarkAny = Boolean(claims.caps?.includes('attendance.mark.any'))
  const selectable = useMemo(() => {
    const all = classes.data ?? []
    if (canMarkAny || myClassIds.length === 0) return all
    return all.filter((c) => myClassIds.includes(c.id))
  }, [classes.data, canMarkAny, myClassIds.join(',')])

  const activeClass = classId ?? selectable[0]?.id ?? null

  // The school calendar decides whether a register may exist at all.
  const day = useQuery({
    queryKey: ['school-day', date],
    queryFn: () => fetchSchoolDay(date),
  })
  const nearest = useQuery({
    queryKey: ['nearest-teaching-day', date],
    queryFn: () => fetchNearestTeachingDay(date),
    // Also runs when the date is outside the school year entirely (data === null),
    // which is the common case during the long between-term breaks.
    enabled: !day.isLoading && day.data?.day_type !== 'teaching',
  })

  const isTeachingDay = day.data?.day_type === 'teaching'
  const reg = useRegister(isTeachingDay ? activeClass : null, date, session, schoolId)

  useEffect(() => { setQuery('') }, [activeClass, date, session])

  const visible = useMemo(() => {
    const list = reg.roster.data ?? []
    if (!query.trim()) return list
    const q = query.toLowerCase()
    return list.filter(
      (s) =>
        s.first_name.toLowerCase().includes(q) ||
        s.last_name.toLowerCase().includes(q) ||
        s.admission_number.toLowerCase().includes(q),
    )
  }, [reg.roster.data, query])

  const isOpen = reg.session.data?.status === 'open'
  const isClosed = reg.session.data?.status === 'closed'

  return (
    <div className="mx-auto w-full max-w-3xl pb-32">
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h1 className="text-lg font-semibold">Attendance Register</h1>
            <p className="text-sm text-slate-500">{formatLongDate(date)}</p>
          </div>
          <SyncBadge />
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-2">
          <input
            type="date"
            value={date}
            onChange={(e) => { setDate(e.target.value); setClassId(classId) }}
            className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium"
          />

          <select
            value={activeClass ?? ''}
            onChange={(e) => setClassId(e.target.value)}
            className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium"
          >
            {selectable.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}{c.stream === 'extended' ? ' · Extended' : ''}
              </option>
            ))}
          </select>

          {/* Attendance is taken twice daily, morning and afternoon. */}
          <div className="inline-flex overflow-hidden rounded-lg border border-slate-300">
            {(['am', 'pm'] as SessionType[]).map((s) => (
              <button
                key={s}
                onClick={() => setSession(s)}
                className={`h-10 px-4 text-sm font-semibold uppercase ${
                  session === s ? 'bg-brand text-white' : 'bg-white text-slate-600'
                }`}
              >
                {s}
              </button>
            ))}
          </div>

          {isTeachingDay && reg.session.data == null && !reg.session.isLoading && (
            <button
              onClick={() => reg.open.mutate()}
              disabled={reg.open.isPending || !activeClass}
              className="h-10 rounded-lg bg-brand px-4 text-sm font-semibold text-white disabled:opacity-50"
            >
              {reg.open.isPending ? 'Opening…' : 'Open register'}
            </button>
          )}

          {isOpen && (
            <button
              onClick={() => reg.close.mutate()}
              className="h-10 rounded-lg border border-slate-300 px-4 text-sm font-semibold"
            >
              Close register
            </button>
          )}
        </div>

        {reg.session.data && (
          <div className="mt-3 flex flex-wrap items-center gap-3 text-sm">
            <Stat label="On roll" value={reg.counts.total} />
            <Stat label="Present" value={reg.counts.present} tone="text-present" />
            <Stat label="Absent" value={reg.counts.absent} tone="text-absent" />
            <Stat label="Late" value={reg.counts.late} tone="text-late" />
            <Stat label="Authorised" value={reg.counts.authorised} tone="text-authorised" />
            {isClosed && (
              <span className="rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-600">
                Closed — amendments need a reason
              </span>
            )}
          </div>
        )}
      </header>

      {/* Non-teaching day: explain why, and offer the nearest day that works. */}
      {day.data && !isTeachingDay && (
        <NonTeachingDay
          dayType={day.data.day_type}
          reason={day.data.closure_reason ?? day.data.note}
          nearest={nearest.data ?? null}
          onJump={(d) => setDate(d)}
        />
      )}

      {day.data === null && !day.isLoading && (
        <NonTeachingDay
          dayType="out_of_year"
          reason={null}
          nearest={nearest.data ?? null}
          onJump={(d) => setDate(d)}
        />
      )}

      {isTeachingDay && reg.session.data && (
        <div className="px-4 py-3">
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search name or admission number"
            className="h-11 w-full rounded-lg border border-slate-300 px-3 text-sm"
          />
        </div>
      )}

      {isTeachingDay && reg.isLoading && (
        <p className="px-4 py-8 text-sm text-slate-500">Loading…</p>
      )}

      {isTeachingDay && !reg.isLoading && !reg.session.data && (
        <Notice
          title={`No ${session.toUpperCase()} register opened yet`}
          body="Opening it marks everyone present — change only the exceptions."
        />
      )}

      <ul className="divide-y divide-slate-100">
        {visible.map((s) => {
          const current = reg.statuses[s.student_id]
          return (
            <li key={s.student_id} className="flex items-center gap-3 px-4 py-2.5">
              <div className="w-8 shrink-0 text-right text-xs tabular-nums text-slate-400">
                {s.roll_number ?? '—'}
              </div>
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">
                  {displayName(s)}
                  {s.is_class_captain && (
                    <span className="ml-1.5 rounded bg-brand-light px-1.5 py-0.5 text-[10px] font-semibold uppercase text-brand">
                      Captain
                    </span>
                  )}
                </p>
                <p className="text-xs text-slate-400">{s.admission_number}</p>
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
                      disabled={!isOpen}
                      onClick={() => void reg.mark(s.student_id, st.value)}
                      className={`status-pill ${
                        active
                          ? st.cls
                          : 'border-slate-200 bg-white text-slate-400 hover:border-slate-300'
                      } ${!isOpen ? 'cursor-not-allowed opacity-50' : ''}`}
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
    </div>
  )
}

function NonTeachingDay({ dayType, reason, nearest, onJump }: {
  dayType: string
  reason: string | null
  nearest: string | null
  onJump: (d: string) => void
}) {
  const titles: Record<string, string> = {
    weekend: 'Weekend — no school',
    holiday: 'Public holiday',
    closure: 'School closed',
    exam_only: 'Examinations only',
    activity: 'School activity day',
    out_of_year: 'Outside the school year',
  }
  return (
    <div className="px-4 py-12 text-center">
      <p className="text-sm font-medium text-slate-700">
        {titles[dayType] ?? 'No school on this date'}
      </p>
      {reason && <p className="mt-1 text-sm text-slate-500">{reason}</p>}
      <p className="mt-1 text-xs text-slate-400">
        {dayType === 'out_of_year'
          ? 'This date is not in the 2026 academic calendar — it falls between terms.'
          : 'A register can only be opened on a teaching day.'}
      </p>
      {nearest && (
        <button
          onClick={() => onJump(nearest)}
          className="mt-4 h-10 rounded-lg border border-slate-300 px-4 text-sm font-semibold"
        >
          Go to last teaching day ({formatLongDate(nearest)})
        </button>
      )}
    </div>
  )
}

function Notice({ title, body }: { title: string; body: string }) {
  return (
    <div className="px-4 py-12 text-center">
      <p className="text-sm font-medium text-slate-700">{title}</p>
      <p className="mt-1 text-xs text-slate-400">{body}</p>
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
