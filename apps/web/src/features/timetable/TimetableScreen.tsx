import { useEffect, useMemo, useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { EduClaims } from '@/lib/supabase'
import { hasCap } from '@/lib/supabase'
import { formatDate, todayInMauritius } from '@/lib/format'
import * as api from './api'

type View = 'grid' | 'solve' | 'cover'

export function TimetableScreen({ claims }: { claims: EduClaims }) {
  const [view, setView] = useState<View>('grid')
  const [versionId, setVersionId] = useState<string | null>(null)

  const versions = useQuery({ queryKey: ['tt-versions'], queryFn: api.fetchVersions })
  useEffect(() => {
    if (!versionId && versions.data?.length) setVersionId(versions.data[0]!.id)
  }, [versions.data, versionId])

  const version = versions.data?.find((v) => v.id === versionId)

  return (
    <div className="mx-auto w-full max-w-5xl pb-32">
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h1 className="text-lg font-semibold">Timetable</h1>
            <p className="text-sm text-slate-500">
              {version ? `Version ${version.version} · ${version.cycle_length}-day cycle` : '—'}
            </p>
          </div>
          {version && (
            <span className={`rounded-full px-2.5 py-1 text-xs font-medium capitalize ${
              version.status === 'published' ? 'bg-green-50 text-green-700'
              : version.status === 'draft' ? 'bg-slate-100 text-slate-600'
              : 'bg-amber-50 text-amber-800'}`}>
              {version.status}
            </span>
          )}
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-2">
          <select value={versionId ?? ''} onChange={(e) => setVersionId(e.target.value)}
                  className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium">
            {(versions.data ?? []).map((v) => (
              <option key={v.id} value={v.id}>
                v{v.version} {v.label ? `· ${v.label}` : ''} ({v.status})
              </option>
            ))}
          </select>
          <nav className="flex gap-1">
            {(['grid', 'solve', 'cover'] as View[]).map((t) => (
              <button key={t} onClick={() => setView(t)}
                className={`h-10 rounded-lg px-3 text-sm font-medium capitalize ${
                  view === t ? 'bg-brand text-white' : 'text-slate-600 hover:bg-slate-100'}`}>
                {t === 'cover' ? 'Daily cover' : t}
              </button>
            ))}
          </nav>
        </div>
      </header>

      {versionId && view === 'grid' && <Grid versionId={versionId} />}
      {versionId && view === 'solve' && (
        <Solve versionId={versionId} claims={claims}
               cycleLength={version?.cycle_length ?? 5} status={version?.status ?? 'draft'} />
      )}
      {view === 'cover' && <Cover claims={claims} />}
    </div>
  )
}

function Grid({ versionId }: { versionId: string }) {
  const periods = useQuery({ queryKey: ['tt-periods', versionId], queryFn: () => api.fetchPeriods(versionId) })
  const slots = useQuery({ queryKey: ['tt-slots', versionId], queryFn: () => api.fetchSlots(versionId) })

  const teaching = (periods.data ?? []).filter((p) => p.is_teaching)
  const days = useMemo(() => {
    const max = Math.max(1, ...(slots.data ?? []).map((s: any) => s.cycle_day))
    return Array.from({ length: max }, (_, i) => i + 1)
  }, [slots.data])

  const at = (d: number, pid: string) =>
    (slots.data ?? []).filter((s: any) => s.cycle_day === d && s.period_id === pid)

  if (slots.isLoading) return <p className="px-4 py-8 text-sm text-slate-500">Loading…</p>
  if ((slots.data ?? []).length === 0) {
    return (
      <p className="px-4 py-12 text-center text-sm text-slate-500">
        This version has no lessons yet. Use <b>Solve</b> to generate one.
      </p>
    )
  }

  return (
    <div className="overflow-x-auto px-4 py-3">
      <table className="w-full border-collapse text-xs">
        <thead>
          <tr>
            <th className="p-2 text-left font-semibold text-slate-500">Day</th>
            {teaching.map((p) => (
              <th key={p.id} className="p-2 text-center font-semibold">
                <div>{p.name}</div>
                <div className="font-normal text-slate-400">{p.starts_at.slice(0, 5)}</div>
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {days.map((d) => (
            <tr key={d} className="border-t border-slate-100">
              <td className="p-2 font-semibold text-slate-500">Day {d}</td>
              {teaching.map((p) => (
                <td key={p.id} className="p-1 align-top">
                  {at(d, p.id).map((s: any) => (
                    <div key={s.id}
                         className="mb-1 rounded-md border border-slate-200 bg-slate-50 px-1.5 py-1">
                      <div className="truncate font-medium">{s.set_name}</div>
                      <div className="truncate text-slate-400">{s.room_code}</div>
                    </div>
                  ))}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function Solve({ versionId, claims, cycleLength, status }: {
  versionId: string; claims: EduClaims; cycleLength: number; status: string
}) {
  const qc = useQueryClient()
  const [budget, setBudget] = useState(10)
  const [seed, setSeed] = useState(42)
  const [running, setRunning] = useState(false)
  const [result, setResult] = useState<any>(null)
  const [error, setError] = useState<string | null>(null)
  const workerRef = useRef<Worker | null>(null)

  const periods = useQuery({ queryKey: ['tt-periods', versionId], queryFn: () => api.fetchPeriods(versionId) })

  const apply = useMutation({
    mutationFn: async () => {
      const teaching = (periods.data ?? []).filter((p) => p.is_teaching)
      const placements = result.result.placements.map((pl: any) => ({
        setId: pl.setId,
        cycleDay: pl.cycleDay,
        periodId: teaching[pl.period - 1]?.id,
        roomId: pl.roomId,
        educatorId: pl.educatorId,
        isDoubleStart: pl.isDoubleStart,
      })).filter((p: any) => p.periodId)
      return api.applyTimetable(versionId, placements)
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['tt-slots'] })
      void qc.invalidateQueries({ queryKey: ['tt-versions'] })
    },
  })

  const publish = useMutation({
    mutationFn: () => api.publishTimetable(versionId, todayInMauritius()),
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['tt-versions'] }) },
  })

  async function run() {
    setRunning(true); setError(null); setResult(null)
    try {
      const inputs = await api.fetchSolverInputs(claims.year_id!)
      const teaching = (periods.data ?? []).filter((p) => p.is_teaching)

      const worker = new Worker(
        new URL('../../workers/timetable.worker.ts', import.meta.url),
        { type: 'module' },
      )
      workerRef.current = worker
      worker.onmessage = (e) => {
        if (e.data.type === 'error') setError(e.data.message)
        else setResult(e.data)
        setRunning(false)
        worker.terminate()
      }
      worker.postMessage({
        type: 'solve',
        input: {
          ...inputs,
          cycleLength,
          periods: teaching.map((_, i) => i + 1),
          seed,
          timeBudgetMs: budget * 1000,
        },
      })
    } catch (err) {
      setError((err as Error).message); setRunning(false)
    }
  }

  const r = result?.result

  return (
    <div className="px-4 py-4">
      <div className="rounded-xl border border-slate-200 p-4">
        <p className="text-sm font-medium">Generate a timetable</p>
        <p className="mt-0.5 text-xs text-slate-500">
          The solver runs in a background thread. It produces a strong draft in
          seconds — you always keep the final say in the grid.
        </p>

        <div className="mt-3 flex flex-wrap items-end gap-3">
          <label className="text-xs font-medium">
            Effort (seconds)
            <input type="number" min={0} max={120} value={budget}
                   onChange={(e) => setBudget(Number(e.target.value))}
                   className="mt-1 h-10 w-24 rounded-lg border border-slate-300 px-2 text-sm" />
          </label>
          <label className="text-xs font-medium">
            Seed
            <input type="number" value={seed} onChange={(e) => setSeed(Number(e.target.value))}
                   className="mt-1 h-10 w-24 rounded-lg border border-slate-300 px-2 text-sm" />
            <span className="ml-2 text-slate-400">different seed, different layout</span>
          </label>
          <button onClick={run} disabled={running || status === 'published'}
                  className="h-10 rounded-lg bg-brand px-4 text-sm font-semibold text-white disabled:opacity-50">
            {running ? 'Solving…' : 'Solve'}
          </button>
        </div>

        {status === 'published' && (
          <p className="mt-2 text-xs text-amber-800">
            This version is published and immutable. Create a new version to change it.
          </p>
        )}
        {error && <p className="mt-2 text-sm text-absent">{error}</p>}
      </div>

      {r && (
        <div className="mt-4 rounded-xl border border-slate-200 p-4">
          <div className="flex flex-wrap gap-4 text-sm">
            <Stat label="Lessons placed" value={r.placements.length} />
            <Stat label="Could not place" value={r.unplaced.length}
                  tone={r.unplaced.length ? 'text-absent' : 'text-present'} />
            <Stat label="Quality score" value={Math.round(r.score)} />
            <Stat label="Iterations" value={r.iterations} />
          </div>

          <p className={`mt-2 text-xs ${result.check.ok ? 'text-present' : 'text-absent'}`}>
            {result.check.ok
              ? 'No clashes: every educator, room and pupil is free in every slot.'
              : `${result.check.problems.length} hard-constraint problem(s)`}
          </p>

          {r.unplaced.length > 0 && (
            <>
              <p className="mt-3 text-xs font-semibold">Not placed — needs a human decision</p>
              <ul className="mt-1 space-y-1">
                {r.unplaced.map((u: any) => (
                  <li key={u.setId} className="text-xs text-slate-600">
                    <b>{u.name}</b> — {u.periods} period(s): {u.reason}
                  </li>
                ))}
              </ul>
            </>
          )}

          <div className="mt-4 flex gap-2">
            <button onClick={() => apply.mutate()} disabled={apply.isPending}
                    className="h-10 rounded-lg bg-brand px-4 text-sm font-semibold text-white disabled:opacity-50">
              {apply.isPending ? 'Saving…' : `Save ${r.placements.length} lessons to this version`}
            </button>
            {hasCap(claims, 'timetable.publish') && status !== 'published' && (
              <button onClick={() => publish.mutate()} disabled={publish.isPending}
                      className="h-10 rounded-lg border border-slate-300 px-4 text-sm font-semibold">
                Publish
              </button>
            )}
          </div>
          {apply.isSuccess && (
            <p className="mt-2 text-xs text-present">{apply.data} lessons saved.</p>
          )}
        </div>
      )}
    </div>
  )
}

function Cover({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [date, setDate] = useState(todayInMauritius())
  const uncovered = useQuery({
    queryKey: ['uncovered', date],
    queryFn: () => api.fetchUncovered(date),
  })
  const [openSlot, setOpenSlot] = useState<string | null>(null)
  const candidates = useQuery({
    queryKey: ['substitutes', date, openSlot],
    queryFn: () => api.fetchSubstitutes(date, openSlot!),
    enabled: Boolean(openSlot),
  })
  const assign = useMutation({
    mutationFn: (v: { slot: string; absent: string; sub: string }) =>
      api.assignSubstitute({
        school_id: claims.school_id!, date,
        timetable_slot_id: v.slot, absent_staff_id: v.absent, substitute_staff_id: v.sub,
      }),
    onSuccess: () => {
      setOpenSlot(null)
      void qc.invalidateQueries({ queryKey: ['uncovered'] })
    },
  })

  return (
    <div className="px-4 py-4">
      <input type="date" value={date} onChange={(e) => setDate(e.target.value)}
             className="h-10 rounded-lg border border-slate-300 px-3 text-sm font-medium" />

      {(uncovered.data ?? []).length === 0 ? (
        <p className="py-12 text-center text-sm text-slate-500">
          No lessons need cover on {formatDate(date)}.
        </p>
      ) : (
        <ul className="mt-4 divide-y divide-slate-100">
          {(uncovered.data ?? []).map((u: any) => (
            <li key={u.timetable_slot_id} className="py-3">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="text-sm font-medium">
                    {u.period_name} · {u.subject_name}
                  </p>
                  <p className="text-xs text-slate-400">
                    {u.set_name} · {u.room_code} · {u.absent_staff_name} away
                  </p>
                </div>
                <button
                  onClick={() => setOpenSlot(openSlot === u.timetable_slot_id ? null : u.timetable_slot_id)}
                  className="h-9 shrink-0 rounded-lg border border-slate-300 px-3 text-xs font-semibold"
                >
                  Find cover
                </button>
              </div>

              {openSlot === u.timetable_slot_id && (
                <ul className="mt-2 space-y-1">
                  {(candidates.data ?? []).map((c: any) => (
                    <li key={c.staff_id}>
                      <button
                        onClick={() => assign.mutate({
                          slot: u.timetable_slot_id,
                          absent: u.absent_staff_id,
                          sub: c.staff_id,
                        })}
                        className="flex w-full items-center justify-between rounded-lg border
                                   border-slate-200 px-3 py-2 text-left text-sm hover:border-brand"
                      >
                        <span>{c.staff_name}</span>
                        <span className="text-xs text-slate-400">{c.reason}</span>
                      </button>
                    </li>
                  ))}
                  {(candidates.data ?? []).length === 0 && !candidates.isLoading && (
                    <li className="text-xs text-absent">
                      Nobody is free. Consider merging classes or supervised study.
                    </li>
                  )}
                </ul>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

function Stat({ label, value, tone = 'text-slate-700' }: {
  label: string; value: number; tone?: string
}) {
  return (
    <span className="inline-flex items-baseline gap-1">
      <span className={`text-base font-semibold tabular-nums ${tone}`}>{value}</span>
      <span className="text-xs text-slate-500">{label}</span>
    </span>
  )
}
