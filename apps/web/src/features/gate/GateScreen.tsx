import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { hasCap, type EduClaims } from '@/lib/supabase'
import {
  fetchLateArrivals, fetchStaff, fetchStaffMovements, fetchStaffRegister,
  markStaffAttendance, openStaffRegister, recordLateArrival, searchPupils,
  signStaffIn, signStaffOut,
  type LateArrivalOutcome, type PupilOption,
} from './api'

const today = () => new Date().toISOString().slice(0, 10)
const nowTime = () => new Date().toTimeString().slice(0, 5)

/**
 * The gate desk: late arrivals and staff off site.
 *
 * This screen exists because rpc_record_late_arrival had no caller. The
 * database handled late arrivals correctly and nobody could trigger it, so a
 * feature that looked finished could never fire in practice.
 */
export function GateScreen({ claims }: { claims: EduClaims }) {
  const canLate = hasCap(claims, 'attendance.resolve')
  const canStaff = hasCap(claims, 'staff.manage')
  const [date, setDate] = useState(today())
  const [pane, setPane] = useState<'pupils' | 'staff'>(canLate ? 'pupils' : 'staff')

  if (!canLate && !canStaff) {
    return <p className="p-6 text-sm text-slate-600">
      The gate register is an Usher and office function.
    </p>
  }

  return (
    <div className="mx-auto max-w-5xl space-y-5 p-4 sm:p-6">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-lg font-semibold text-slate-900">Gate</h1>
          <p className="mt-1 text-sm text-slate-600">
            Late arrivals and staff movement for one day.
          </p>
        </div>
        <label className="text-sm">
          <span className="block text-xs font-medium text-slate-600">Date</span>
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)}
                 className="mt-1 rounded-md border-slate-300 text-sm" />
        </label>
      </header>

      {canLate && canStaff && (
        <div className="flex gap-1 rounded-lg bg-slate-100 p-1 text-sm">
          {(['pupils', 'staff'] as const).map((p) => (
            <button key={p} onClick={() => setPane(p)}
              className={`flex-1 rounded-md px-3 py-1.5 font-medium ${
                pane === p ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-600'}`}>
              {p === 'pupils' ? 'Pupil late arrivals' : 'Staff'}
            </button>
          ))}
        </div>
      )}

      {pane === 'pupils' && canLate && <LateArrivals date={date} />}
      {pane === 'staff' && canStaff && <StaffPane date={date} />}
    </div>
  )
}

function LateArrivals({ date }: { date: string }) {
  const qc = useQueryClient()
  const [q, setQ] = useState('')
  const [picked, setPicked] = useState<PupilOption | null>(null)
  const [at, setAt] = useState(nowTime())
  const [reason, setReason] = useState('')
  const [last, setLast] = useState<LateArrivalOutcome | null>(null)
  const [err, setErr] = useState<string | null>(null)

  const results = useQuery({
    queryKey: ['pupil-search', q],
    queryFn: () => searchPupils(q),
    enabled: q.trim().length >= 2,
  })

  const rows = useQuery({
    queryKey: ['late-arrivals', date],
    queryFn: () => fetchLateArrivals(date),
  })

  const record = useMutation({
    mutationFn: () => recordLateArrival(picked!.student_id, date, at, reason || undefined),
    onSuccess: (r) => {
      setLast(r); setErr(null); setPicked(null); setQ(''); setReason('')
      qc.invalidateQueries({ queryKey: ['late-arrivals', date] })
    },
    onError: (e) => setErr(e instanceof Error ? e.message : String(e)),
  })

  return (
    <div className="space-y-5">
      <section className="rounded-lg border border-slate-200 p-4">
        <h2 className="text-sm font-semibold text-slate-900">Record a late arrival</h2>

        <div className="mt-3 grid gap-3 sm:grid-cols-[2fr,auto,2fr,auto]">
          <div>
            <label className="block text-xs font-medium text-slate-600">Pupil</label>
            {picked ? (
              <div className="mt-1 flex items-center gap-2 rounded-md bg-slate-100 px-2 py-1.5 text-sm">
                <span className="font-medium">{picked.first_name} {picked.last_name}</span>
                <span className="text-xs text-slate-500">{picked.class_name}</span>
                <button onClick={() => setPicked(null)}
                        className="ml-auto text-xs text-slate-500 hover:text-slate-800">change</button>
              </div>
            ) : (
              <>
                <input value={q} onChange={(e) => setQ(e.target.value)}
                       placeholder="Name or admission number"
                       className="mt-1 w-full rounded-md border-slate-300 text-sm" />
                {(results.data ?? []).length > 0 && (
                  <ul className="mt-1 max-h-40 overflow-y-auto rounded-md border border-slate-200 text-sm">
                    {results.data!.map((p) => (
                      <li key={p.student_id}>
                        <button onClick={() => { setPicked(p); setQ('') }}
                                className="flex w-full justify-between px-2 py-1.5 text-left hover:bg-slate-50">
                          <span>{p.first_name} {p.last_name}</span>
                          <span className="text-xs text-slate-500">{p.class_name}</span>
                        </button>
                      </li>
                    ))}
                  </ul>
                )}
              </>
            )}
          </div>

          <label className="text-sm">
            <span className="block text-xs font-medium text-slate-600">Arrived</span>
            <input type="time" value={at} onChange={(e) => setAt(e.target.value)}
                   className="mt-1 rounded-md border-slate-300 text-sm" />
          </label>

          <label className="text-sm">
            <span className="block text-xs font-medium text-slate-600">Reason (optional)</span>
            <input value={reason} onChange={(e) => setReason(e.target.value)}
                   placeholder="Bus delay"
                   className="mt-1 w-full rounded-md border-slate-300 text-sm" />
          </label>

          <div className="flex items-end">
            <button
              onClick={() => record.mutate()}
              disabled={!picked || record.isPending}
              className="rounded-md bg-brand px-3 py-1.5 text-sm font-semibold text-white disabled:opacity-40"
            >
              {record.isPending ? 'Recording…' : 'Record'}
            </button>
          </div>
        </div>

        {err && <p className="mt-3 rounded bg-red-50 px-2 py-1.5 text-sm text-red-800">{err}</p>}

        {/*
          The outcome is spelled out because the two cases have very different
          consequences for the pupil, and the person at the gate is the only one
          in a position to notice a mistake.
        */}
        {last && (
          <div className={`mt-3 rounded-md px-3 py-2 text-sm ring-1 ${
            last.outcome === 'carried_to_pm'
              ? 'bg-amber-50 text-amber-900 ring-amber-200'
              : 'bg-emerald-50 text-emerald-900 ring-emerald-200'}`}>
            {last.outcome === 'marked_late_in_am' ? (
              <>Marked <strong>late</strong> on the morning register
                 ({last.minutes_late} min).</>
            ) : (
              <>The morning register had already closed. The pupil stays{' '}
                <strong>absent for the morning</strong> and is marked{' '}
                <strong>late on the afternoon register</strong> ({last.minutes_late} min).
                That costs them one of two sessions today, which counts toward the
                80% examination threshold.</>
            )}
          </div>
        )}
      </section>

      <section className="rounded-lg border border-slate-200 p-4">
        <h2 className="text-sm font-semibold text-slate-900">
          Late today ({rows.data?.length ?? 0})
        </h2>
        {(rows.data ?? []).length === 0 ? (
          <p className="mt-2 text-sm text-slate-500">Nobody recorded late.</p>
        ) : (
          <table className="mt-2 min-w-full text-sm">
            <thead className="text-left text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="py-1.5 pr-3">Pupil</th>
                <th className="py-1.5 pr-3">Class</th>
                <th className="py-1.5 pr-3">Arrived</th>
                <th className="py-1.5 pr-3 text-right">Mins</th>
                <th className="py-1.5 pr-3">AM</th>
                <th className="py-1.5 pr-3">PM</th>
                <th className="py-1.5">Reason</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {rows.data!.map((r) => (
                <tr key={r.student_id}>
                  <td className="py-1.5 pr-3 font-medium">{r.first_name} {r.last_name}</td>
                  <td className="py-1.5 pr-3 text-slate-600">{r.class_name ?? '—'}</td>
                  <td className="py-1.5 pr-3 tabular-nums">{r.arrived_at?.slice(0, 5)}</td>
                  <td className="py-1.5 pr-3 text-right tabular-nums">{r.minutes_late ?? '—'}</td>
                  <td className="py-1.5 pr-3">{r.am_status ?? '—'}</td>
                  <td className="py-1.5 pr-3">{r.pm_status ?? '—'}</td>
                  <td className="py-1.5 text-slate-600">{r.reason ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </div>
  )
}

function StaffPane({ date }: { date: string }) {
  const qc = useQueryClient()
  const [err, setErr] = useState<string | null>(null)
  const staff = useQuery({ queryKey: ['staff'], queryFn: fetchStaff })
  const reg = useQuery({ queryKey: ['staff-register', date], queryFn: () => fetchStaffRegister(date) })
  const moves = useQuery({ queryKey: ['staff-moves', date], queryFn: () => fetchStaffMovements(date) })

  const byStaff = useMemo(
    () => new Map((reg.data ?? []).map((r) => [r.staff_id, r])),
    [reg.data],
  )
  const nameOf = useMemo(
    () => new Map((staff.data ?? []).map((s) => [s.id, `${s.first_name} ${s.last_name}`])),
    [staff.data],
  )

  const fail = (e: unknown) => setErr(e instanceof Error ? e.message : String(e))
  const refresh = () => {
    qc.invalidateQueries({ queryKey: ['staff-register', date] })
    qc.invalidateQueries({ queryKey: ['staff-moves', date] })
  }

  const open = useMutation({
    mutationFn: () => openStaffRegister(date), onSuccess: refresh, onError: fail,
  })
  const mark = useMutation({
    mutationFn: (v: { id: string; status: string }) =>
      markStaffAttendance(v.id, date, v.status, v.status === 'late' ? nowTime() : null),
    onSuccess: refresh, onError: fail,
  })
  const out = useMutation({
    mutationFn: (v: { id: string; reason: string }) =>
      signStaffOut(v.id, date, nowTime(), v.reason),
    onSuccess: refresh, onError: fail,
  })
  const back = useMutation({
    mutationFn: (id: string) => signStaffIn(id, nowTime()), onSuccess: refresh, onError: fail,
  })

  const STATUSES = ['present', 'late', 'absent', 'on_leave', 'off_site', 'training'] as const

  return (
    <div className="space-y-5">
      {err && <p className="rounded bg-red-50 px-2 py-1.5 text-sm text-red-800">{err}</p>}

      <section className="rounded-lg border border-slate-200 p-4">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold text-slate-900">Staff register</h2>
          <button onClick={() => open.mutate()} disabled={open.isPending}
                  className="rounded-md bg-white px-3 py-1.5 text-sm font-semibold text-slate-700 ring-1 ring-slate-300 hover:bg-slate-50">
            {open.isPending ? 'Opening…' : 'Open register'}
          </button>
        </div>
        <p className="mt-1 text-xs text-slate-500">
          Opening pre-fills everyone present, and marks anyone on approved leave
          automatically — so an unexplained absence is the only thing left to
          notice.
        </p>

        <table className="mt-3 min-w-full text-sm">
          <tbody className="divide-y divide-slate-100">
            {(staff.data ?? []).map((s) => {
              const r = byStaff.get(s.id)
              return (
                <tr key={s.id}>
                  <td className="py-1.5 pr-3">
                    <span className="font-medium">{s.last_name}, {s.first_name}</span>
                    {s.post && <span className="ml-2 text-xs text-slate-400">{s.post}</span>}
                  </td>
                  <td className="py-1.5">
                    <select
                      value={r?.status ?? ''}
                      onChange={(e) => mark.mutate({ id: s.id, status: e.target.value })}
                      className="rounded-md border-slate-300 py-1 text-xs"
                    >
                      <option value="" disabled>— not taken —</option>
                      {STATUSES.map((st) => (
                        <option key={st} value={st}>{st.replace('_', ' ')}</option>
                      ))}
                    </select>
                    {r?.minutes_late ? (
                      <span className="ml-2 text-xs text-amber-700">{r.minutes_late} min late</span>
                    ) : null}
                  </td>
                  <td className="py-1.5 text-right">
                    <SignOutButton onSubmit={(reason) => out.mutate({ id: s.id, reason })} />
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </section>

      <section className="rounded-lg border border-slate-200 p-4">
        <h2 className="text-sm font-semibold text-slate-900">
          Off site ({(moves.data ?? []).filter((m) => !m.in_at).length} out now)
        </h2>
        {(moves.data ?? []).length === 0 ? (
          <p className="mt-2 text-sm text-slate-500">No movements recorded.</p>
        ) : (
          <table className="mt-2 min-w-full text-sm">
            <tbody className="divide-y divide-slate-100">
              {moves.data!.map((m) => (
                <tr key={m.id}>
                  <td className="py-1.5 pr-3 font-medium">{nameOf.get(m.staff_id) ?? '—'}</td>
                  <td className="py-1.5 pr-3 text-slate-600">{m.reason}</td>
                  <td className="py-1.5 pr-3 tabular-nums">
                    {m.out_at.slice(0, 5)} → {m.in_at ? m.in_at.slice(0, 5) : '—'}
                  </td>
                  <td className="py-1.5 text-right">
                    {!m.in_at && (
                      <button onClick={() => back.mutate(m.id)}
                              className="text-xs font-medium text-brand hover:underline">
                        Sign back in
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </div>
  )
}

function SignOutButton({ onSubmit }: { onSubmit: (reason: string) => void }) {
  const [open, setOpen] = useState(false)
  const [reason, setReason] = useState('')
  if (!open) {
    return (
      <button onClick={() => setOpen(true)}
              className="text-xs font-medium text-slate-500 hover:text-slate-800">
        Sign out
      </button>
    )
  }
  return (
    <span className="inline-flex items-center gap-1">
      <input autoFocus value={reason} onChange={(e) => setReason(e.target.value)}
             placeholder="Reason" className="w-40 rounded-md border-slate-300 py-1 text-xs" />
      <button
        disabled={!reason.trim()}
        onClick={() => { onSubmit(reason.trim()); setReason(''); setOpen(false) }}
        className="rounded bg-brand px-2 py-1 text-xs font-semibold text-white disabled:opacity-40"
      >
        Go
      </button>
      <button onClick={() => setOpen(false)} className="text-xs text-slate-400">×</button>
    </span>
  )
}
