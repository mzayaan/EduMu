import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import * as api from './api'
import type { UnplacedLesson } from './api'

/**
 * Direct-manipulation timetable editor.
 *
 * The Deputy Rector's judgement always wins. This never auto-corrects a
 * placement: it refuses an illegal move, says why in their language, and lets
 * them decide what to do about it.
 *
 * Legality is settled by the database — two unique indexes for room and staff
 * clashes, plus a trigger for the pupil clash that no index can express. This
 * component predicts the answer only to grey out obviously impossible targets;
 * the write is what actually decides, so a wrong prediction is a cosmetic bug
 * rather than a corrupt timetable.
 */
export function EditableGrid({ versionId, status }: {
  versionId: string
  status: 'draft' | 'published' | 'superseded'
}) {
  const qc = useQueryClient()
  const [dragged, setDragged] = useState<
    | { kind: 'slot'; id: string; setId: string; staffId: string | null }
    | { kind: 'unplaced'; setId: string }
    | null
  >(null)
  const [over, setOver] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [flash, setFlash] = useState<string | null>(null)

  const periods = useQuery({
    queryKey: ['tt-periods', versionId],
    queryFn: () => api.fetchPeriods(versionId),
  })
  const slots = useQuery({
    queryKey: ['tt-slots', versionId],
    queryFn: () => api.fetchSlots(versionId),
  })
  const unplaced = useQuery({
    queryKey: ['tt-unplaced', versionId],
    queryFn: () => api.fetchUnplaced(versionId),
  })

  const editable = status === 'draft'
  const teaching = useMemo(
    () => (periods.data ?? []).filter((p) => p.is_teaching),
    [periods.data],
  )
  const days = useMemo(() => {
    const max = Math.max(5, ...(slots.data ?? []).map((s: any) => s.cycle_day))
    return Array.from({ length: max }, (_, i) => i + 1)
  }, [slots.data])

  function refresh() {
    void qc.invalidateQueries({ queryKey: ['tt-slots', versionId] })
    void qc.invalidateQueries({ queryKey: ['tt-unplaced', versionId] })
  }
  function announce(msg: string) {
    setError(null)
    setFlash(msg)
    window.setTimeout(() => setFlash(null), 2500)
  }

  const move = useMutation({
    mutationFn: (v: { slot: string; day: number; period: string }) =>
      api.moveSlot(v.slot, v.day, v.period),
    onSuccess: () => { announce('Lesson moved'); refresh() },
    onError: (e: any) => setError(readable(e.message)),
  })
  const place = useMutation({
    mutationFn: (v: { set: string; day: number; period: string }) =>
      api.placeLesson(versionId, v.set, v.day, v.period),
    onSuccess: () => { announce('Lesson placed'); refresh() },
    onError: (e: any) => setError(readable(e.message)),
  })
  const remove = useMutation({
    mutationFn: (slot: string) => api.removeLesson(slot),
    onSuccess: () => { announce('Returned to the unplaced tray'); refresh() },
    onError: (e: any) => setError(readable(e.message)),
  })

  /**
   * Conservative prediction, used only for shading. It checks the one thing
   * this grid can know for certain — the same teacher already in that slot.
   * Pupil clashes need enrolment data the grid does not hold, so they are left
   * to the server rather than guessed at and got wrong.
   */
  function sameTeacherBusy(day: number, periodId: string): boolean {
    if (!dragged) return false
    const staffId = dragged.kind === 'slot' ? dragged.staffId : null
    if (!staffId) return false
    return (slots.data ?? []).some(
      (s: any) =>
        s.cycle_day === day &&
        s.period_id === periodId &&
        s.staff_id === staffId &&
        s.id !== (dragged.kind === 'slot' ? dragged.id : null),
    )
  }

  function drop(day: number, periodId: string) {
    setOver(null)
    if (!dragged || !editable) return
    if (dragged.kind === 'slot') {
      move.mutate({ slot: dragged.id, day, period: periodId })
    } else {
      place.mutate({ set: dragged.setId, day, period: periodId })
    }
    setDragged(null)
  }

  const busy = move.isPending || place.isPending || remove.isPending

  return (
    <div className="px-4 py-3">
      {!editable && (
        <p className="mb-3 rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-800">
          This version is <b>{status}</b>. Timetables become immutable once
          published so that historical lesson attendance still resolves against
          the version in force on its own date. Create a new version to change it.
        </p>
      )}
      {error && (
        <p className="mb-3 rounded-lg bg-red-50 px-3 py-2 text-sm text-absent">{error}</p>
      )}
      {flash && !error && <p className="mb-3 text-xs text-present">{flash}</p>}

      {editable && (
        <p className="mb-2 text-xs text-slate-400">
          Drag a lesson to move it, or drag from the tray to place one. Clashes
          are refused with the reason — nothing is silently rearranged.
        </p>
      )}

      <div className="flex gap-4">
        <div className="min-w-0 flex-1 overflow-x-auto">
          <table className="w-full border-collapse text-[11px]">
            <thead>
              <tr>
                <th className="p-1 text-left font-semibold text-slate-500">Day</th>
                {teaching.map((p) => (
                  <th key={p.id} className="p-1 text-center font-semibold">
                    <div>{p.name}</div>
                    <div className="font-normal text-slate-400">
                      {p.starts_at.slice(0, 5)}
                    </div>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {days.map((d) => (
                <tr key={d} className="border-t border-slate-100">
                  <td className="p-1 font-semibold text-slate-500">Day {d}</td>
                  {teaching.map((p) => {
                    const key = `${d}:${p.id}`
                    const here = (slots.data ?? []).filter(
                      (s: any) => s.cycle_day === d && s.period_id === p.id,
                    )
                    const clash = sameTeacherBusy(d, p.id)
                    const isOver = over === key
                    return (
                      <td
                        key={p.id}
                        onDragOver={(e) => {
                          if (!editable || !dragged) return
                          e.preventDefault()
                          setOver(key)
                        }}
                        onDragLeave={() => setOver((o) => (o === key ? null : o))}
                        onDrop={() => drop(d, p.id)}
                        className={`min-w-[92px] border p-0.5 align-top transition-colors
                          ${isOver && clash ? 'border-absent bg-red-50' : ''}
                          ${isOver && !clash ? 'border-brand bg-brand-light' : ''}
                          ${!isOver && dragged && !clash ? 'border-transparent bg-slate-50' : ''}
                          ${!isOver && (!dragged || clash) ? 'border-transparent' : ''}`}
                      >
                        {here.map((s: any) => (
                          <div
                            key={s.id}
                            draggable={editable && !busy}
                            onDragStart={() =>
                              setDragged({
                                kind: 'slot', id: s.id,
                                setId: s.subject_set_id, staffId: s.staff_id ?? null,
                              })}
                            onDragEnd={() => { setDragged(null); setOver(null) }}
                            className={`group mb-0.5 rounded border border-slate-200 bg-white px-1 py-0.5
                              ${editable ? 'cursor-grab active:cursor-grabbing' : ''}`}
                          >
                            <div className="truncate font-medium">{s.set_name}</div>
                            <div className="flex items-center justify-between gap-1">
                              <span className="truncate text-slate-400">{s.room_code}</span>
                              {editable && (
                                <button
                                  onClick={() => remove.mutate(s.id)}
                                  title="Return to the unplaced tray"
                                  aria-label={`Remove ${s.set_name}`}
                                  className="shrink-0 px-0.5 text-slate-300 opacity-0
                                             transition-opacity hover:text-absent
                                             group-hover:opacity-100"
                                >
                                  ×
                                </button>
                              )}
                            </div>
                          </div>
                        ))}
                      </td>
                    )
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <aside className="w-52 shrink-0">
          <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            Unplaced
          </h3>
          {(unplaced.data ?? []).length === 0 ? (
            <p className="mt-2 text-xs text-present">Every lesson is placed.</p>
          ) : (
            <>
              <p className="mt-1 text-[10px] text-slate-400">
                What the solver could not fit. Drag onto the grid.
              </p>
              <ul className="mt-2 space-y-1">
                {(unplaced.data ?? []).map((u: UnplacedLesson) => (
                  <li
                    key={u.subject_set_id}
                    draggable={editable && !busy}
                    onDragStart={() =>
                      setDragged({ kind: 'unplaced', setId: u.subject_set_id })}
                    onDragEnd={() => { setDragged(null); setOver(null) }}
                    className={`rounded border border-amber-300 bg-amber-50 px-2 py-1 text-[11px]
                      ${editable ? 'cursor-grab active:cursor-grabbing' : ''}`}
                  >
                    <div className="font-medium">{u.set_name}</div>
                    <div className="text-slate-500">
                      {u.outstanding} of {u.required} outstanding
                    </div>
                    {u.required_room_type && (
                      <div className="text-slate-400">
                        needs a {u.required_room_type.replace('_', ' ')}
                      </div>
                    )}
                  </li>
                ))}
              </ul>
            </>
          )}
        </aside>
      </div>
    </div>
  )
}

/**
 * Postgres exception text is accurate but not addressed to a Deputy Rector.
 * The message has to say what to do next, not just what went wrong.
 */
function readable(msg: string): string {
  if (msg.includes('Pupil clash')) {
    const detail = msg.replace(/^.*Pupil clash: /, '')
    return `Pupil clash — ${detail}. Those pupils would be in two lessons at once. ` +
      'Move the other lesson first, or choose a different period.'
  }
  if (msg.includes('tt_no_room_clash')) {
    return 'That room is already in use in this period. Free it, or let the lesson take another room.'
  }
  if (msg.includes('tt_no_staff_clash')) {
    return 'That teacher is already teaching in this period.'
  }
  if (msg.includes('immutable') || msg.includes('published')) {
    return 'This timetable is published and cannot be changed. Create a new version to make edits.'
  }
  if (msg.includes('Not authorised')) {
    return 'You do not have permission to change the timetable.'
  }
  return msg
}
