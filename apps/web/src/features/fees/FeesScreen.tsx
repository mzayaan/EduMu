import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { hasCap, supabase, type EduClaims } from '@/lib/supabase'
import {
  addStructure, fetchPayments, fetchStatement, fetchStructures, generateCharges,
  proofUrl, rupees, submitPayment, uploadProof, verifyPayment, waiveFee,
  type PaymentRow, type StatementRow,
} from './api'

/**
 * Fees.
 *
 * The banner is not decoration. Anyone opening this in a portfolio — or a
 * school evaluating it — needs to know within one second that no money moves
 * through this system, because the screen otherwise looks exactly like one
 * that does.
 */
function DemoBanner() {
  return (
    <div className="rounded-lg border-2 border-dashed border-amber-400 bg-amber-50 p-3">
      <p className="text-sm font-semibold text-amber-900">
        Demonstration only — this does not process payments
      </p>
      <p className="mt-1 text-xs leading-relaxed text-amber-800">
        No card details, no bank connection, no payment gateway. The guardian
        pays the school directly by MCB Juice and uploads the confirmation; a
        person at the school checks the bank and marks it verified. Before real
        use this would need bank reconciliation, a refund path, an immutable
        ledger and an accountant&apos;s review — none of which is here.
      </p>
    </div>
  )
}

export function FeesScreen({ claims }: { claims: EduClaims }) {
  // The Bursar holds fees.manage and not school.manage. Waiving is deliberately
  // narrower — forgiving money owed stays with the office — so that is checked
  // separately below rather than folded into one flag.
  const isOffice = hasCap(claims, 'fees.manage') || hasCap(claims, 'school.manage')
  const canWaive = hasCap(claims, 'school.manage')
  const [tab, setTab] = useState<'statement' | 'payments' | 'setup'>(
    isOffice ? 'payments' : 'statement',
  )

  return (
    <div className="mx-auto max-w-5xl space-y-5 p-4 sm:p-6">
      <header>
        <h1 className="text-lg font-semibold text-slate-900">Fees</h1>
        <p className="mt-1 text-sm text-slate-600">
          State secondary schooling in Mauritius is free; this is for
          grant-aided and private schools.
        </p>
      </header>

      <DemoBanner />

      {isOffice && (
        <div className="flex gap-1 rounded-lg bg-slate-100 p-1 text-sm">
          {([['payments', 'To verify'], ['statement', 'Balances'], ['setup', 'Fee structure']] as const)
            .map(([id, label]) => (
              <button key={id} onClick={() => setTab(id)}
                className={`flex-1 rounded-md px-3 py-1.5 font-medium ${
                  tab === id ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-600'}`}>
                {label}
              </button>
            ))}
        </div>
      )}

      {tab === 'statement' && (
        <Statement claims={claims} isOffice={isOffice} canWaive={canWaive} />
      )}
      {tab === 'payments' && isOffice && <Verification />}
      {tab === 'setup' && isOffice && <Setup claims={claims} />}
    </div>
  )
}

function Statement({ claims, isOffice, canWaive }: {
  claims: EduClaims; isOffice: boolean; canWaive: boolean
}) {
  const qc = useQueryClient()
  const [err, setErr] = useState<string | null>(null)
  const [paying, setPaying] = useState<StatementRow | null>(null)
  const rows = useQuery({ queryKey: ['fee-statement'], queryFn: () => fetchStatement() })

  const owed = (rows.data ?? []).reduce((t, r) => t + Number(r.balance), 0)
  const pending = (rows.data ?? []).reduce((t, r) => t + Number(r.pending), 0)

  const waive = useMutation({
    mutationFn: (v: { id: string; reason: string }) => waiveFee(v.id, v.reason),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['fee-statement'] }),
    onError: (e) => setErr(e instanceof Error ? e.message : String(e)),
  })

  return (
    <div className="space-y-4">
      {err && <p className="rounded bg-red-50 px-3 py-2 text-sm text-red-800">{err}</p>}

      <div className="flex flex-wrap gap-4 rounded-lg border border-slate-200 p-4 text-sm">
        <div>
          <div className="text-xs uppercase tracking-wide text-slate-500">Outstanding</div>
          <div className="text-lg font-semibold tabular-nums">{rupees(owed)}</div>
        </div>
        <div>
          <div className="text-xs uppercase tracking-wide text-slate-500">Awaiting verification</div>
          <div className="text-lg font-semibold tabular-nums text-amber-700">{rupees(pending)}</div>
          <div className="text-xs text-slate-500">does not reduce the balance yet</div>
        </div>
      </div>

      {(rows.data ?? []).length === 0 ? (
        <p className="text-sm text-slate-500">Nothing charged.</p>
      ) : (
        <table className="min-w-full text-sm">
          <thead className="text-left text-xs uppercase tracking-wide text-slate-500">
            <tr>
              {isOffice && <th className="py-2 pr-3">Pupil</th>}
              <th className="py-2 pr-3">Item</th>
              <th className="py-2 pr-3">Due</th>
              <th className="py-2 pr-3 text-right">Amount</th>
              <th className="py-2 pr-3 text-right">Paid</th>
              <th className="py-2 pr-3 text-right">Balance</th>
              <th className="py-2" />
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {rows.data!.map((r) => (
              <tr key={r.charge_id}>
                {isOffice && (
                  <td className="py-2 pr-3">{r.first_name} {r.last_name}</td>
                )}
                <td className="py-2 pr-3">
                  {r.description}
                  {r.waived && (
                    <span className="ml-2 rounded bg-slate-100 px-1.5 py-0.5 text-xs text-slate-600"
                          title={r.waived_reason ?? ''}>waived</span>
                  )}
                </td>
                <td className="py-2 pr-3 text-slate-600">{r.due_on ?? '—'}</td>
                <td className="py-2 pr-3 text-right tabular-nums">{rupees(Number(r.amount))}</td>
                <td className="py-2 pr-3 text-right tabular-nums">
                  {rupees(Number(r.paid))}
                  {Number(r.pending) > 0 && (
                    <div className="text-xs text-amber-700">
                      +{rupees(Number(r.pending))} pending
                    </div>
                  )}
                </td>
                <td className="py-2 pr-3 text-right font-semibold tabular-nums">
                  {rupees(Number(r.balance))}
                </td>
                <td className="py-2 text-right">
                  {Number(r.balance) > 0 && !r.waived && (
                    <button onClick={() => setPaying(r)}
                            className="text-xs font-medium text-brand hover:underline">
                      Record payment
                    </button>
                  )}
                  {canWaive && !r.waived && Number(r.balance) > 0 && (
                    <WaiveButton onWaive={(reason) => waive.mutate({ id: r.charge_id, reason })} />
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {paying && (
        <PayDialog row={paying} claims={claims}
                   onClose={() => setPaying(null)}
                   onDone={() => {
                     setPaying(null)
                     qc.invalidateQueries({ queryKey: ['fee-statement'] })
                   }} />
      )}
    </div>
  )
}

function PayDialog({ row, claims, onClose, onDone }: {
  row: StatementRow; claims: EduClaims; onClose: () => void; onDone: () => void
}) {
  const [amount, setAmount] = useState(String(row.balance))
  const [paidOn, setPaidOn] = useState(new Date().toISOString().slice(0, 10))
  const [reference, setReference] = useState('')
  const [file, setFile] = useState<File | null>(null)
  const [err, setErr] = useState<string | null>(null)

  const run = useMutation({
    mutationFn: async () => {
      let proofPath: string | undefined
      if (file) {
        if (!claims.school_id) throw new Error('No school on your session')
        proofPath = await uploadProof(claims.school_id, row.student_id, file)
      }
      return submitPayment({
        studentId: row.student_id, chargeId: row.charge_id,
        amount: Number(amount), paidOn, method: 'mcb_juice',
        reference, proofPath,
      })
    },
    onSuccess: onDone,
    onError: (e) => setErr(e instanceof Error ? e.message : String(e)),
  })

  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4">
      <div className="w-full max-w-md rounded-lg bg-white p-4 shadow-xl">
        <h3 className="text-sm font-semibold text-slate-900">
          Record an MCB Juice payment
        </h3>
        <p className="mt-1 text-xs text-slate-600">
          Send the money in the MCB Juice app first, then record it here with
          the confirmation. The school checks its account before this counts
          against the balance.
        </p>

        <div className="mt-3 space-y-3">
          <label className="block text-sm">
            <span className="text-xs font-medium text-slate-600">Amount (MUR)</span>
            <input value={amount} onChange={(e) => setAmount(e.target.value)}
                   inputMode="decimal"
                   className="mt-1 w-full rounded-md border-slate-300 text-sm" />
          </label>
          <label className="block text-sm">
            <span className="text-xs font-medium text-slate-600">Date paid</span>
            <input type="date" value={paidOn} onChange={(e) => setPaidOn(e.target.value)}
                   className="mt-1 w-full rounded-md border-slate-300 text-sm" />
          </label>
          <label className="block text-sm">
            <span className="text-xs font-medium text-slate-600">
              Juice transaction reference
            </span>
            <input value={reference} onChange={(e) => setReference(e.target.value)}
                   placeholder="From your MCB Juice confirmation"
                   className="mt-1 w-full rounded-md border-slate-300 text-sm" />
          </label>
          <label className="block text-sm">
            <span className="text-xs font-medium text-slate-600">
              Screenshot of the confirmation
            </span>
            <input type="file" accept="image/*,application/pdf"
                   onChange={(e) => setFile(e.target.files?.[0] ?? null)}
                   className="mt-1 w-full text-sm" />
          </label>
        </div>

        {err && <p className="mt-3 rounded bg-red-50 px-2 py-1.5 text-sm text-red-800">{err}</p>}

        <div className="mt-4 flex justify-end gap-2">
          <button onClick={onClose} className="rounded-md px-3 py-1.5 text-sm text-slate-600">
            Cancel
          </button>
          <button
            disabled={!Number(amount) || run.isPending}
            onClick={() => run.mutate()}
            className="rounded-md bg-brand px-3 py-1.5 text-sm font-semibold text-white disabled:opacity-40"
          >
            {run.isPending ? 'Submitting…' : 'Submit for verification'}
          </button>
        </div>
      </div>
    </div>
  )
}

function Verification() {
  const qc = useQueryClient()
  const [err, setErr] = useState<string | null>(null)
  const rows = useQuery({
    queryKey: ['fee-payments', 'awaiting_verification'],
    queryFn: () => fetchPayments('awaiting_verification'),
  })

  const decide = useMutation({
    mutationFn: (v: { id: string; ok: boolean; note?: string }) =>
      verifyPayment(v.id, v.ok, v.note),
    onSuccess: () => {
      setErr(null)
      qc.invalidateQueries({ queryKey: ['fee-payments', 'awaiting_verification'] })
      qc.invalidateQueries({ queryKey: ['fee-statement'] })
    },
    onError: (e) => setErr(e instanceof Error ? e.message : String(e)),
  })

  return (
    <div className="space-y-3">
      <p className="text-sm text-slate-600">
        Open your bank app, confirm the money arrived, then verify. Verifying is
        the only step here that means anything — nothing is confirmed by the
        system itself.
      </p>
      {err && <p className="rounded bg-red-50 px-3 py-2 text-sm text-red-800">{err}</p>}

      {(rows.data ?? []).length === 0 ? (
        <p className="text-sm text-slate-500">Nothing awaiting verification.</p>
      ) : (
        (rows.data ?? []).map((p) => (
          <PaymentCard key={p.id} payment={p}
                       busy={decide.isPending}
                       onDecide={(ok, note) => decide.mutate({ id: p.id, ok, note })} />
        ))
      )}
    </div>
  )
}

function PaymentCard({ payment, busy, onDecide }: {
  payment: PaymentRow; busy: boolean; onDecide: (ok: boolean, note?: string) => void
}) {
  const [note, setNote] = useState('')
  const [url, setUrl] = useState<string | null>(null)

  return (
    <div className="rounded-lg border border-slate-200 p-3">
      <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1 text-sm">
        <span className="font-semibold tabular-nums">{rupees(Number(payment.amount))}</span>
        <span className="text-slate-600">{payment.method.replace('_', ' ')}</span>
        <span className="text-slate-600">paid {payment.paid_on}</span>
        {payment.reference && (
          <span className="rounded bg-slate-100 px-1.5 py-0.5 font-mono text-xs">
            {payment.reference}
          </span>
        )}
      </div>

      {payment.proof_path && (
        <div className="mt-2">
          {url ? (
            <a href={url} target="_blank" rel="noreferrer"
               className="text-xs font-medium text-brand hover:underline">
              Open proof in a new tab
            </a>
          ) : (
            <button
              onClick={async () => setUrl(await proofUrl(payment.proof_path!))}
              className="text-xs font-medium text-brand hover:underline"
            >
              View proof
            </button>
          )}
        </div>
      )}

      <div className="mt-3 flex flex-wrap items-end gap-2">
        <input value={note} onChange={(e) => setNote(e.target.value)}
               placeholder="Note (required to reject)"
               className="min-w-[14rem] flex-1 rounded-md border-slate-300 text-sm" />
        <button disabled={busy}
                onClick={() => onDecide(true, note || undefined)}
                className="rounded-md bg-emerald-600 px-3 py-1.5 text-sm font-semibold text-white disabled:opacity-40">
          Verify
        </button>
        <button disabled={busy || !note.trim()}
                onClick={() => onDecide(false, note.trim())}
                className="rounded-md bg-white px-3 py-1.5 text-sm font-semibold text-slate-700 ring-1 ring-slate-300 disabled:opacity-40">
          Reject
        </button>
      </div>
    </div>
  )
}

function Setup({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [err, setErr] = useState<string | null>(null)
  const [msg, setMsg] = useState<string | null>(null)
  const years = useQuery({
    queryKey: ['years'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('academic_year').select('id,name,status').order('starts_on', { ascending: false })
      if (error) throw error
      return (data ?? []) as Array<{ id: string; name: string; status: string }>
    },
  })
  const [yearId, setYearId] = useState('')
  const active = yearId || years.data?.find((y) => y.status === 'active')?.id || ''

  const structures = useQuery({
    queryKey: ['fee-structures', active],
    queryFn: () => fetchStructures(active),
    enabled: !!active,
  })

  const [form, setForm] = useState({ grade: '', name: '', amount: '', dueOn: '', mandatory: true })

  const add = useMutation({
    mutationFn: () => addStructure({
      schoolId: claims.school_id!, yearId: active,
      grade: form.grade === '' ? null : Number(form.grade),
      name: form.name.trim(), amount: Number(form.amount),
      dueOn: form.dueOn || null, mandatory: form.mandatory,
    }),
    onSuccess: () => {
      setErr(null); setForm({ grade: '', name: '', amount: '', dueOn: '', mandatory: true })
      qc.invalidateQueries({ queryKey: ['fee-structures', active] })
    },
    onError: (e) => setErr(e instanceof Error ? e.message : String(e)),
  })

  const raise = useMutation({
    mutationFn: () => generateCharges(active),
    onSuccess: (n) => {
      setMsg(`Raised ${n} charge${n === 1 ? '' : 's'}.`)
      qc.invalidateQueries({ queryKey: ['fee-statement'] })
    },
    onError: (e) => setErr(e instanceof Error ? e.message : String(e)),
  })

  return (
    <div className="space-y-4">
      {err && <p className="rounded bg-red-50 px-3 py-2 text-sm text-red-800">{err}</p>}
      {msg && <p className="rounded bg-emerald-50 px-3 py-2 text-sm text-emerald-900">{msg}</p>}

      <label className="block text-sm">
        <span className="font-medium text-slate-700">Academic year</span>
        <select value={active} onChange={(e) => setYearId(e.target.value)}
                className="mt-1 block w-full max-w-sm rounded-md border-slate-300 text-sm">
          {(years.data ?? []).map((y) => (
            <option key={y.id} value={y.id}>{y.name} — {y.status}</option>
          ))}
        </select>
      </label>

      <section className="rounded-lg border border-slate-200 p-4">
        <h2 className="text-sm font-semibold text-slate-900">Fee items</h2>
        <p className="mt-1 text-xs text-slate-500">
          Leave the grade blank to charge every pupil in the school.
        </p>

        <div className="mt-3 flex flex-wrap items-end gap-2">
          <label className="text-sm">
            <span className="block text-xs font-medium text-slate-600">Grade</span>
            <input value={form.grade} onChange={(e) => setForm({ ...form, grade: e.target.value })}
                   placeholder="all" inputMode="numeric"
                   className="mt-1 w-16 rounded-md border-slate-300 text-sm" />
          </label>
          <label className="min-w-[10rem] flex-1 text-sm">
            <span className="block text-xs font-medium text-slate-600">Name</span>
            <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })}
                   placeholder="Term 1 tuition"
                   className="mt-1 w-full rounded-md border-slate-300 text-sm" />
          </label>
          <label className="text-sm">
            <span className="block text-xs font-medium text-slate-600">Amount</span>
            <input value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })}
                   inputMode="decimal"
                   className="mt-1 w-28 rounded-md border-slate-300 text-sm" />
          </label>
          <label className="text-sm">
            <span className="block text-xs font-medium text-slate-600">Due</span>
            <input type="date" value={form.dueOn}
                   onChange={(e) => setForm({ ...form, dueOn: e.target.value })}
                   className="mt-1 rounded-md border-slate-300 text-sm" />
          </label>
          <button disabled={!form.name.trim() || !Number(form.amount) || add.isPending}
                  onClick={() => add.mutate()}
                  className="rounded-md bg-brand px-3 py-1.5 text-sm font-semibold text-white disabled:opacity-40">
            Add
          </button>
        </div>

        <table className="mt-4 min-w-full text-sm">
          <tbody className="divide-y divide-slate-100">
            {(structures.data ?? []).map((s) => (
              <tr key={s.id}>
                <td className="py-1.5 pr-3">{s.grade == null ? 'All grades' : `Grade ${s.grade}`}</td>
                <td className="py-1.5 pr-3">{s.name}</td>
                <td className="py-1.5 pr-3 text-right tabular-nums">{rupees(Number(s.amount))}</td>
                <td className="py-1.5 pr-3 text-slate-600">{s.due_on ?? '—'}</td>
                <td className="py-1.5 text-xs text-slate-500">
                  {s.is_mandatory ? '' : 'voluntary'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        <div className="mt-4">
          <button disabled={!active || raise.isPending} onClick={() => raise.mutate()}
                  className="rounded-md bg-white px-3 py-1.5 text-sm font-semibold text-slate-700 ring-1 ring-slate-300 disabled:opacity-40">
            {raise.isPending ? 'Raising…' : 'Raise charges for every enrolled pupil'}
          </button>
          <p className="mt-1 text-xs text-slate-500">
            Safe to run twice — a pupil is never charged the same item more than once.
          </p>
        </div>
      </section>
    </div>
  )
}

function WaiveButton({ onWaive }: { onWaive: (reason: string) => void }) {
  const [open, setOpen] = useState(false)
  const [reason, setReason] = useState('')
  if (!open) {
    return (
      <button onClick={() => setOpen(true)}
              className="ml-3 text-xs font-medium text-slate-500 hover:text-slate-800">
        Waive
      </button>
    )
  }
  return (
    <span className="ml-2 inline-flex items-center gap-1">
      <input autoFocus value={reason} onChange={(e) => setReason(e.target.value)}
             placeholder="Reason" className="w-40 rounded-md border-slate-300 py-1 text-xs" />
      <button disabled={!reason.trim()}
              onClick={() => { onWaive(reason.trim()); setOpen(false); setReason('') }}
              className="rounded bg-brand px-2 py-1 text-xs font-semibold text-white disabled:opacity-40">
        Save
      </button>
      <button onClick={() => setOpen(false)} className="text-xs text-slate-400">×</button>
    </span>
  )
}
