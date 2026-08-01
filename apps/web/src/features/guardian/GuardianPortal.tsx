import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { EduClaims } from '@/lib/supabase'
import { displayName, formatDate, todayInMauritius } from '@/lib/format'
import * as api from './api'

type Panel = 'attendance' | 'results' | 'homework' | 'notices'

export function GuardianPortal({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [wardId, setWardId] = useState<string | null>(null)
  const [panel, setPanel] = useState<Panel>('attendance')

  const wards = useQuery({ queryKey: ['wards'], queryFn: api.fetchWards })
  useEffect(() => {
    if (!wardId && wards.data?.length) setWardId(wards.data[0]!.student_id)
  }, [wards.data, wardId])

  const ward = wards.data?.find((w) => w.student_id === wardId)

  return (
    <div className="mx-auto w-full max-w-3xl pb-32">
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <h1 className="text-lg font-semibold">
          {ward ? displayName(ward) : 'My children'}
        </h1>
        {ward && (
          <p className="text-sm text-slate-500">
            {ward.class_name} · {ward.admission_number}
            {ward.is_responsible_party && ' · Responsible Party'}
          </p>
        )}

        {(wards.data ?? []).length > 1 && (
          <div className="mt-3 flex gap-2 overflow-x-auto">
            {wards.data!.map((w) => (
              <button
                key={w.student_id}
                onClick={() => setWardId(w.student_id)}
                className={`shrink-0 rounded-lg border px-3 py-2 text-sm font-medium ${
                  w.student_id === wardId
                    ? 'border-brand bg-brand-light text-brand'
                    : 'border-slate-200 bg-white text-slate-600'
                }`}
              >
                {w.preferred_name || w.first_name}
              </button>
            ))}
          </div>
        )}

        <nav className="mt-3 flex gap-1 overflow-x-auto">
          {(['attendance', 'results', 'homework', 'notices'] as Panel[]).map((p) => (
            <button
              key={p}
              onClick={() => setPanel(p)}
              className={`h-9 shrink-0 rounded-lg px-3 text-sm font-medium capitalize ${
                panel === p ? 'bg-brand text-white' : 'text-slate-600 hover:bg-slate-100'
              }`}
            >
              {p}
            </button>
          ))}
        </nav>
      </header>

      {!wards.isLoading && (wards.data ?? []).length === 0 && (
        <p className="px-4 py-12 text-center text-sm text-slate-500">
          No children are linked to this account yet. Please contact the school office.
        </p>
      )}

      {wardId && panel === 'attendance' && (
        <AttendancePanel wardId={wardId} schoolId={claims.school_id ?? null}
                         onChange={() => qc.invalidateQueries({ queryKey: ['ward-notes'] })} />
      )}
      {wardId && panel === 'results' && <ResultsPanel wardId={wardId} />}
      {wardId && panel === 'homework' && <HomeworkPanel wardId={wardId} />}
      {panel === 'notices' && <NoticesPanel />}
    </div>
  )
}

function AttendancePanel({ wardId, schoolId, onChange }: {
  wardId: string; schoolId: string | null; onChange: () => void
}) {
  const summary = useQuery({
    queryKey: ['ward-attendance', wardId],
    queryFn: () => api.fetchWardAttendance(wardId),
  })
  const absences = useQuery({
    queryKey: ['ward-absences', wardId],
    queryFn: () => api.fetchWardRecentAbsences(wardId),
  })
  const notes = useQuery({
    queryKey: ['ward-notes', wardId],
    queryFn: () => api.fetchWardAbsenceNotes(wardId),
  })

  const [open, setOpen] = useState(false)
  const [from, setFrom] = useState(todayInMauritius())
  const [to, setTo] = useState(todayInMauritius())
  const [reason, setReason] = useState('')

  const submit = useMutation({
    mutationFn: () => api.submitAbsenceNote({
      school_id: schoolId!, student_id: wardId,
      covers_from: from, covers_to: to, reason: reason.trim(),
    }),
    onSuccess: () => {
      setOpen(false); setReason('')
      void notes.refetch(); onChange()
    },
  })

  const total = useMemo(() => {
    const rows = summary.data ?? []
    const possible = rows.reduce((n: number, r: any) => n + r.sessions_possible, 0)
    const present = rows.reduce((n: number, r: any) => n + r.sessions_present, 0)
    return possible === 0 ? null : Math.round((1000 * present) / possible) / 10
  }, [summary.data])

  return (
    <div className="px-4 py-4">
      <div className="rounded-xl border border-slate-200 p-4">
        <p className="text-sm text-slate-500">Attendance this year</p>
        <p className={`mt-1 text-3xl font-semibold tabular-nums ${
          total === null ? 'text-slate-400' : total >= 80 ? 'text-present' : 'text-absent'}`}>
          {total === null ? '—' : `${total}%`}
        </p>
        {total !== null && total < 80 && (
          <p className="mt-1 text-xs text-absent">
            Below the 80% the school expects before examinations.
          </p>
        )}
      </div>

      <button
        onClick={() => setOpen((v) => !v)}
        className="mt-4 h-11 w-full rounded-lg bg-brand text-sm font-semibold text-white"
      >
        {open ? 'Cancel' : 'Explain an absence'}
      </button>

      {open && (
        <div className="mt-3 rounded-xl border border-slate-200 p-4">
          <div className="flex gap-2">
            <label className="flex-1 text-xs font-medium">
              From
              <input type="date" value={from} onChange={(e) => setFrom(e.target.value)}
                     className="mt-1 h-10 w-full rounded-lg border border-slate-300 px-2 text-sm" />
            </label>
            <label className="flex-1 text-xs font-medium">
              To
              <input type="date" value={to} onChange={(e) => setTo(e.target.value)}
                     className="mt-1 h-10 w-full rounded-lg border border-slate-300 px-2 text-sm" />
            </label>
          </div>
          <label className="mt-3 block text-xs font-medium">
            Reason
            <textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={3}
                      placeholder="e.g. unwell with fever; medical certificate to follow"
                      className="mt-1 w-full rounded-lg border border-slate-300 p-2 text-sm" />
          </label>
          <button
            disabled={reason.trim().length === 0 || submit.isPending}
            onClick={() => submit.mutate()}
            className="mt-3 h-10 w-full rounded-lg bg-brand text-sm font-semibold text-white disabled:opacity-40"
          >
            {submit.isPending ? 'Sending…' : 'Send to the school'}
          </button>
          <p className="mt-2 text-xs text-slate-400">
            The Form Teacher will review it. Accepted notes change the absence to authorised.
          </p>
        </div>
      )}

      {(notes.data ?? []).length > 0 && (
        <>
          <h2 className="mt-6 text-sm font-semibold">Absence notes</h2>
          <ul className="mt-2 space-y-2">
            {notes.data!.map((n: any) => (
              <li key={n.id} className="rounded-lg border border-slate-200 p-3">
                <div className="flex items-start justify-between gap-2">
                  <p className="text-sm">{n.reason}</p>
                  <span className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase ${
                    n.status === 'accepted' ? 'bg-green-50 text-present'
                    : n.status === 'rejected' ? 'bg-red-50 text-absent'
                    : 'bg-amber-50 text-amber-800'}`}>
                    {n.status}
                  </span>
                </div>
                <p className="mt-1 text-xs text-slate-400">
                  {formatDate(n.covers_from)} – {formatDate(n.covers_to)}
                </p>
              </li>
            ))}
          </ul>
        </>
      )}

      <h2 className="mt-6 text-sm font-semibold">Recent absences and lateness</h2>
      {(absences.data ?? []).length === 0 ? (
        <p className="mt-2 text-sm text-slate-500">Nothing recorded.</p>
      ) : (
        <ul className="mt-2 divide-y divide-slate-100">
          {absences.data!.map((a) => (
            <li key={a.id} className="flex items-center justify-between py-2">
              <span className="text-sm">
                {formatDate(a.date)} · {a.session?.toUpperCase()}
              </span>
              <span className={`text-xs font-semibold uppercase ${
                a.status === 'absent_unauth' ? 'text-absent'
                : a.status === 'late' ? 'text-late' : 'text-authorised'}`}>
                {a.status === 'absent_unauth' ? 'Unauthorised'
                  : a.status === 'absent_auth' ? 'Authorised' : 'Late'}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

function ResultsPanel({ wardId }: { wardId: string }) {
  const results = useQuery({
    queryKey: ['ward-results', wardId],
    queryFn: () => api.fetchWardResults(wardId),
  })
  return (
    <div className="px-4 py-4">
      {(results.data ?? []).length === 0 ? (
        <p className="text-sm text-slate-500">
          No results have been published yet. Marks appear here once the school releases them.
        </p>
      ) : (
        <ul className="divide-y divide-slate-100">
          {results.data!.map((r: any, i: number) => (
            <li key={i} className="flex items-center justify-between py-3">
              <div>
                <p className="text-sm font-medium">{r.subject_name}</p>
                <p className="text-xs text-slate-400">
                  Rank {r.rank_in_set} of {r.set_size}
                </p>
              </div>
              <div className="text-right">
                <p className="text-lg font-semibold tabular-nums">{r.aggregate_score}%</p>
                <p className="text-xs font-semibold text-slate-500">{r.band_label}</p>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

function HomeworkPanel({ wardId }: { wardId: string }) {
  const hw = useQuery({ queryKey: ['ward-homework', wardId], queryFn: () => api.fetchWardHomework(wardId) })
  return (
    <div className="px-4 py-4">
      {(hw.data ?? []).length === 0 ? (
        <p className="text-sm text-slate-500">No homework set.</p>
      ) : (
        <ul className="space-y-2">
          {hw.data!.map((h: any) => (
            <li key={h.id} className="rounded-lg border border-slate-200 p-3">
              <div className="flex items-start justify-between gap-2">
                <p className="text-sm font-medium">{h.title}</p>
                <span className="shrink-0 text-xs text-slate-400">Due {formatDate(h.due_on)}</span>
              </div>
              <p className="text-xs text-slate-400">{h.set_name}</p>
              {h.description && <p className="mt-1 text-sm text-slate-600">{h.description}</p>}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

function NoticesPanel() {
  const notices = useQuery({ queryKey: ['notices'], queryFn: api.fetchNotices })
  return (
    <div className="px-4 py-4">
      {(notices.data ?? []).length === 0 ? (
        <p className="text-sm text-slate-500">No notices.</p>
      ) : (
        <ul className="space-y-3">
          {notices.data!.map((n: any) => (
            <li key={n.id} className="rounded-lg border border-slate-200 p-3">
              <div className="flex items-start justify-between gap-2">
                <p className="text-sm font-medium">{n.title}</p>
                {n.pinned && (
                  <span className="shrink-0 rounded bg-brand-light px-1.5 py-0.5 text-[10px] font-semibold uppercase text-brand">
                    Pinned
                  </span>
                )}
              </div>
              <p className="mt-1 whitespace-pre-line text-sm text-slate-600">{n.body}</p>
              <p className="mt-1 text-xs text-slate-400">{formatDate(n.publish_at.slice(0, 10))}</p>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
