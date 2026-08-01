import { useEffect, useMemo, useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase, type EduClaims, hasCap } from '@/lib/supabase'
import { displayName } from '@/lib/format'
import {
  computeTermResults, fetchMarksheet, fetchMySets, fetchTerms,
  setAssessmentStatus, type AssessmentStatus, type MarksheetRow,
} from './api'

const CODES = ['ABS', 'EXEMPT', 'MED', 'DEBARRED'] as const

const NEXT: Record<AssessmentStatus, { to: AssessmentStatus; label: string; cap: string } | null> = {
  draft:     { to: 'open',      label: 'Open for entry', cap: 'marks.enter' },
  open:      { to: 'submitted', label: 'Submit to HOD',  cap: 'marks.enter' },
  submitted: { to: 'moderated', label: 'Moderate',       cap: 'marks.moderate' },
  moderated: { to: 'published', label: 'Publish',        cap: 'marks.publish' },
  published: null,
}

export function MarksGrid({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [setId, setSetId] = useState<string | null>(null)
  const [termId, setTermId] = useState<string | null>(null)
  const [dirty, setDirty] = useState<Record<string, string>>({})
  const [saving, setSaving] = useState(0)

  const sets = useQuery({ queryKey: ['my-sets'], queryFn: fetchMySets })
  const terms = useQuery({ queryKey: ['terms'], queryFn: fetchTerms })

  useEffect(() => { if (!setId && sets.data?.length) setSetId(sets.data[0]!.id) }, [sets.data, setId])
  useEffect(() => { if (!termId && terms.data?.length) setTermId(terms.data[0]!.id) }, [terms.data, termId])

  const sheet = useQuery({
    queryKey: ['marksheet', setId, termId],
    queryFn: () => fetchMarksheet(setId!, termId),
    enabled: Boolean(setId),
  })

  // Pivot the flat result into students × assessments.
  const { students, assessments, byCell } = useMemo(() => {
    const rows = sheet.data ?? []
    const sMap = new Map<string, MarksheetRow>()
    const aMap = new Map<string, MarksheetRow>()
    const cells: Record<string, MarksheetRow> = {}
    for (const r of rows) {
      if (!sMap.has(r.student_id)) sMap.set(r.student_id, r)
      if (!aMap.has(r.assessment_id)) aMap.set(r.assessment_id, r)
      cells[`${r.student_id}:${r.assessment_id}`] = r
    }
    return {
      students: [...sMap.values()],
      assessments: [...aMap.values()],
      byCell: cells,
    }
  }, [sheet.data])

  const status = assessments[0]?.status ?? 'draft'
  const editable = status === 'draft' || status === 'open'
  const next = NEXT[status]

  const advance = useMutation({
    mutationFn: async (to: AssessmentStatus) => {
      for (const a of assessments) await setAssessmentStatus(a.assessment_id, to)
    },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['marksheet'] }) },
  })

  const compute = useMutation({
    mutationFn: () => computeTermResults(termId!),
  })

  async function save(studentId: string, assessmentId: string, raw: string) {
    const key = `${studentId}:${assessmentId}`
    const cell = byCell[key]
    if (!cell || !claims.school_id) return

    const trimmed = raw.trim().toUpperCase()
    const isCode = (CODES as readonly string[]).includes(trimmed)
    const score = trimmed === '' ? null : Number(trimmed)

    if (!isCode && trimmed !== '' && (Number.isNaN(score) || score! < 0 || score! > cell.max_score)) {
      return // out of range — leave the cell dirty so the teacher sees it
    }
    if (trimmed === '') return

    setSaving((n) => n + 1)
    const { error } = await supabase.from('mark').upsert(
      {
        school_id: claims.school_id,
        assessment_id: assessmentId,
        student_id: studentId,
        score: isCode ? null : score,
        code: isCode ? trimmed : null,
      },
      { onConflict: 'assessment_id,student_id' },
    )
    setSaving((n) => n - 1)
    if (!error) {
      setDirty((d) => { const { [key]: _, ...rest } = d; return rest })
      void qc.invalidateQueries({ queryKey: ['marksheet', setId, termId] })
    }
  }

  return (
    <div className="mx-auto w-full max-w-5xl pb-32">
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h1 className="text-lg font-semibold">Marks</h1>
            <p className="text-sm text-slate-500">
              {editable ? 'Enter a score, or ABS / EXEMPT / MED' : 'Locked — awaiting the next step'}
            </p>
          </div>
          <StatusPill status={status} saving={saving > 0} />
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-2">
          <select value={setId ?? ''} onChange={(e) => setSetId(e.target.value)}
                  className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium">
            {(sets.data ?? []).map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
          <select value={termId ?? ''} onChange={(e) => setTermId(e.target.value)}
                  className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium">
            {(terms.data ?? []).map((t: any) => <option key={t.id} value={t.id}>{t.name}</option>)}
          </select>

          {next && hasCap(claims, next.cap) && (
            <button
              onClick={() => advance.mutate(next.to)}
              disabled={advance.isPending}
              className="h-10 rounded-lg bg-brand px-4 text-sm font-semibold text-white disabled:opacity-50"
            >
              {advance.isPending ? 'Working…' : next.label}
            </button>
          )}

          {status === 'published' && hasCap(claims, 'marks.moderate') && (
            <button
              onClick={() => compute.mutate()}
              disabled={compute.isPending}
              className="h-10 rounded-lg border border-slate-300 px-4 text-sm font-semibold"
            >
              {compute.isPending ? 'Computing…'
                : compute.data != null ? `Computed ${compute.data} results`
                : 'Compute term results'}
            </button>
          )}
        </div>

        {status === 'published' && (
          <p className="mt-2 text-xs text-slate-500">
            Published — pupils and Responsible Parties can now see these marks.
          </p>
        )}
      </header>

      {sheet.isLoading && <p className="px-4 py-8 text-sm text-slate-500">Loading…</p>}

      {!sheet.isLoading && assessments.length === 0 && (
        <div className="px-4 py-12 text-center">
          <p className="text-sm font-medium text-slate-700">No assessments for this set and term</p>
        </div>
      )}

      {assessments.length > 0 && (
        <div className="overflow-x-auto px-4 py-3">
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr>
                <th className="sticky left-0 z-[1] bg-white p-2 text-left text-xs font-semibold text-slate-500">
                  Pupil
                </th>
                {assessments.map((a) => (
                  <th key={a.assessment_id} className="p-2 text-center text-xs font-semibold">
                    <div className="whitespace-nowrap">{a.title}</div>
                    <div className="font-normal text-slate-400">
                      /{a.max_score} · ×{a.weight}
                    </div>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {students.map((s) => (
                <tr key={s.student_id} className="border-t border-slate-100">
                  <td className="sticky left-0 z-[1] bg-white p-2 whitespace-nowrap">
                    <div className="text-sm font-medium">{displayName(s)}</div>
                    <div className="text-xs text-slate-400">{s.admission_number}</div>
                  </td>
                  {assessments.map((a) => {
                    const key = `${s.student_id}:${a.assessment_id}`
                    const cell = byCell[key]
                    const value = dirty[key] ?? (cell?.code ?? cell?.score?.toString() ?? '')
                    const over = !dirty[key] ? false
                      : !(CODES as readonly string[]).includes(dirty[key]!.trim().toUpperCase())
                        && Number(dirty[key]) > a.max_score
                    return (
                      <td key={a.assessment_id} className="p-1 text-center">
                        <input
                          value={value}
                          disabled={!editable}
                          onChange={(e) => setDirty((d) => ({ ...d, [key]: e.target.value }))}
                          onBlur={(e) => void save(s.student_id, a.assessment_id, e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter') (e.target as HTMLInputElement).blur()
                          }}
                          aria-label={`${displayName(s)} — ${a.title}`}
                          className={`h-10 w-20 rounded-lg border px-2 text-center tabular-nums
                            ${over ? 'border-absent text-absent' : 'border-slate-200'}
                            ${!editable ? 'bg-slate-50 text-slate-500' : ''}`}
                        />
                      </td>
                    )
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

function StatusPill({ status, saving }: { status: AssessmentStatus; saving: boolean }) {
  const tone: Record<AssessmentStatus, string> = {
    draft:     'bg-slate-100 text-slate-600',
    open:      'bg-blue-50 text-blue-700',
    submitted: 'bg-amber-50 text-amber-800',
    moderated: 'bg-violet-50 text-violet-700',
    published: 'bg-green-50 text-green-700',
  }
  if (saving) {
    return <span className="rounded-full bg-blue-50 px-2.5 py-1 text-xs font-medium text-blue-700">Saving…</span>
  }
  return (
    <span className={`rounded-full px-2.5 py-1 text-xs font-medium capitalize ${tone[status]}`}>
      {status}
    </span>
  )
}
