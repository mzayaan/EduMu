import { useEffect, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { hasCap, type EduClaims } from '@/lib/supabase'
import { displayName } from '@/lib/format'
import { fetchTerms } from '@/features/marks/api'
import * as api from './api'
import { ReportCard } from './ReportCard'
import { supabase } from '@/lib/supabase'

export function ReportsScreen({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [termId, setTermId] = useState<string | null>(null)
  const [studentId, setStudentId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [printAll, setPrintAll] = useState(false)

  const terms = useQuery({ queryKey: ['terms'], queryFn: fetchTerms })

  // Several schools deliberately do not rank the lower forms. That is policy,
  // so it lives in school.settings rather than in this component.
  const settings = useQuery({
    queryKey: ['school-settings'],
    queryFn: async () => {
      const { data, error } = await supabase.from('school').select('settings').single()
      if (error) throw error
      return (data?.settings ?? {}) as { suppress_ranks_grades?: number[] }
    },
  })
  const suppressed = settings.data?.suppress_ranks_grades ?? []
  const showRankFor = (grade: number | null | undefined) =>
    grade == null || !suppressed.includes(grade)
  useEffect(() => { if (!termId && terms.data?.length) setTermId(terms.data[0]!.id) }, [terms.data, termId])

  const list = useQuery({
    queryKey: ['card-list', termId],
    queryFn: () => api.fetchCardList(termId!),
    enabled: Boolean(termId),
  })
  useEffect(() => {
    if (list.data?.length && !list.data.some((r: any) => r.student_id === studentId)) {
      setStudentId(list.data[0]!.student_id)
    }
  }, [list.data, studentId])

  const card = useQuery({
    queryKey: ['card', termId, studentId],
    queryFn: () => api.fetchCard(termId!, studentId!),
    enabled: Boolean(termId && studentId),
  })

  // Fetching every card at once is what makes a whole-class print possible.
  const allCards = useQuery({
    queryKey: ['all-cards', termId],
    queryFn: async () => {
      const rows = list.data ?? []
      return Promise.all(rows.map((r: any) => api.fetchCard(termId!, r.student_id)))
    },
    enabled: printAll && Boolean(termId) && (list.data ?? []).length > 0,
  })

  const build = useMutation({
    mutationFn: () => api.buildReportCards(termId!),
    onSuccess: () => { setError(null); void qc.invalidateQueries({ queryKey: ['card-list'] }) },
    onError: (e: any) => setError(e.message),
  })
  const publish = useMutation({
    mutationFn: () => api.publishReportCards(termId!),
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['card-list'] }) },
    onError: (e: any) => setError(e.message),
  })

  if (printAll) {
    return (
      <div>
        <div className="no-print sticky top-0 z-10 flex gap-2 border-b border-slate-200 bg-white px-4 py-3">
          <button onClick={() => window.print()}
                  className="h-10 rounded-lg bg-brand px-4 text-sm font-semibold text-white">
            Print {(allCards.data ?? []).length} cards
          </button>
          <button onClick={() => setPrintAll(false)}
                  className="h-10 rounded-lg border border-slate-300 px-4 text-sm font-semibold">
            Back
          </button>
        </div>
        {allCards.isLoading && <p className="p-8 text-sm text-slate-500">Assembling…</p>}
        {(allCards.data ?? []).map((c, i) => c && (
          <div key={i} className="page-break">
            <ReportCard card={c} showRank={showRankFor(c.class?.grade)} />
          </div>
        ))}
      </div>
    )
  }

  return (
    <div className="mx-auto w-full max-w-5xl pb-32">
      <header className="no-print sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <h1 className="text-lg font-semibold">Report Books</h1>
        <p className="text-sm text-slate-500">Assemble, comment, publish and print</p>

        <div className="mt-3 flex flex-wrap items-center gap-2">
          <select value={termId ?? ''} onChange={(e) => setTermId(e.target.value)}
                  className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium">
            {(terms.data ?? []).map((t: any) => <option key={t.id} value={t.id}>{t.name}</option>)}
          </select>
          {hasCap(claims, 'marks.moderate') && (
            <button onClick={() => build.mutate()} disabled={build.isPending}
                    className="h-10 rounded-lg bg-brand px-4 text-sm font-semibold text-white disabled:opacity-50">
              {build.isPending ? 'Building…' : 'Build / rebuild'}
            </button>
          )}
          {hasCap(claims, 'marks.publish') && (
            <button onClick={() => publish.mutate()} disabled={publish.isPending}
                    className="h-10 rounded-lg border border-slate-300 px-4 text-sm font-semibold">
              Publish to parents
            </button>
          )}
          {(list.data ?? []).length > 0 && (
            <button onClick={() => setPrintAll(true)}
                    className="h-10 rounded-lg border border-slate-300 px-4 text-sm font-semibold">
              Print all
            </button>
          )}
        </div>

        {error && <p className="mt-2 text-sm text-absent">{error}</p>}
        {build.isSuccess && <p className="mt-2 text-xs text-present">{build.data} cards built.</p>}
        {publish.isSuccess && (
          <p className="mt-2 text-xs text-present">
            {publish.data} published — Responsible Parties notified.
          </p>
        )}
      </header>

      {(list.data ?? []).length === 0 && !list.isLoading && (
        <p className="no-print px-4 py-12 text-center text-sm text-slate-500">
          No report cards for this term yet. Compute term results first, then Build.
        </p>
      )}

      <div className="grid gap-4 px-4 py-4 lg:grid-cols-[16rem_1fr]">
        <aside className="no-print">
          <ul className="divide-y divide-slate-100">
            {(list.data ?? []).map((r: any) => (
              <li key={r.student_id}>
                <button onClick={() => setStudentId(r.student_id)}
                  className={`w-full px-2 py-2 text-left ${
                    r.student_id === studentId ? 'bg-brand-light' : 'hover:bg-slate-50'}`}>
                  <p className="text-sm font-medium">
                    {r.first_name ? displayName(r) : r.student_id}
                  </p>
                  <p className="text-xs text-slate-400">
                    {r.overall_score != null ? `${r.overall_score}%` : '—'}
                    {r.overall_rank && ` · ${r.overall_rank}/${r.class_size}`}
                    {r.status === 'published' && ' · published'}
                    {!r.form_teacher_comment && ' · no comment'}
                  </p>
                </button>
              </li>
            ))}
          </ul>
        </aside>

        <div>
          {card.data && (
            <>
              <div className="rounded-xl border border-slate-200 shadow-sm">
                <ReportCard card={card.data} showRank={showRankFor(card.data.class?.grade)} />
              </div>
              <div className="no-print mt-4">
                <button onClick={() => window.print()}
                        className="h-10 rounded-lg border border-slate-300 px-4 text-sm font-semibold">
                  Print this card
                </button>
              </div>
              {termId && studentId && (
                <Comments claims={claims} termId={termId} studentId={studentId}
                          card={card.data}
                          onSaved={() => {
                            void qc.invalidateQueries({ queryKey: ['card'] })
                            void qc.invalidateQueries({ queryKey: ['card-list'] })
                          }} />
              )}
            </>
          )}
        </div>
      </div>
    </div>
  )
}

function Comments({ claims, termId, studentId, card, onSaved }: {
  claims: EduClaims; termId: string; studentId: string
  card: api.CardData; onSaved: () => void
}) {
  const [ft, setFt] = useState(card.summary?.form_teacher_comment ?? '')
  const [rec, setRec] = useState(card.summary?.rector_comment ?? '')
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    setFt(card.summary?.form_teacher_comment ?? '')
    setRec(card.summary?.rector_comment ?? '')
  }, [card])

  const save = useMutation({
    mutationFn: (v: { which: 'form_teacher' | 'rector'; text: string }) =>
      api.setComment(termId, studentId, v.which, v.text),
    onSuccess: () => { setErr(null); onSaved() },
    onError: (e: any) => setErr(e.message),
  })

  return (
    <div className="no-print mt-4 space-y-3 rounded-xl border border-slate-200 p-4">
      <p className="text-sm font-medium">Comments</p>
      {err && <p className="text-sm text-absent">{err}</p>}

      <label className="block text-xs font-medium">
        Form Teacher
        <textarea value={ft} onChange={(e) => setFt(e.target.value)} rows={2}
                  onBlur={() => ft !== (card.summary?.form_teacher_comment ?? '')
                    && save.mutate({ which: 'form_teacher', text: ft })}
                  className="mt-1 w-full rounded-lg border border-slate-300 p-2 text-sm" />
      </label>

      {hasCap(claims, 'school.manage') && (
        <label className="block text-xs font-medium">
          Rector
          <textarea value={rec} onChange={(e) => setRec(e.target.value)} rows={2}
                    onBlur={() => rec !== (card.summary?.rector_comment ?? '')
                      && save.mutate({ which: 'rector', text: rec })}
                    className="mt-1 w-full rounded-lg border border-slate-300 p-2 text-sm" />
        </label>
      )}
      <p className="text-xs text-slate-400">Saved when you click away.</p>
    </div>
  )
}
