import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { hasCap, type EduClaims } from '@/lib/supabase'
import { formatDate, todayInMauritius } from '@/lib/format'
import { fetchTerms } from '@/features/marks/api'
import { fetchMySets } from '@/features/marks/api'
import * as api from './api'
import type { PlanStatus, SchemeRow } from './api'

type Panel = 'schemes' | 'weekly' | 'homework' | 'coverage'

const STATUS_LABEL: Record<PlanStatus, string> = {
  draft: 'Not submitted',
  submitted: 'With the HOD',
  hod_returned: 'Returned for revision',
  hod_approved: 'Vetted — awaiting the Rector',
  rector_approved: 'Approved',
}
const STATUS_TONE: Record<PlanStatus, string> = {
  draft: 'bg-slate-100 text-slate-600',
  submitted: 'bg-amber-50 text-amber-800',
  hod_returned: 'bg-red-50 text-absent',
  hod_approved: 'bg-violet-50 text-violet-700',
  rector_approved: 'bg-green-50 text-present',
}

export function CurriculumScreen({ claims }: { claims: EduClaims }) {
  const [panel, setPanel] = useState<Panel>('schemes')
  return (
    <div className="mx-auto w-full max-w-4xl pb-32">
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <h1 className="text-lg font-semibold">Curriculum</h1>
        <p className="text-sm text-slate-500">
          Schemes of work, weekly plans and homework
        </p>
        <nav className="mt-3 flex gap-1 overflow-x-auto">
          {(['schemes', 'weekly', 'homework', 'coverage'] as Panel[]).map((p) => (
            <button key={p} onClick={() => setPanel(p)}
              className={`h-9 shrink-0 rounded-lg px-3 text-sm font-medium capitalize ${
                panel === p ? 'bg-brand text-white' : 'text-slate-600 hover:bg-slate-100'}`}>
              {p === 'weekly' ? 'Weekly plan' : p}
            </button>
          ))}
        </nav>
      </header>

      {panel === 'schemes' && <Schemes claims={claims} />}
      {panel === 'weekly' && <Weekly claims={claims} />}
      {panel === 'homework' && <Homework claims={claims} />}
      {panel === 'coverage' && <Coverage />}
    </div>
  )
}

function Schemes({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [termId, setTermId] = useState<string | null>(null)
  const [openId, setOpenId] = useState<string | null>(null)
  const [comment, setComment] = useState('')
  const [error, setError] = useState<string | null>(null)

  const terms = useQuery({ queryKey: ['terms'], queryFn: fetchTerms })
  useEffect(() => { if (!termId && terms.data?.length) setTermId(terms.data[0]!.id) }, [terms.data, termId])

  const rows = useQuery({
    queryKey: ['scheme-status', termId],
    queryFn: () => api.fetchSchemeStatus(termId!),
    enabled: Boolean(termId),
  })

  const isHod = hasCap(claims, 'marks.moderate')
  const isRector = hasCap(claims, 'school.manage')

  const act = useMutation({
    mutationFn: async (v: { row: SchemeRow; action: string }) => {
      let id = v.row.scheme_id
      if (!id) {
        id = await api.ensureScheme({
          school_id: claims.school_id!, academic_year_id: claims.year_id!,
          subject_set_id: v.row.subject_set_id, staff_id: v.row.staff_id,
          term_id: termId!, due_on: null,
        })
      }
      if (v.action === 'submit') await api.submitScheme(id)
      if (v.action === 'approve_hod') await api.reviewScheme(id, true)
      if (v.action === 'return') await api.reviewScheme(id, false, comment)
      if (v.action === 'approve_rector') await api.approveScheme(id)
    },
    onSuccess: () => {
      setError(null); setComment(''); setOpenId(null)
      void qc.invalidateQueries({ queryKey: ['scheme-status'] })
    },
    onError: (e: any) => setError(e.message),
  })

  const outstanding = (rows.data ?? []).filter(
    (r) => r.status !== 'rector_approved').length

  return (
    <div className="px-4 py-4">
      <div className="flex flex-wrap items-center gap-2">
        <select value={termId ?? ''} onChange={(e) => setTermId(e.target.value)}
                className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium">
          {(terms.data ?? []).map((t: any) => <option key={t.id} value={t.id}>{t.name}</option>)}
        </select>
        <span className="text-xs text-slate-500">
          {outstanding} of {(rows.data ?? []).length} outstanding
        </span>
      </div>

      {error && <p className="mt-3 text-sm text-absent">{error}</p>}

      <ul className="mt-4 divide-y divide-slate-100">
        {(rows.data ?? []).map((r) => {
          const mine = r.staff_id === claims.person_id
          return (
            <li key={r.subject_set_id} className="py-3">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{r.set_name}</p>
                  <p className="text-xs text-slate-400">
                    {r.staff_name}{r.department && ` · ${r.department}`}
                    {r.weeks > 0 && ` · ${r.weeks} week(s) planned`}
                  </p>
                  {r.hod_comment && r.status === 'hod_returned' && (
                    <p className="mt-1 text-xs text-absent">HOD: {r.hod_comment}</p>
                  )}
                </div>
                <span className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase ${STATUS_TONE[r.status]}`}>
                  {STATUS_LABEL[r.status]}
                </span>
              </div>

              <div className="mt-2 flex flex-wrap gap-1.5">
                {mine && (r.status === 'draft' || r.status === 'hod_returned') && (
                  <button onClick={() => act.mutate({ row: r, action: 'submit' })}
                          disabled={act.isPending}
                          className="h-9 rounded-lg border border-slate-200 px-3 text-xs font-medium
                                     hover:border-brand hover:text-brand">
                    Submit to HOD
                  </button>
                )}
                {isHod && r.status === 'submitted' && (
                  <>
                    <button onClick={() => act.mutate({ row: r, action: 'approve_hod' })}
                            className="h-9 rounded-lg border border-slate-200 px-3 text-xs font-medium
                                       hover:border-present hover:text-present">
                      Vet and pass on
                    </button>
                    <button onClick={() => setOpenId(openId === r.subject_set_id ? null : r.subject_set_id)}
                            className="h-9 rounded-lg border border-slate-200 px-3 text-xs font-medium
                                       hover:border-absent hover:text-absent">
                      Return…
                    </button>
                  </>
                )}
                {isRector && r.status === 'hod_approved' && (
                  <button onClick={() => act.mutate({ row: r, action: 'approve_rector' })}
                          className="h-9 rounded-lg bg-brand px-3 text-xs font-semibold text-white">
                    Approve
                  </button>
                )}
              </div>

              {openId === r.subject_set_id && (
                <div className="mt-2 flex gap-2">
                  <input value={comment} onChange={(e) => setComment(e.target.value)}
                         placeholder="What needs changing? (required)"
                         className="h-9 flex-1 rounded-lg border border-slate-300 px-2.5 text-xs" />
                  <button disabled={comment.trim() === ''}
                          onClick={() => act.mutate({ row: r, action: 'return' })}
                          className="h-9 rounded-lg bg-absent px-3 text-xs font-semibold text-white disabled:opacity-40">
                    Return
                  </button>
                </div>
              )}
            </li>
          )
        })}
      </ul>
    </div>
  )
}

function Weekly({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [setId, setSetId] = useState<string | null>(null)
  const [week, setWeek] = useState(mondayOf(todayInMauritius()))
  const [error, setError] = useState<string | null>(null)

  const sets = useQuery({ queryKey: ['my-sets'], queryFn: fetchMySets })
  useEffect(() => { if (!setId && sets.data?.length) setSetId(sets.data[0]!.id) }, [sets.data, setId])

  const plan = useQuery({
    queryKey: ['weekly-plan', setId, week],
    queryFn: () => api.fetchWeeklyPlan(setId!, week),
    enabled: Boolean(setId),
  })

  const generate = useMutation({
    mutationFn: () => api.generateWeeklyPlan(setId!, week),
    onSuccess: () => { setError(null); void qc.invalidateQueries({ queryKey: ['weekly-plan'] }) },
    onError: (e: any) => setError(e.message),
  })

  const cover = useMutation({
    mutationFn: (v: { id: string; actual: string; covered: boolean; remarks?: string }) =>
      api.recordCoverage(v.id, v.actual, v.covered, v.remarks),
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['weekly-plan'] }) },
  })

  return (
    <div className="px-4 py-4">
      <div className="flex flex-wrap items-center gap-2">
        <select value={setId ?? ''} onChange={(e) => setSetId(e.target.value)}
                className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium">
          {(sets.data ?? []).map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
        </select>
        <input type="date" value={week} onChange={(e) => setWeek(mondayOf(e.target.value))}
               className="h-10 rounded-lg border border-slate-300 px-3 text-sm font-medium" />
        <button onClick={() => generate.mutate()} disabled={generate.isPending || !setId}
                className="h-10 rounded-lg bg-brand px-4 text-sm font-semibold text-white disabled:opacity-50">
          {generate.isPending ? 'Building…' : 'Build from timetable'}
        </button>
      </div>
      <p className="mt-1 text-xs text-slate-400">
        Week beginning {formatDate(week)}. Rows come from the published timetable,
        so you fill in content rather than re-deriving your own week.
      </p>

      {error && <p className="mt-3 text-sm text-absent">{error}</p>}

      {!plan.data && !plan.isLoading && (
        <p className="py-10 text-center text-sm text-slate-500">
          No plan for this week yet.
        </p>
      )}

      {plan.data && (
        <ul className="mt-4 divide-y divide-slate-100">
          {plan.data.rows.map((r: any) => (
            <PlanRow key={r.id} row={r}
                     onPlan={(v) => api.savePlanRow(r.id, v).then(() =>
                       qc.invalidateQueries({ queryKey: ['weekly-plan'] }))}
                     onCover={(actual, covered, remarks) =>
                       cover.mutate({ id: r.id, actual, covered, remarks })} />
          ))}
        </ul>
      )}
    </div>
  )
}

function PlanRow({ row, onPlan, onCover }: {
  row: any
  onPlan: (v: string) => void
  onCover: (actual: string, covered: boolean, remarks?: string) => void
}) {
  const [planned, setPlanned] = useState(row.planned ?? '')
  const [actual, setActual] = useState(row.actual ?? '')
  const [remarks, setRemarks] = useState(row.remarks ?? '')

  return (
    <li className="py-3">
      <p className="text-xs font-semibold text-slate-500">{formatDate(row.date)}</p>
      <input value={planned} onChange={(e) => setPlanned(e.target.value)}
             onBlur={() => planned !== (row.planned ?? '') && onPlan(planned)}
             placeholder="Planned work"
             className="mt-1 h-10 w-full rounded-lg border border-slate-300 px-2.5 text-sm" />
      <div className="mt-1.5 flex flex-wrap gap-2">
        <input value={actual} onChange={(e) => setActual(e.target.value)}
               placeholder="What was actually covered"
               className="h-10 flex-1 rounded-lg border border-slate-200 px-2.5 text-sm" />
        <input value={remarks} onChange={(e) => setRemarks(e.target.value)}
               placeholder="Remarks"
               className="h-10 w-40 rounded-lg border border-slate-200 px-2.5 text-sm" />
        <button onClick={() => onCover(actual, true, remarks)}
                className="h-10 rounded-lg border border-slate-200 px-3 text-xs font-medium
                           hover:border-present hover:text-present">
          Covered
        </button>
        <button onClick={() => onCover(actual, false, remarks)}
                className="h-10 rounded-lg border border-slate-200 px-3 text-xs font-medium
                           hover:border-late hover:text-late">
          Not covered
        </button>
      </div>
      {row.covered !== null && (
        <p className={`mt-1 text-xs ${row.covered ? 'text-present' : 'text-late'}`}>
          {row.covered ? 'Recorded as covered' : 'Recorded as not covered'}
          {row.remarks && ` — ${row.remarks}`}
        </p>
      )}
    </li>
  )
}

function Homework({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [setId, setSetId] = useState<string | null>(null)
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [due, setDue] = useState(todayInMauritius())
  const [minutes, setMinutes] = useState(30)

  const sets = useQuery({ queryKey: ['my-sets'], queryFn: fetchMySets })
  useEffect(() => { if (!setId && sets.data?.length) setSetId(sets.data[0]!.id) }, [sets.data, setId])

  const list = useQuery({
    queryKey: ['homework', setId], queryFn: () => api.fetchHomework(setId!),
    enabled: Boolean(setId),
  })

  const create = useMutation({
    mutationFn: () => api.setHomework({
      school_id: claims.school_id!, subject_set_id: setId!, set_by: claims.person_id!,
      title, description, due_on: due, estimated_minutes: minutes,
    }),
    onSuccess: () => {
      setTitle(''); setDescription('')
      void qc.invalidateQueries({ queryKey: ['homework'] })
    },
  })

  return (
    <div className="px-4 py-4">
      <select value={setId ?? ''} onChange={(e) => setSetId(e.target.value)}
              className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium">
        {(sets.data ?? []).map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
      </select>

      <div className="mt-3 space-y-2 rounded-xl border border-slate-200 p-4">
        <input value={title} onChange={(e) => setTitle(e.target.value)}
               placeholder="Title, e.g. Exercise 4.2 — simultaneous equations"
               className="h-10 w-full rounded-lg border border-slate-300 px-2.5 text-sm" />
        <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={2}
                  placeholder="Instructions"
                  className="w-full rounded-lg border border-slate-300 p-2 text-sm" />
        <div className="flex flex-wrap items-end gap-2">
          <label className="text-xs font-medium">
            Due
            <input type="date" value={due} onChange={(e) => setDue(e.target.value)}
                   className="mt-1 h-10 rounded-lg border border-slate-300 px-2 text-sm" />
          </label>
          <label className="text-xs font-medium">
            Minutes
            <input type="number" min={5} max={180} value={minutes}
                   onChange={(e) => setMinutes(Number(e.target.value))}
                   className="mt-1 h-10 w-20 rounded-lg border border-slate-300 px-2 text-sm" />
          </label>
          <button disabled={title.trim() === '' || create.isPending}
                  onClick={() => create.mutate()}
                  className="h-10 rounded-lg bg-brand px-4 text-sm font-semibold text-white disabled:opacity-40">
            Set homework
          </button>
        </div>
        <p className="text-xs text-slate-400">
          Pupils and their Responsible Parties see this immediately.
        </p>
      </div>

      <ul className="mt-4 divide-y divide-slate-100">
        {(list.data ?? []).map((h: any) => (
          <li key={h.id} className="py-3">
            <div className="flex items-start justify-between gap-2">
              <p className="text-sm font-medium">{h.title}</p>
              <span className="shrink-0 text-xs text-slate-400">Due {formatDate(h.due_on)}</span>
            </div>
            {h.description && <p className="mt-0.5 text-sm text-slate-600">{h.description}</p>}
            <p className="text-xs text-slate-400">
              Set {formatDate(h.set_on)}
              {h.estimated_minutes && ` · about ${h.estimated_minutes} minutes`}
            </p>
          </li>
        ))}
      </ul>
    </div>
  )
}

function Coverage() {
  const rows = useQuery({ queryKey: ['coverage'], queryFn: api.fetchCoverage })
  const withData = (rows.data ?? []).filter((r: any) => r.periods_recorded > 0)

  return (
    <div className="px-4 py-4">
      <p className="text-xs text-slate-500">
        Built from what educators recorded as actually covered — not from what
        was planned. The earliest reliable sign that a class is falling behind.
      </p>
      {withData.length === 0 ? (
        <p className="py-10 text-center text-sm text-slate-500">
          No coverage recorded yet. It appears once weekly plans are filled in.
        </p>
      ) : (
        <ul className="mt-3 divide-y divide-slate-100">
          {withData.map((r: any, i: number) => (
            <li key={i} className="flex items-center justify-between py-3">
              <div>
                <p className="text-sm font-medium">{r.set_name}</p>
                <p className="text-xs text-slate-400">
                  {r.term_name} · {r.periods_covered}/{r.periods_recorded} periods
                </p>
              </div>
              <span className={`text-lg font-semibold tabular-nums ${
                r.coverage_pct >= 80 ? 'text-present'
                : r.coverage_pct >= 60 ? 'text-late' : 'text-absent'}`}>
                {r.coverage_pct}%
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

/** Weeks run Monday to Sunday; snap any chosen date back to its Monday. */
function mondayOf(iso: string): string {
  const d = new Date(iso + 'T00:00:00')
  const day = (d.getDay() + 6) % 7
  d.setDate(d.getDate() - day)
  return d.toISOString().slice(0, 10)
}
