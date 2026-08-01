import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { displayName, formatDate } from '@/lib/format'
import {
  decideEligibility, fetchEligibility, fetchExamSessions,
  type EligibilityRow,
} from './api'

export function EligibilityScreen() {
  const qc = useQueryClient()
  const [sessionId, setSessionId] = useState<string | null>(null)
  const [onlyAtRisk, setOnlyAtRisk] = useState(true)

  const sessions = useQuery({ queryKey: ['exam-sessions'], queryFn: fetchExamSessions })

  useEffect(() => {
    if (!sessionId && sessions.data?.length) setSessionId(sessions.data[0]!.id)
  }, [sessions.data, sessionId])

  const rows = useQuery({
    queryKey: ['eligibility', sessionId],
    queryFn: () => fetchEligibility(sessionId!),
    enabled: Boolean(sessionId),
  })

  const decide = useMutation({
    mutationFn: (v: { studentId: string; decision: 'allow' | 'debar'; reason?: string }) =>
      decideEligibility(sessionId!, v.studentId, v.decision, v.reason),
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['eligibility'] }) },
  })

  const all = rows.data ?? []
  const atRisk = useMemo(() => all.filter((r) => r.recommended !== 'allow'), [all])
  const visible = onlyAtRisk ? atRisk : all
  const undecided = atRisk.filter((r) => r.decision === null).length
  const session = sessions.data?.find((s) => s.id === sessionId)

  return (
    <div className="mx-auto w-full max-w-3xl pb-32">
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <h1 className="text-lg font-semibold">Examination Eligibility</h1>
        <p className="text-sm text-slate-500">
          Attendance screening before an examination session
        </p>

        <div className="mt-3 flex flex-wrap items-center gap-2">
          <select
            value={sessionId ?? ''}
            onChange={(e) => setSessionId(e.target.value)}
            className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium"
          >
            {(sessions.data ?? []).map((s) => (
              <option key={s.id} value={s.id}>{s.name}</option>
            ))}
          </select>
          <button
            onClick={() => setOnlyAtRisk((v) => !v)}
            className="h-10 rounded-lg border border-slate-300 px-3 text-sm font-medium"
          >
            {onlyAtRisk ? `Show all (${all.length})` : `Only at risk (${atRisk.length})`}
          </button>
        </div>

        {session && (
          <p className="mt-2 text-xs text-slate-500">
            {formatDate(session.starts_on)} – {formatDate(session.ends_on)} ·{' '}
            <b className="text-absent">{atRisk.length}</b> below threshold ·{' '}
            <b>{undecided}</b> awaiting a decision
          </p>
        )}
      </header>

      {rows.isLoading && <p className="px-4 py-8 text-sm text-slate-500">Loading…</p>}

      {!rows.isLoading && visible.length === 0 && (
        <div className="px-4 py-12 text-center">
          <p className="text-sm font-medium text-slate-700">
            Every candidate meets the attendance threshold
          </p>
          <p className="mt-1 text-xs text-slate-400">
            Nothing to decide for this session.
          </p>
        </div>
      )}

      <ul className="divide-y divide-slate-100">
        {visible.map((r) => (
          <Row
            key={r.student_id}
            r={r}
            pending={decide.isPending}
            onDecide={(decision, reason) =>
              decide.mutate({ studentId: r.student_id, decision, reason })
            }
          />
        ))}
      </ul>

      <p className="px-4 pt-6 text-xs text-slate-400">
        The School Management Manual asks for at least 80% attendance before July
        mock examinations and end-of-year internal examinations. The threshold is
        configurable per school. This screen recommends; the Rector decides.
      </p>
    </div>
  )
}

function Row({ r, onDecide, pending }: {
  r: EligibilityRow
  onDecide: (decision: 'allow' | 'debar', reason?: string) => void
  pending: boolean
}) {
  const [reason, setReason] = useState('')
  const [debarring, setDebarring] = useState(false)
  const below = r.recommended === 'review'

  return (
    <li className="px-4 py-3">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-sm font-medium">
            {displayName(r)}
            <span className="ml-2 text-xs font-normal text-slate-400">
              {r.admission_number} · {r.class_name}
            </span>
          </p>
          <p className="mt-0.5 text-xs text-slate-500">
            {r.sessions_present}/{r.sessions_possible} sessions ·{' '}
            {r.absent_unauth} unauthorised · {r.absent_auth} authorised
            {r.times_late > 0 && ` · ${r.times_late} late`}
          </p>
          {below && (
            <p className="mt-0.5 text-xs text-absent">
              {r.shortfall_sessions} sessions short of the {r.threshold}% threshold
            </p>
          )}
        </div>
        <div className="shrink-0 text-right">
          <p className={`text-lg font-semibold tabular-nums ${
            r.pct_present === null ? 'text-slate-400'
              : below ? 'text-absent' : 'text-present'}`}>
            {r.pct_present === null ? '—' : `${r.pct_present}%`}
          </p>
        </div>
      </div>

      {r.decision ? (
        <p className="mt-2 text-xs">
          <span className={`rounded-full px-2 py-0.5 font-semibold uppercase ${
            r.decision === 'debar' ? 'bg-red-50 text-absent' : 'bg-green-50 text-present'}`}>
            {r.decision === 'debar' ? 'Debarred' : 'Allowed'}
          </span>
          {r.decision_reason && <span className="ml-2 text-slate-500">{r.decision_reason}</span>}
        </p>
      ) : below ? (
        debarring ? (
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <input
              autoFocus value={reason} onChange={(e) => setReason(e.target.value)}
              placeholder="Reason for debarring (required)"
              className="h-9 flex-1 rounded-lg border border-slate-300 px-2.5 text-xs"
            />
            <button
              disabled={pending || reason.trim().length === 0}
              onClick={() => onDecide('debar', reason.trim())}
              className="h-9 rounded-lg bg-absent px-3 text-xs font-semibold text-white disabled:opacity-40"
            >
              Confirm debar
            </button>
            <button
              onClick={() => { setDebarring(false); setReason('') }}
              className="h-9 rounded-lg border border-slate-200 px-3 text-xs font-medium"
            >
              Cancel
            </button>
          </div>
        ) : (
          <div className="mt-2 flex gap-1.5">
            <button
              disabled={pending}
              onClick={() => onDecide('allow')}
              className="h-9 rounded-lg border border-slate-200 px-3 text-xs font-medium
                         text-slate-600 hover:border-present hover:text-present"
            >
              Allow to sit
            </button>
            <button
              disabled={pending}
              onClick={() => setDebarring(true)}
              className="h-9 rounded-lg border border-slate-200 px-3 text-xs font-medium
                         text-slate-600 hover:border-absent hover:text-absent"
            >
              Debar…
            </button>
          </div>
        )
      ) : null}
    </li>
  )
}
