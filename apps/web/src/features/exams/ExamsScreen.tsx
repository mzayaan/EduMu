import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { displayName, formatDate } from '@/lib/format'
import { fetchExamSessions } from '@/features/eligibility/api'
import * as api from './api'

const STRATEGIES = [
  { value: 'separate_class', label: 'Separate classmates',
    hint: 'Neighbours are rarely from the same class' },
  { value: 'spaced', label: 'Spaced',
    hint: 'Leave every other seat empty — needs the capacity' },
  { value: 'sequential', label: 'Sequential',
    hint: 'Straight fill by admission number, for a tight hall' },
]

export function ExamsScreen() {
  const qc = useQueryClient()
  const [sessionId, setSessionId] = useState<string | null>(null)
  const [paperId, setPaperId] = useState<string | null>(null)
  const [strategy, setStrategy] = useState('separate_class')
  const [perRoom, setPerRoom] = useState(2)
  const [error, setError] = useState<string | null>(null)

  const sessions = useQuery({ queryKey: ['exam-sessions'], queryFn: fetchExamSessions })
  useEffect(() => {
    if (!sessionId && sessions.data?.length) setSessionId(sessions.data[0]!.id)
  }, [sessions.data, sessionId])

  const papers = useQuery({
    queryKey: ['exam-papers', sessionId],
    queryFn: () => api.fetchPapers(sessionId!),
    enabled: Boolean(sessionId),
  })
  useEffect(() => {
    if (papers.data?.length && !papers.data.some((p) => p.id === paperId)) {
      setPaperId(papers.data[0]!.id)
    }
  }, [papers.data, paperId])

  const candidates = useQuery({
    queryKey: ['exam-candidates', paperId],
    queryFn: () => api.fetchCandidates(paperId!),
    enabled: Boolean(paperId),
  })
  const plan = useQuery({
    queryKey: ['seating-plan', paperId],
    queryFn: () => api.fetchSeatingPlan(paperId!),
    enabled: Boolean(paperId),
  })
  const duties = useQuery({
    queryKey: ['duties', paperId],
    queryFn: () => api.fetchDuties(paperId!),
    enabled: Boolean(paperId),
  })

  const allocate = useMutation({
    mutationFn: () => api.allocateSeats(paperId!, strategy),
    onSuccess: () => {
      setError(null)
      void qc.invalidateQueries({ queryKey: ['seating-plan'] })
    },
    onError: (e: any) => setError(e.message),
  })

  const roster = useMutation({
    mutationFn: () => api.assignInvigilators(paperId!, perRoom),
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['duties'] }) },
    onError: (e: any) => setError(e.message),
  })

  const paper = papers.data?.find((p) => p.id === paperId)
  const sitting = (candidates.data ?? []).filter((c) => !c.debarred)
  const debarred = (candidates.data ?? []).filter((c) => c.debarred)
  const withArrangements = sitting.filter((c) => c.arrangement)

  const byRoom = useMemo(() => {
    const m = new Map<string, api.Seat[]>()
    for (const s of plan.data ?? []) {
      if (!m.has(s.room_code)) m.set(s.room_code, [])
      m.get(s.room_code)!.push(s)
    }
    return [...m.entries()]
  }, [plan.data])

  return (
    <div className="mx-auto w-full max-w-4xl pb-32">
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <h1 className="text-lg font-semibold">Examinations</h1>
        <p className="text-sm text-slate-500">Papers, seating and invigilation</p>

        <div className="mt-3 flex flex-wrap items-center gap-2">
          <select value={sessionId ?? ''} onChange={(e) => setSessionId(e.target.value)}
                  className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium">
            {(sessions.data ?? []).map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
          <select value={paperId ?? ''} onChange={(e) => setPaperId(e.target.value)}
                  className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium">
            {(papers.data ?? []).map((p) => (
              <option key={p.id} value={p.id}>
                {p.subject_name} · Grade {p.grade} · {formatDate(p.date)}
              </option>
            ))}
          </select>
        </div>

        {paper && (
          <p className="mt-2 text-xs text-slate-500">
            {formatDate(paper.date)} at {paper.starts_at.slice(0, 5)} ·{' '}
            {paper.duration_minutes} minutes · {sitting.length} sitting
            {debarred.length > 0 && ` · ${debarred.length} debarred`}
            {withArrangements.length > 0 && ` · ${withArrangements.length} with arrangements`}
          </p>
        )}
      </header>

      {error && <p className="px-4 pt-3 text-sm text-absent">{error}</p>}

      <div className="px-4 py-4">
        <div className="rounded-xl border border-slate-200 p-4">
          <p className="text-sm font-medium">Seating</p>
          <div className="mt-2 flex flex-wrap items-end gap-2">
            <label className="text-xs font-medium">
              Strategy
              <select value={strategy} onChange={(e) => setStrategy(e.target.value)}
                      className="mt-1 h-10 w-56 rounded-lg border border-slate-300 px-2 text-sm">
                {STRATEGIES.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
              </select>
            </label>
            <button onClick={() => allocate.mutate()} disabled={allocate.isPending || !paperId}
                    className="h-10 rounded-lg bg-brand px-4 text-sm font-semibold text-white disabled:opacity-50">
              {allocate.isPending ? 'Allocating…' : 'Allocate seats'}
            </button>
          </div>
          <p className="mt-1 text-xs text-slate-400">
            {STRATEGIES.find((s) => s.value === strategy)?.hint}
          </p>
          {allocate.isSuccess && (
            <p className="mt-2 text-xs text-present">{allocate.data} candidates seated.</p>
          )}

          <p className="mt-4 text-sm font-medium">Invigilation</p>
          <div className="mt-2 flex flex-wrap items-end gap-2">
            <label className="text-xs font-medium">
              Per room
              <input type="number" min={1} max={5} value={perRoom}
                     onChange={(e) => setPerRoom(Number(e.target.value))}
                     className="mt-1 h-10 w-20 rounded-lg border border-slate-300 px-2 text-sm" />
            </label>
            <button onClick={() => roster.mutate()} disabled={roster.isPending || !paperId}
                    className="h-10 rounded-lg border border-slate-300 px-4 text-sm font-semibold">
              {roster.isPending ? 'Assigning…' : 'Assign invigilators'}
            </button>
          </div>
          <p className="mt-1 text-xs text-slate-400">
            Duties go to whoever has invigilated least this session, skipping anyone on leave.
          </p>
        </div>

        {debarred.length > 0 && (
          <div className="mt-4 rounded-xl border border-red-200 bg-red-50 p-3">
            <p className="text-xs font-semibold text-absent">
              Not sitting — debarred by the Rector
            </p>
            <ul className="mt-1 text-xs text-slate-700">
              {debarred.map((c) => (
                <li key={c.student_id}>{displayName(c)} · {c.admission_number}</li>
              ))}
            </ul>
          </div>
        )}

        {(duties.data ?? []).length > 0 && (
          <div className="mt-4">
            <h2 className="text-sm font-semibold">Invigilation roster</h2>
            <ul className="mt-2 divide-y divide-slate-100">
              {duties.data!.map((d: any) => (
                <li key={d.id} className="flex items-center justify-between py-2 text-sm">
                  <span>{d.staff_name}</span>
                  <span className="text-xs text-slate-400">
                    {d.room_code} · {d.role}
                  </span>
                </li>
              ))}
            </ul>
          </div>
        )}

        {byRoom.map(([room, seats]) => (
          <div key={room} className="mt-6">
            <h2 className="text-sm font-semibold">Seating plan — {room}</h2>
            <table className="mt-2 w-full border-collapse text-sm">
              <thead>
                <tr className="text-left text-xs text-slate-500">
                  <th className="p-2">Seat</th>
                  <th className="p-2">Candidate</th>
                  <th className="p-2">Class</th>
                  <th className="p-2">Arrangement</th>
                </tr>
              </thead>
              <tbody>
                {seats.map((s) => (
                  <tr key={s.seat_label} className="border-t border-slate-100">
                    <td className="p-2 font-mono text-xs">{s.seat_label}</td>
                    <td className="p-2">{displayName(s)}</td>
                    <td className="p-2 text-xs text-slate-400">{s.class_name}</td>
                    <td className="p-2 text-xs">
                      {s.arrangement
                        ? <span className="rounded bg-amber-50 px-1.5 py-0.5 text-amber-800">
                            {s.arrangement}
                          </span>
                        : <span className="text-slate-300">—</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ))}
      </div>
    </div>
  )
}
