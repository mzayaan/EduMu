import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

/**
 * Two teacher jobs whose RPCs existed with no caller.
 *
 * `rpc_amend_mark` is the audited correction path for a mark that has already
 * been moderated or published. Without a screen, corrections still happened —
 * just not through the route that records who changed what and why. An audit
 * trail nobody can use is not an audit trail.
 *
 * `rpc_set_subject_comment` fills `term_result.educator_comment`, which the
 * report book renders. Until now every report book printed those blank while
 * appearing to have the field.
 */

interface SubjectRow {
  student_id: string
  subject_id: string
  first_name: string
  last_name: string
  subject_name: string
  aggregate_score: number | null
  educator_comment: string | null
  difficulties: string | null
}

async function fetchSubjectResults(termId: string, setId: string): Promise<SubjectRow[]> {
  const { data, error } = await supabase
    .from('term_results_with_attendance')
    .select('student_id,subject_id,first_name,last_name,subject_name,aggregate_score,educator_comment,difficulties')
    .eq('term_id', termId)
    .eq('subject_set_id', setId)
    .order('last_name')
  if (error) throw error
  return (data ?? []) as SubjectRow[]
}

async function setSubjectComment(
  termId: string, studentId: string, subjectId: string,
  comment: string, difficulties: string,
) {
  const { error } = await supabase.rpc('rpc_set_subject_comment', {
    p_term: termId, p_student: studentId, p_subject: subjectId,
    p_comment: comment || null, p_difficulties: difficulties || null,
  })
  if (error) throw error
}

async function amendMark(markId: string, score: number | null, code: string | null, reason: string) {
  const { error } = await supabase.rpc('rpc_amend_mark', {
    p_mark: markId, p_score: score, p_code: code, p_reason: reason,
  })
  if (error) throw error
}

export function MarkCorrections({ termId, setId }: { termId: string; setId: string }) {
  const qc = useQueryClient()
  const [err, setErr] = useState<string | null>(null)
  const rows = useQuery({
    queryKey: ['subject-results', termId, setId],
    queryFn: () => fetchSubjectResults(termId, setId),
    enabled: !!termId && !!setId,
  })

  const save = useMutation({
    mutationFn: (v: { student: string; subject: string; comment: string; difficulties: string }) =>
      setSubjectComment(termId, v.student, v.subject, v.comment, v.difficulties),
    onSuccess: () => {
      setErr(null)
      void qc.invalidateQueries({ queryKey: ['subject-results', termId, setId] })
    },
    onError: (e) => setErr(e instanceof Error ? e.message : String(e)),
  })

  if (!termId || !setId) return null

  return (
    <section className="mt-6 rounded-lg border border-slate-200 p-4">
      <h2 className="text-sm font-semibold text-slate-900">Subject comments</h2>
      <p className="mt-1 text-xs text-slate-500">
        These print on the report book under each subject. Left empty, the
        subject row on the report is a mark and nothing else.
      </p>

      {err && <p className="mt-2 rounded bg-red-50 px-2 py-1.5 text-sm text-red-800">{err}</p>}

      <div className="mt-3 space-y-2">
        {(rows.data ?? []).map((r) => (
          <CommentRow
            key={`${r.student_id}:${r.subject_id}`}
            row={r}
            busy={save.isPending}
            onSave={(comment, difficulties) =>
              save.mutate({ student: r.student_id, subject: r.subject_id, comment, difficulties })}
          />
        ))}
        {(rows.data ?? []).length === 0 && (
          <p className="text-sm text-slate-500">
            No computed results for this set and term yet.
          </p>
        )}
      </div>
    </section>
  )
}

function CommentRow({ row, busy, onSave }: {
  row: SubjectRow
  busy: boolean
  onSave: (comment: string, difficulties: string) => void
}) {
  const [comment, setComment] = useState(row.educator_comment ?? '')
  const [difficulties, setDifficulties] = useState(row.difficulties ?? '')
  const dirty = comment !== (row.educator_comment ?? '') ||
                difficulties !== (row.difficulties ?? '')

  return (
    <div className="grid gap-2 rounded-md bg-slate-50 p-2 sm:grid-cols-[10rem,1fr,1fr,auto]">
      <div className="text-sm">
        <div className="font-medium text-slate-900">{row.first_name} {row.last_name}</div>
        <div className="text-xs text-slate-500">
          {row.subject_name}
          {row.aggregate_score != null && ` · ${row.aggregate_score}`}
        </div>
      </div>
      <input value={comment} onChange={(e) => setComment(e.target.value)}
             placeholder="Comment for the report book"
             className="rounded-md border-slate-300 text-sm" />
      <input value={difficulties} onChange={(e) => setDifficulties(e.target.value)}
             placeholder="Difficulties (optional)"
             className="rounded-md border-slate-300 text-sm" />
      <button
        disabled={!dirty || busy}
        onClick={() => onSave(comment.trim(), difficulties.trim())}
        className="rounded-md bg-brand px-3 py-1.5 text-sm font-semibold text-white disabled:opacity-30"
      >
        Save
      </button>
    </div>
  )
}

/**
 * Correcting a mark that is no longer editable in the grid. Separate from the
 * grid on purpose: an amendment after moderation is a deliberate act, not a
 * typo fix, and it demands a reason that goes to audit_log.
 */
export function AmendMark({ markId, current, onDone }: {
  markId: string
  current: { score: number | null; code: string | null }
  onDone?: () => void
}) {
  const [score, setScore] = useState(current.score?.toString() ?? '')
  const [code, setCode] = useState(current.code ?? '')
  const [reason, setReason] = useState('')
  const [err, setErr] = useState<string | null>(null)

  const run = useMutation({
    mutationFn: () => amendMark(
      markId,
      score.trim() === '' ? null : Number(score),
      code.trim() === '' ? null : code.trim().toUpperCase(),
      reason.trim(),
    ),
    onSuccess: () => { setErr(null); setReason(''); onDone?.() },
    onError: (e) => setErr(e instanceof Error ? e.message : String(e)),
  })

  return (
    <div className="flex flex-wrap items-end gap-2 rounded-md bg-amber-50 p-2 ring-1 ring-amber-200">
      <label className="text-sm">
        <span className="block text-xs font-medium text-slate-600">Score</span>
        <input value={score} onChange={(e) => setScore(e.target.value)}
               inputMode="decimal" className="mt-1 w-20 rounded-md border-slate-300 text-sm" />
      </label>
      <label className="text-sm">
        <span className="block text-xs font-medium text-slate-600">or code</span>
        <input value={code} onChange={(e) => setCode(e.target.value)}
               placeholder="ABS" className="mt-1 w-24 rounded-md border-slate-300 text-sm" />
      </label>
      <label className="min-w-[14rem] flex-1 text-sm">
        <span className="block text-xs font-medium text-slate-600">
          Reason (required — recorded against your name)
        </span>
        <input value={reason} onChange={(e) => setReason(e.target.value)}
               className="mt-1 w-full rounded-md border-slate-300 text-sm" />
      </label>
      <button
        disabled={!reason.trim() || run.isPending}
        onClick={() => run.mutate()}
        className="rounded-md bg-brand px-3 py-1.5 text-sm font-semibold text-white disabled:opacity-40"
      >
        {run.isPending ? 'Amending…' : 'Amend'}
      </button>
      {err && <p className="w-full text-sm text-red-800">{err}</p>}
    </div>
  )
}
