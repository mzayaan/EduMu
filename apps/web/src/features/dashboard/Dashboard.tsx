import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { supabase, type EduClaims, hasCap } from '@/lib/supabase'
import { displayName, formatLongDate, todayInMauritius } from '@/lib/format'

async function fetchDashboard(date: string) {
  const { data, error } = await supabase.rpc('school_dashboard', { p_date: date })
  if (error) throw error
  return data as Record<string, number | string>
}

async function fetchAtRisk() {
  const { data, error } = await supabase
    .from('pupils_at_risk')
    .select('*')
    .order('attendance_pct', { nullsFirst: false })
    .limit(15)
  if (error) throw error
  return data ?? []
}

async function fetchResults() {
  const { data, error } = await supabase
    .from('results_by_subject')
    .select('subject_name,grade,term_name,entries,mean_score,pass_rate,credits')
    .order('pass_rate')
  if (error) throw error
  return data ?? []
}

async function fetchRoll() {
  const { data, error } = await supabase.rpc('roll_return', { p_date: todayInMauritius() })
  if (error) throw error
  return data ?? []
}

async function fetchMinistryReturn(yearId: string) {
  const { data, error } = await supabase.rpc('ministry_return', { p_year: yearId })
  if (error) throw error
  return data
}

/** Things needing someone's attention today, ordered by urgency. */
const ATTENTION: { key: string; label: string; tone: 'bad' | 'warn' }[] = [
  { key: 'absent_unauthorised_today', label: 'Unauthorised absences today', tone: 'bad' },
  { key: 'open_discrepancies', label: 'Unresolved discrepancies', tone: 'bad' },
  { key: 'below_attendance_threshold', label: 'Below the 80% threshold', tone: 'bad' },
  { key: 'pending_absence_notes', label: 'Absence notes awaiting a decision', tone: 'warn' },
  { key: 'open_conduct_cases', label: 'Open conduct cases', tone: 'warn' },
  { key: 'marks_awaiting_moderation', label: 'Marks awaiting moderation', tone: 'warn' },
  { key: 'marks_awaiting_publication', label: 'Marks awaiting publication', tone: 'warn' },
  { key: 'overdue_actions', label: 'Overdue action items', tone: 'warn' },
  { key: 'staff_on_leave_today', label: 'Staff on leave today', tone: 'warn' },
]

export function Dashboard({ claims }: { claims: EduClaims }) {
  const [date] = useState(todayInMauritius())
  const [showReturn, setShowReturn] = useState(false)

  const dash = useQuery({ queryKey: ['dashboard', date], queryFn: () => fetchDashboard(date) })
  const atRisk = useQuery({ queryKey: ['at-risk'], queryFn: fetchAtRisk })
  const results = useQuery({ queryKey: ['results-by-subject'], queryFn: fetchResults })
  const roll = useQuery({ queryKey: ['roll'], queryFn: fetchRoll })
  const ministry = useQuery({
    queryKey: ['ministry-return', claims.year_id],
    queryFn: () => fetchMinistryReturn(claims.year_id!),
    enabled: showReturn && Boolean(claims.year_id),
  })

  const d = dash.data ?? {}
  const attention = ATTENTION.filter((a) => Number(d[a.key] ?? 0) > 0)

  return (
    <div className="mx-auto w-full max-w-4xl pb-32">
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <h1 className="text-lg font-semibold">School Dashboard</h1>
        <p className="text-sm text-slate-500">{formatLongDate(date)}</p>
      </header>

      <div className="px-4 py-4">
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Tile label="On roll" value={d.on_roll} />
          <Tile label="Staff" value={d.staff} />
          <Tile label="Registers taken" value={d.registers_taken} />
          <Tile label="Absent today" value={d.absent_unauthorised_today}
                tone={Number(d.absent_unauthorised_today ?? 0) > 0 ? 'bad' : 'good'} />
        </div>

        <h2 className="mt-6 text-sm font-semibold">Needs attention</h2>
        {attention.length === 0 ? (
          <p className="mt-2 text-sm text-slate-500">Nothing outstanding.</p>
        ) : (
          <ul className="mt-2 divide-y divide-slate-100">
            {attention.map((a) => (
              <li key={a.key} className="flex items-center justify-between py-2">
                <span className="text-sm">{a.label}</span>
                <span className={`text-base font-semibold tabular-nums ${
                  a.tone === 'bad' ? 'text-absent' : 'text-late'}`}>
                  {String(d[a.key])}
                </span>
              </li>
            ))}
          </ul>
        )}

        {(roll.data ?? []).length > 0 && (
          <>
            <h2 className="mt-6 text-sm font-semibold">Roll by grade</h2>
            <table className="mt-2 w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-slate-500">
                  <th className="p-2">Grade</th><th className="p-2">Boys</th>
                  <th className="p-2">Girls</th><th className="p-2">Total</th>
                </tr>
              </thead>
              <tbody>
                {(roll.data ?? []).map((r: any) => (
                  <tr key={r.grade} className="border-t border-slate-100">
                    <td className="p-2 font-medium">Grade {r.grade}</td>
                    <td className="p-2 tabular-nums">{r.male}</td>
                    <td className="p-2 tabular-nums">{r.female}</td>
                    <td className="p-2 font-semibold tabular-nums">{r.total}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </>
        )}

        {(atRisk.data ?? []).length > 0 && (
          <>
            <h2 className="mt-6 text-sm font-semibold">Pupils needing attention</h2>
            <ul className="mt-2 divide-y divide-slate-100">
              {(atRisk.data ?? [])
                .filter((p: any) => p.attendance_pct !== null && p.attendance_pct < 80)
                .map((p: any) => (
                <li key={p.student_id} className="flex items-center justify-between py-2">
                  <div>
                    <p className="text-sm font-medium">{displayName(p)}</p>
                    <p className="text-xs text-slate-400">
                      {p.class_name} · {p.admission_number}
                      {p.open_cases > 0 && ` · ${p.open_cases} open case(s)`}
                      {p.recent_incidents > 0 && ` · ${p.recent_incidents} recent incident(s)`}
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="text-base font-semibold tabular-nums text-absent">
                      {p.attendance_pct}%
                    </p>
                    {p.mean_score !== null && (
                      <p className="text-xs text-slate-400">mean {p.mean_score}%</p>
                    )}
                  </div>
                </li>
              ))}
            </ul>
          </>
        )}

        {(results.data ?? []).length > 0 && (
          <>
            <h2 className="mt-6 text-sm font-semibold">Results by subject</h2>
            <table className="mt-2 w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-slate-500">
                  <th className="p-2">Subject</th><th className="p-2">Entries</th>
                  <th className="p-2">Mean</th><th className="p-2">Pass rate</th>
                </tr>
              </thead>
              <tbody>
                {(results.data ?? []).map((r: any, i: number) => (
                  <tr key={i} className="border-t border-slate-100">
                    <td className="p-2">{r.subject_name}</td>
                    <td className="p-2 tabular-nums">{r.entries}</td>
                    <td className="p-2 tabular-nums">{r.mean_score}%</td>
                    <td className={`p-2 font-semibold tabular-nums ${
                      r.pass_rate < 60 ? 'text-absent' : 'text-present'}`}>
                      {r.pass_rate}%
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </>
        )}

        {hasCap(claims, 'school.manage') && (
          <div className="mt-8">
            <button onClick={() => setShowReturn((v) => !v)}
                    className="h-10 rounded-lg border border-slate-300 px-4 text-sm font-semibold">
              {showReturn ? 'Hide' : 'Generate'} Ministry statistical return
            </button>
            {showReturn && ministry.data && (
              <>
                <p className="mt-2 text-xs text-slate-400">
                  Roll by grade, teaching days per term, attendance, staff by post
                  and results — as one document. Copy or export as required.
                </p>
                <pre className="mt-2 max-h-96 overflow-auto rounded-lg bg-slate-900 p-3
                                text-xs text-slate-100">
                  {JSON.stringify(ministry.data, null, 2)}
                </pre>
              </>
            )}
          </div>
        )}
      </div>
    </div>
  )
}

function Tile({ label, value, tone = 'neutral' }: {
  label: string; value: unknown; tone?: 'neutral' | 'good' | 'bad'
}) {
  const colour = tone === 'bad' ? 'text-absent' : tone === 'good' ? 'text-present' : 'text-ink'
  return (
    <div className="rounded-xl border border-slate-200 p-3">
      <p className={`text-2xl font-semibold tabular-nums ${colour}`}>
        {value === undefined || value === null ? '—' : String(value)}
      </p>
      <p className="mt-0.5 text-xs text-slate-500">{label}</p>
    </div>
  )
}
