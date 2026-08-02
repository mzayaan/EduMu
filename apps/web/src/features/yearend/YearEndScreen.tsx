import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { hasCap, type EduClaims } from '@/lib/supabase'
import {
  confirmPromotions, declareClosure, evaluatePromotions, fetchPromotions, fetchYears,
  generateSchoolCalendar, overridePromotion, rolloverYear, seedPromotionRules,
  type PromotionOutcome, type PromotionRow, type RolloverResult,
} from './api'

const OUTCOMES: PromotionOutcome[] = [
  'promote', 'conditional_promote', 'repeat', 'leave', 'refer',
]

const LABEL: Record<PromotionOutcome, string> = {
  promote: 'Promote',
  conditional_promote: 'Conditional',
  repeat: 'Repeat',
  leave: 'Leave',
  refer: 'Refer',
}

const TONE: Record<PromotionOutcome, string> = {
  promote: 'bg-emerald-50 text-emerald-800 ring-emerald-200',
  conditional_promote: 'bg-amber-50 text-amber-800 ring-amber-200',
  repeat: 'bg-orange-50 text-orange-800 ring-orange-200',
  leave: 'bg-slate-100 text-slate-700 ring-slate-200',
  refer: 'bg-violet-50 text-violet-800 ring-violet-200',
}

/**
 * The end of the academic year, in the order it actually happens.
 *
 * The steps are numbered and gated because the sequence is not arbitrary:
 * rpc_rollover_year refuses outright while any decision is unconfirmed. The
 * screen makes that visible rather than letting someone discover it as an
 * error message.
 *
 * The engine advises; the Rector decides. Every outcome is overridable with a
 * reason, and the override is what rollover acts on.
 */
export function YearEndScreen({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const canDecide = hasCap(claims, 'marks.publish')
  const canManage = hasCap(claims, 'school.manage')

  const years = useQuery({ queryKey: ['years'], queryFn: fetchYears })
  const [fromYear, setFromYear] = useState<string>('')
  const [toYear, setToYear] = useState<string>('')
  const [dryRun, setDryRun] = useState<RolloverResult | null>(null)
  const [note, setNote] = useState<string | null>(null)

  const active = fromYear || years.data?.find((y) => y.status === 'active')?.id || ''

  const rows = useQuery({
    queryKey: ['promotions', active],
    queryFn: () => fetchPromotions(active),
    enabled: !!active,
  })

  const refresh = () => {
    qc.invalidateQueries({ queryKey: ['promotions', active] })
    qc.invalidateQueries({ queryKey: ['years'] })
  }

  const say = (m: string) => { setNote(m); setTimeout(() => setNote(null), 6000) }
  const fail = (e: unknown) => say(e instanceof Error ? e.message : String(e))

  const evaluate = useMutation({
    mutationFn: () => evaluatePromotions(active),
    onSuccess: (n) => { say(`Evaluated ${n} pupil${n === 1 ? '' : 's'}.`); refresh() },
    onError: fail,
  })

  const seed = useMutation({
    mutationFn: () => seedPromotionRules(active),
    onSuccess: () => say('Default rules seeded. Check the thresholds against your own.'),
    onError: fail,
  })

  // Not named `confirm`: that shadows window.confirm, and the rollover button
  // below calls it. TypeScript caught this; at runtime it would have thrown
  // "not callable" only on the one path that matters.
  const confirmAll = useMutation({
    mutationFn: () => confirmPromotions(active),
    onSuccess: (n) => { say(`Confirmed ${n} decision${n === 1 ? '' : 's'}.`); refresh() },
    onError: fail,
  })

  const override = useMutation({
    mutationFn: (v: { student: string; outcome: PromotionOutcome; reason: string }) =>
      overridePromotion(v.student, active, v.outcome, v.reason),
    onSuccess: () => { say('Override recorded.'); refresh() },
    onError: fail,
  })

  const roll = useMutation({
    mutationFn: (commit: boolean) => rolloverYear(active, toYear, commit),
    onSuccess: (r) => {
      setDryRun(r)
      say(r.committed
        ? `Rolled over. ${r.promoted} promoted, ${r.repeated} repeating, ${r.left} left.`
        : `Dry run only — nothing saved.`)
      if (r.committed) refresh()
    },
    onError: fail,
  })

  const calendar = useMutation({
    mutationFn: (v: { year: string; cycle: number }) =>
      generateSchoolCalendar(v.year, v.cycle),
    onSuccess: (n) => say(`Generated ${n} calendar day${n === 1 ? '' : 's'}.`),
    onError: fail,
  })

  const closure = useMutation({
    mutationFn: (v: { date: string; reason: string }) =>
      declareClosure(active, v.date, v.reason),
    onSuccess: () => say('Closure recorded. Registers cannot be opened that day.'),
    onError: fail,
  })

  const all = rows.data ?? []
  const unconfirmed = all.filter((r) => !r.confirmed_at).length
  const counts = OUTCOMES.map((o) => ({
    outcome: o, n: all.filter((r) => r.effective_outcome === o).length,
  })).filter((c) => c.n > 0)

  if (!canManage && !canDecide) {
    return <p className="p-6 text-sm text-slate-600">
      Year-end is a Rector and school administration function.
    </p>
  }

  return (
    <div className="mx-auto max-w-6xl space-y-6 p-4 sm:p-6">
      <header>
        <h1 className="text-lg font-semibold text-slate-900">Year end</h1>
        <p className="mt-1 text-sm text-slate-600">
          Promotion and rollover, in the order they happen. Each step is blocked
          until the one before it is done — rollover refuses while any decision
          is still unconfirmed.
        </p>
      </header>

      {note && (
        <div className="rounded-md bg-slate-900 px-3 py-2 text-sm text-white">{note}</div>
      )}

      <label className="block text-sm">
        <span className="font-medium text-slate-700">Academic year</span>
        <select
          value={active}
          onChange={(e) => { setFromYear(e.target.value); setDryRun(null) }}
          className="mt-1 block w-full max-w-sm rounded-md border-slate-300 text-sm"
        >
          {(years.data ?? []).map((y) => (
            <option key={y.id} value={y.id}>{y.name} — {y.status}</option>
          ))}
        </select>
      </label>

      {/* ── 1 ─────────────────────────────────────────────────────────── */}
      <Step n={1} title="Evaluate">
        <p className="text-sm text-slate-600">
          Runs every enrolled pupil through the year&apos;s promotion rules.
          Re-running is safe: it never overwrites a decision already confirmed.
        </p>
        <div className="mt-3 flex flex-wrap gap-2">
          <Button onClick={() => evaluate.mutate()} busy={evaluate.isPending}>
            Evaluate promotions
          </Button>
          <Button subtle onClick={() => seed.mutate()} busy={seed.isPending}>
            Seed default rules
          </Button>
        </div>
        {counts.length > 0 && (
          <div className="mt-3 flex flex-wrap gap-2">
            {counts.map((c) => (
              <span key={c.outcome}
                className={`rounded-full px-2.5 py-1 text-xs font-semibold ring-1 ${TONE[c.outcome]}`}>
                {LABEL[c.outcome]}: {c.n}
              </span>
            ))}
          </div>
        )}
      </Step>

      {/* ── 2 ─────────────────────────────────────────────────────────── */}
      <Step n={2} title="Review and overrule">
        {all.length === 0 ? (
          <p className="text-sm text-slate-500">
            Nothing evaluated yet for this year.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead className="text-left text-xs uppercase tracking-wide text-slate-500">
                <tr>
                  <th className="py-2 pr-3">Pupil</th>
                  <th className="py-2 pr-3">Class</th>
                  <th className="py-2 pr-3 text-right">Aggregate</th>
                  <th className="py-2 pr-3 text-right">Attendance</th>
                  <th className="py-2 pr-3 text-right">Repeats</th>
                  <th className="py-2 pr-3">Rule</th>
                  <th className="py-2 pr-3">Outcome</th>
                  <th className="py-2" />
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {all.map((r) => (
                  <Row key={r.student_id} row={r} canDecide={canDecide}
                       onOverride={(outcome, reason) =>
                         override.mutate({ student: r.student_id, outcome, reason })} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Step>

      {/* ── 3 ─────────────────────────────────────────────────────────── */}
      <Step n={3} title="Confirm">
        <p className="text-sm text-slate-600">
          {unconfirmed > 0
            ? `${unconfirmed} decision${unconfirmed === 1 ? '' : 's'} still unconfirmed.`
            : all.length > 0
              ? 'All decisions confirmed.'
              : 'Nothing to confirm yet.'}
          {' '}Confirming freezes them: re-evaluating will not overwrite a
          confirmed decision.
        </p>
        <div className="mt-3">
          <Button
            onClick={() => confirmAll.mutate()}
            busy={confirmAll.isPending}
            disabled={!canDecide || unconfirmed === 0}
          >
            Confirm {unconfirmed > 0 ? unconfirmed : ''} decision{unconfirmed === 1 ? '' : 's'}
          </Button>
          {!canDecide && (
            <p className="mt-2 text-xs text-slate-500">
              Only the Rector may confirm promotions.
            </p>
          )}
        </div>
      </Step>

      {/* ── 4 ─────────────────────────────────────────────────────────── */}
      <Step n={4} title="Roll over into next year">
        <p className="text-sm text-slate-600">
          Closes this year, opens the next, and moves every pupil into the class
          their outcome implies. <strong>Always dry run first</strong> — it
          reports anyone it cannot place because next year has no class of the
          right grade.
        </p>
        <div className="mt-3 flex flex-wrap items-end gap-3">
          <label className="block text-sm">
            <span className="font-medium text-slate-700">Into</span>
            <select
              value={toYear}
              onChange={(e) => { setToYear(e.target.value); setDryRun(null) }}
              className="mt-1 block rounded-md border-slate-300 text-sm"
            >
              <option value="">Choose a year…</option>
              {(years.data ?? []).filter((y) => y.id !== active).map((y) => (
                <option key={y.id} value={y.id}>{y.name} — {y.status}</option>
              ))}
            </select>
          </label>
          <Button subtle disabled={!toYear} busy={roll.isPending}
                  onClick={() => roll.mutate(false)}>
            Dry run
          </Button>
          <Button
            disabled={!toYear || !dryRun || dryRun.committed || unconfirmed > 0}
            busy={roll.isPending}
            onClick={() => {
              if (window.confirm(
                'This closes the current year and moves every pupil. Continue?',
              )) roll.mutate(true)
            }}
          >
            Commit rollover
          </Button>
        </div>

        {dryRun && (
          <div className="mt-4 rounded-md border border-slate-200 bg-slate-50 p-3 text-sm">
            <p className="font-medium text-slate-800">
              {dryRun.committed ? 'Committed' : 'Dry run — nothing was saved'}
            </p>
            <ul className="mt-2 grid grid-cols-2 gap-x-6 gap-y-1 text-slate-700 sm:grid-cols-4">
              <li>Promoted: <strong>{dryRun.promoted}</strong></li>
              <li>Repeating: <strong>{dryRun.repeated}</strong></li>
              <li>Leaving: <strong>{dryRun.left}</strong></li>
              <li>Referred: <strong>{dryRun.referred}</strong></li>
            </ul>
            {dryRun.unplaced_count > 0 && (
              <p className="mt-3 rounded bg-amber-50 px-2 py-1.5 text-amber-900 ring-1 ring-amber-200">
                <strong>{dryRun.unplaced_count} pupil(s) cannot be placed.</strong>{' '}
                Next year has no class for the grade they need. Create those
                classes first — they would otherwise be left behind silently.
              </p>
            )}
          </div>
        )}
      </Step>

      {/* ── year setup ─────────────────────────────────────────────────── */}
      <Step title="Calendar">
        <p className="text-sm text-slate-600">
          Builds the teaching days for a year from its terms and public
          holidays. The cycle length must match the timetable, because
          cycle_day is what lessons are keyed on.
        </p>
        <CalendarTools
          busy={calendar.isPending || closure.isPending}
          onGenerate={(cycle) => calendar.mutate({ year: active, cycle })}
          onClose={(date, reason) => closure.mutate({ date, reason })}
        />
      </Step>
    </div>
  )
}

function Row({ row, canDecide, onOverride }: {
  row: PromotionRow
  canDecide: boolean
  onOverride: (o: PromotionOutcome, reason: string) => void
}) {
  const [open, setOpen] = useState(false)
  const [outcome, setOutcome] = useState<PromotionOutcome>(row.effective_outcome)
  const [reason, setReason] = useState('')

  return (
    <>
      <tr>
        <td className="py-2 pr-3">
          <span className="font-medium text-slate-900">
            {row.first_name} {row.last_name}
          </span>
          {row.admission_number && (
            <span className="ml-2 text-xs text-slate-400">{row.admission_number}</span>
          )}
        </td>
        <td className="py-2 pr-3 text-slate-600">{row.class_name ?? '—'}</td>
        <td className="py-2 pr-3 text-right tabular-nums">{row.aggregate ?? '—'}</td>
        <td className="py-2 pr-3 text-right tabular-nums">
          {row.attendance_pct != null ? `${row.attendance_pct}%` : '—'}
        </td>
        <td className="py-2 pr-3 text-right tabular-nums">{row.times_repeated ?? 0}</td>
        <td className="py-2 pr-3 text-xs text-slate-500">{row.rule_name ?? '—'}</td>
        <td className="py-2 pr-3">
          <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ring-1 ${TONE[row.effective_outcome]}`}>
            {LABEL[row.effective_outcome]}
          </span>
          {row.override_outcome && (
            <span className="ml-1.5 text-xs text-slate-400" title={row.override_reason ?? ''}>
              overruled
            </span>
          )}
        </td>
        <td className="py-2 text-right">
          {canDecide && !row.confirmed_at && (
            <button onClick={() => setOpen(!open)}
                    className="text-xs font-medium text-brand hover:underline">
              {open ? 'Cancel' : 'Overrule'}
            </button>
          )}
          {row.confirmed_at && <span className="text-xs text-slate-400">confirmed</span>}
        </td>
      </tr>
      {open && (
        <tr>
          <td colSpan={8} className="bg-slate-50 px-3 py-3">
            <div className="flex flex-wrap items-end gap-2">
              <label className="text-sm">
                <span className="block text-xs font-medium text-slate-600">Outcome</span>
                <select value={outcome} className="mt-1 rounded-md border-slate-300 text-sm"
                        onChange={(e) => setOutcome(e.target.value as PromotionOutcome)}>
                  {OUTCOMES.map((o) => <option key={o} value={o}>{LABEL[o]}</option>)}
                </select>
              </label>
              <label className="min-w-[16rem] flex-1 text-sm">
                <span className="block text-xs font-medium text-slate-600">
                  Reason (required — this is a decision about a child, and it is audited)
                </span>
                <input value={reason} onChange={(e) => setReason(e.target.value)}
                       className="mt-1 w-full rounded-md border-slate-300 text-sm"
                       placeholder="Why the engine's verdict is being set aside" />
              </label>
              <Button
                disabled={!reason.trim()}
                onClick={() => { onOverride(outcome, reason.trim()); setOpen(false); setReason('') }}
              >
                Save override
              </Button>
            </div>
          </td>
        </tr>
      )}
    </>
  )
}

function CalendarTools({ busy, onGenerate, onClose }: {
  busy: boolean
  onGenerate: (cycle: number) => void
  onClose: (date: string, reason: string) => void
}) {
  const [cycle, setCycle] = useState(5)
  const [date, setDate] = useState('')
  const [reason, setReason] = useState('')

  return (
    <div className="mt-3 grid gap-4 sm:grid-cols-2">
      <div className="flex items-end gap-2">
        <label className="text-sm">
          <span className="block text-xs font-medium text-slate-600">Cycle length (days)</span>
          <input type="number" min={1} max={20} value={cycle}
                 onChange={(e) => setCycle(Number(e.target.value))}
                 className="mt-1 w-24 rounded-md border-slate-300 text-sm" />
        </label>
        <Button subtle busy={busy} onClick={() => onGenerate(cycle)}>
          Generate calendar
        </Button>
      </div>

      <div className="flex flex-wrap items-end gap-2">
        <label className="text-sm">
          <span className="block text-xs font-medium text-slate-600">Closure date</span>
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)}
                 className="mt-1 rounded-md border-slate-300 text-sm" />
        </label>
        <label className="min-w-[10rem] flex-1 text-sm">
          <span className="block text-xs font-medium text-slate-600">Reason</span>
          <input value={reason} onChange={(e) => setReason(e.target.value)}
                 placeholder="Cyclone warning class III"
                 className="mt-1 w-full rounded-md border-slate-300 text-sm" />
        </label>
        <Button subtle busy={busy} disabled={!date || !reason.trim()}
                onClick={() => { onClose(date, reason.trim()); setDate(''); setReason('') }}>
          Declare closure
        </Button>
      </div>
    </div>
  )
}

function Step({ n, title, children }: {
  n?: number; title: string; children: React.ReactNode
}) {
  return (
    <section className="rounded-lg border border-slate-200 p-4">
      <h2 className="mb-2 flex items-center gap-2 text-sm font-semibold text-slate-900">
        {n != null && (
          <span className="grid h-5 w-5 place-items-center rounded-full bg-slate-900 text-[11px] text-white">
            {n}
          </span>
        )}
        {title}
      </h2>
      {children}
    </section>
  )
}

function Button({ children, onClick, busy, disabled, subtle }: {
  children: React.ReactNode
  onClick?: () => void
  busy?: boolean
  disabled?: boolean
  subtle?: boolean
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled || busy}
      className={`rounded-md px-3 py-1.5 text-sm font-semibold disabled:opacity-40 ${
        subtle
          ? 'bg-white text-slate-700 ring-1 ring-slate-300 hover:bg-slate-50'
          : 'bg-brand text-white hover:opacity-90'
      }`}
    >
      {busy ? 'Working…' : children}
    </button>
  )
}
