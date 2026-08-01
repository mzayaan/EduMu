import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { displayName, formatLongDate, todayInMauritius } from '@/lib/format'
import {
  fetchDiscrepancies, resolveDiscrepancy,
  type Discrepancy, type Outcome,
} from './api'

const OUTCOMES: { value: Outcome; label: string; hint: string }[] = [
  { value: 'found_on_premises', label: 'Found on premises', hint: 'Located in school — sent to class' },
  { value: 'medical_room',      label: 'Medical room',      hint: 'With the matron or first aid' },
  { value: 'authorised',        label: 'Authorised',        hint: 'Legitimate reason for being out of the lesson' },
  { value: 'left_school',       label: 'Left school',       hint: 'Absconded — marks the PM register absent' },
  { value: 'unresolved',        label: 'Unresolved',        hint: 'Could not be established' },
]

export function DiscrepancyBoard() {
  const qc = useQueryClient()
  const [date, setDate] = useState(todayInMauritius())
  const [showResolved, setShowResolved] = useState(false)
  const [live, setLive] = useState(false)

  const list = useQuery({
    queryKey: ['discrepancies', date],
    queryFn: () => fetchDiscrepancies(date),
    refetchInterval: 60_000, // belt and braces if the socket drops
  })

  // Realtime: a pupil shirking a lesson should surface within seconds, not on
  // the next refresh. RLS still applies to the stream.
  useEffect(() => {
    const channel = supabase
      .channel('discrepancy-board')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'attendance_discrepancy' },
        () => { void qc.invalidateQueries({ queryKey: ['discrepancies'] }) },
      )
      .subscribe((status) => setLive(status === 'SUBSCRIBED'))
    return () => { void supabase.removeChannel(channel) }
  }, [qc])

  const resolve = useMutation({
    mutationFn: ({ id, outcome }: { id: string; outcome: Outcome }) =>
      resolveDiscrepancy(id, outcome),
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['discrepancies'] }) },
  })

  const { open, resolved } = useMemo(() => {
    const all = list.data ?? []
    return {
      open: all.filter((d) => d.resolved_at === null),
      resolved: all.filter((d) => d.resolved_at !== null),
    }
  }, [list.data])

  return (
    <div className="mx-auto w-full max-w-3xl pb-32">
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h1 className="text-lg font-semibold">Attendance Discrepancies</h1>
            <p className="text-sm text-slate-500">{formatLongDate(date)}</p>
          </div>
          <span
            className={`rounded-full px-2.5 py-1 text-xs font-medium ${
              live ? 'bg-green-50 text-green-700' : 'bg-slate-100 text-slate-500'
            }`}
          >
            {live ? 'Live' : 'Connecting…'}
          </span>
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-2">
          <input
            type="date" value={date} onChange={(e) => setDate(e.target.value)}
            className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium"
          />
          <span className="inline-flex items-baseline gap-1">
            <span className="text-base font-semibold tabular-nums text-absent">{open.length}</span>
            <span className="text-xs text-slate-500">open</span>
          </span>
          <button
            onClick={() => setShowResolved((v) => !v)}
            className="h-10 rounded-lg border border-slate-300 px-3 text-sm font-medium"
          >
            {showResolved ? 'Hide' : 'Show'} resolved ({resolved.length})
          </button>
        </div>
      </header>

      {list.isLoading && <p className="px-4 py-8 text-sm text-slate-500">Loading…</p>}

      {!list.isLoading && open.length === 0 && (
        <div className="px-4 py-12 text-center">
          <p className="text-sm font-medium text-slate-700">Nothing outstanding</p>
          <p className="mt-1 text-xs text-slate-400">
            Every pupil on the register has been accounted for in class.
          </p>
        </div>
      )}

      <ul className="divide-y divide-slate-100">
        {open.map((d) => (
          <Row key={d.id} d={d} onResolve={(o) => resolve.mutate({ id: d.id, outcome: o })}
               pending={resolve.isPending} />
        ))}
        {showResolved && resolved.map((d) => <Row key={d.id} d={d} />)}
      </ul>
    </div>
  )
}

function Row({ d, onResolve, pending }: {
  d: Discrepancy
  onResolve?: (o: Outcome) => void
  pending?: boolean
}) {
  const shirking = d.kind === 'present_on_register_absent_in_class'
  return (
    <li className={`px-4 py-3 ${d.resolved_at ? 'opacity-60' : ''}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-sm font-medium">
            {displayName(d)}
            <span className="ml-2 text-xs font-normal text-slate-400">
              {d.admission_number} · {d.class_name}
            </span>
          </p>
          <p className="mt-0.5 text-xs text-slate-500">
            {shirking ? (
              <>Marked <b className="text-present">present</b> on the register but{' '}
                <b className="text-absent">absent</b> in {d.subject_name}</>
            ) : (
              <>Marked <b className="text-absent">absent</b> on the register but{' '}
                <b className="text-present">present</b> in {d.subject_name}</>
            )}
            {d.period_name && ` · ${d.period_name}`}
            {d.reported_by_educator && ` · reported by ${d.reported_by_educator}`}
          </p>
        </div>
        <span
          className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase ${
            shirking ? 'bg-red-50 text-absent' : 'bg-blue-50 text-authorised'
          }`}
        >
          {shirking ? 'Shirking' : 'Register wrong'}
        </span>
      </div>

      {d.resolved_at ? (
        <p className="mt-2 text-xs text-slate-500">
          {OUTCOMES.find((o) => o.value === d.outcome)?.label ?? d.outcome}
          {d.resolved_by_name && ` — ${d.resolved_by_name}`}
        </p>
      ) : (
        <div className="mt-2 flex flex-wrap gap-1.5">
          {OUTCOMES.map((o) => (
            <button
              key={o.value}
              title={o.hint}
              disabled={pending}
              onClick={() => onResolve?.(o.value)}
              className="h-9 rounded-lg border border-slate-200 px-2.5 text-xs font-medium
                         text-slate-600 hover:border-slate-400 disabled:opacity-50"
            >
              {o.label}
            </button>
          ))}
        </div>
      )}
    </li>
  )
}
