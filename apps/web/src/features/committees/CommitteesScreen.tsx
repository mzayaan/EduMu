import { useEffect, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { EduClaims } from '@/lib/supabase'
import { formatDate, todayInMauritius } from '@/lib/format'
import * as api from './api'
import type { ActionItem, Committee, Meeting } from './api'

type Panel = 'committees' | 'meetings' | 'actions'

/**
 * Committees, meetings and the actions that come out of them.
 *
 * The School Management Manual makes committees structural rather than ad hoc,
 * and expects several to meet at least twice a term. The part that decides
 * whether any of it matters is the action list: minutes without follow-up are
 * decoration, so every action carries an owner and a date and appears in that
 * person's own list.
 */
export function CommitteesScreen({ claims }: { claims: EduClaims }) {
  const [panel, setPanel] = useState<Panel>('committees')
  return (
    <div className="mx-auto w-full max-w-4xl pb-32">
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <h1 className="text-lg font-semibold">Committees</h1>
        <p className="text-sm text-slate-500">
          Membership, meetings, minutes and the actions arising
        </p>
        <nav className="mt-3 flex gap-1">
          {(['committees', 'meetings', 'actions'] as Panel[]).map((p) => (
            <button key={p} onClick={() => setPanel(p)}
              className={`h-9 rounded-lg px-3 text-sm font-medium capitalize ${
                panel === p ? 'bg-brand text-white' : 'text-slate-600 hover:bg-slate-100'}`}>
              {p === 'actions' ? 'My actions' : p}
            </button>
          ))}
        </nav>
      </header>

      {panel === 'committees' && <Committees claims={claims} />}
      {panel === 'meetings' && <Meetings claims={claims} />}
      {panel === 'actions' && <Actions claims={claims} />}
    </div>
  )
}

function Committees({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [openId, setOpenId] = useState<string | null>(null)
  const [q, setQ] = useState('')
  const [role, setRole] = useState('')
  const [error, setError] = useState<string | null>(null)

  const committees = useQuery({ queryKey: ['committees'], queryFn: api.fetchCommittees })
  const members = useQuery({
    queryKey: ['committee-members', openId],
    queryFn: () => api.fetchMembers(openId!),
    enabled: Boolean(openId),
  })
  const people = useQuery({
    queryKey: ['people-search', q],
    queryFn: () => api.searchPeople(q),
    enabled: Boolean(openId),
  })

  const add = useMutation({
    mutationFn: (personId: string) => api.addMember(openId!, personId, role),
    onSuccess: () => {
      setError(null); setQ(''); setRole('')
      void qc.invalidateQueries({ queryKey: ['committee-members'] })
    },
    onError: (e: any) => setError(e.message),
  })
  const drop = useMutation({
    mutationFn: (personId: string) => api.removeMember(openId!, personId),
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['committee-members'] }) },
  })

  return (
    <div className="px-4 py-4">
      {error && <p className="mb-3 text-sm text-absent">{error}</p>}
      <ul className="divide-y divide-slate-100">
        {(committees.data ?? []).map((c: Committee) => (
          <li key={c.id} className="py-3">
            <button
              onClick={() => setOpenId(openId === c.id ? null : c.id)}
              className="flex w-full items-start justify-between gap-3 text-left"
            >
              <div>
                <p className="text-sm font-medium">{c.name}</p>
                <p className="text-xs text-slate-400">
                  {c.min_meetings_per_term
                    ? `at least ${c.min_meetings_per_term} meeting(s) per term`
                    : 'no minimum set'}
                </p>
              </div>
              <span className="shrink-0 text-xs text-slate-400">
                {openId === c.id ? 'Hide' : 'Members'}
              </span>
            </button>

            {openId === c.id && (
              <div className="mt-3 rounded-lg border border-slate-200 p-3">
                {(members.data ?? []).length === 0 ? (
                  <p className="text-xs text-slate-500">No members yet.</p>
                ) : (
                  <ul className="divide-y divide-slate-100">
                    {(members.data ?? []).map((m) => (
                      <li key={m.person_id} className="flex items-center justify-between py-1.5">
                        <span className="text-sm">
                          {m.last_name}, {m.first_name}
                          {m.role_in_committee && (
                            <span className="ml-2 text-xs text-slate-400">
                              {m.role_in_committee}
                            </span>
                          )}
                          {m.person_type === 'guardian' && (
                            <span className="ml-2 rounded bg-brand-light px-1.5 py-0.5
                                             text-[10px] font-semibold uppercase text-brand">
                              Parent
                            </span>
                          )}
                        </span>
                        <button onClick={() => drop.mutate(m.person_id)}
                                className="text-xs text-slate-300 hover:text-absent">
                          Remove
                        </button>
                      </li>
                    ))}
                  </ul>
                )}

                <div className="mt-3 border-t border-slate-100 pt-3">
                  <div className="flex gap-2">
                    <input value={q} onChange={(e) => setQ(e.target.value)}
                           placeholder="Search staff or parents"
                           className="h-9 flex-1 rounded-lg border border-slate-300 px-2.5 text-xs" />
                    <input value={role} onChange={(e) => setRole(e.target.value)}
                           placeholder="Role (optional)"
                           className="h-9 w-32 rounded-lg border border-slate-300 px-2.5 text-xs" />
                  </div>
                  {q.trim() && (
                    <ul className="mt-2 max-h-40 overflow-y-auto rounded-lg border border-slate-200">
                      {(people.data ?? []).map((p: any) => (
                        <li key={p.id}>
                          <button onClick={() => add.mutate(p.id)}
                            className="flex w-full items-center justify-between px-2.5 py-1.5
                                       text-left text-xs hover:bg-slate-50">
                            <span>{p.last_name}, {p.first_name}</span>
                            <span className="text-slate-400">{p.person_type}</span>
                          </button>
                        </li>
                      ))}
                    </ul>
                  )}
                  <p className="mt-1 text-[10px] text-slate-400">
                    The Pastoral Care Committee is expected to include a parent —
                    not necessarily a PTA Executive member.
                  </p>
                </div>
              </div>
            )}
          </li>
        ))}
      </ul>
    </div>
  )
}

function Meetings({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [committeeId, setCommitteeId] = useState<string>('')
  const [openId, setOpenId] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)
  const [title, setTitle] = useState('')
  const [heldOn, setHeldOn] = useState(todayInMauritius())
  const [venue, setVenue] = useState('')
  const [agenda, setAgenda] = useState('')
  const [error, setError] = useState<string | null>(null)

  const committees = useQuery({ queryKey: ['committees'], queryFn: api.fetchCommittees })
  const meetings = useQuery({
    queryKey: ['meetings', committeeId],
    queryFn: () => api.fetchMeetings(committeeId || undefined),
  })

  const create = useMutation({
    mutationFn: () => api.createMeeting({
      school_id: claims.school_id!,
      kind: committeeId ? 'committee' : 'staff',
      committee_id: committeeId || null,
      title, held_on: new Date(heldOn + 'T09:00:00').toISOString(),
      venue, agenda, chaired_by: claims.person_id!,
    }),
    onSuccess: () => {
      setCreating(false); setTitle(''); setVenue(''); setAgenda(''); setError(null)
      void qc.invalidateQueries({ queryKey: ['meetings'] })
    },
    onError: (e: any) => setError(e.message),
  })

  return (
    <div className="px-4 py-4">
      <div className="flex flex-wrap items-center gap-2">
        <select value={committeeId} onChange={(e) => setCommitteeId(e.target.value)}
                className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium">
          <option value="">All meetings</option>
          {(committees.data ?? []).map((c) => (
            <option key={c.id} value={c.id}>{c.name}</option>
          ))}
        </select>
        <button onClick={() => setCreating((v) => !v)}
                className="h-10 rounded-lg bg-brand px-4 text-sm font-semibold text-white">
          {creating ? 'Cancel' : 'Record a meeting'}
        </button>
      </div>

      {error && <p className="mt-3 text-sm text-absent">{error}</p>}

      {creating && (
        <div className="mt-3 space-y-2 rounded-xl border border-slate-200 p-4">
          <input value={title} onChange={(e) => setTitle(e.target.value)}
                 placeholder="Title, e.g. Pastoral Care Committee — Term 2"
                 className="h-10 w-full rounded-lg border border-slate-300 px-2.5 text-sm" />
          <div className="flex gap-2">
            <input type="date" value={heldOn} onChange={(e) => setHeldOn(e.target.value)}
                   className="h-10 rounded-lg border border-slate-300 px-2 text-sm" />
            <input value={venue} onChange={(e) => setVenue(e.target.value)}
                   placeholder="Venue"
                   className="h-10 flex-1 rounded-lg border border-slate-300 px-2.5 text-sm" />
          </div>
          <textarea value={agenda} onChange={(e) => setAgenda(e.target.value)} rows={3}
                    placeholder="Agenda"
                    className="w-full rounded-lg border border-slate-300 p-2 text-sm" />
          <button disabled={!title.trim() || create.isPending} onClick={() => create.mutate()}
                  className="h-10 w-full rounded-lg bg-brand text-sm font-semibold text-white disabled:opacity-40">
            Record
          </button>
        </div>
      )}

      <ul className="mt-4 divide-y divide-slate-100">
        {(meetings.data ?? []).map((m: Meeting) => (
          <li key={m.id} className="py-3">
            <button onClick={() => setOpenId(openId === m.id ? null : m.id)}
                    className="flex w-full items-start justify-between gap-3 text-left">
              <div>
                <p className="text-sm font-medium">{m.title}</p>
                <p className="text-xs text-slate-400">
                  {formatDate(m.held_on.slice(0, 10))}
                  {m.venue && ` · ${m.venue}`}
                  {!m.minutes && ' · no minutes yet'}
                </p>
              </div>
              <span className="shrink-0 text-xs text-slate-400">
                {openId === m.id ? 'Hide' : 'Open'}
              </span>
            </button>
            {openId === m.id && <MeetingDetail meeting={m} claims={claims} />}
          </li>
        ))}
      </ul>
    </div>
  )
}

function MeetingDetail({ meeting, claims }: { meeting: Meeting; claims: EduClaims }) {
  const qc = useQueryClient()
  const [minutes, setMinutes] = useState(meeting.minutes ?? '')
  const [desc, setDesc] = useState('')
  const [due, setDue] = useState('')

  const actions = useQuery({
    queryKey: ['actions', meeting.id],
    queryFn: () => api.fetchActions({ meetingId: meeting.id }),
  })

  const save = useMutation({
    mutationFn: () => api.saveMinutes(meeting.id, minutes),
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['meetings'] }) },
  })
  const add = useMutation({
    mutationFn: () => api.addAction({
      school_id: claims.school_id!, meeting_id: meeting.id,
      description: desc, owner_person_id: claims.person_id!,
      due_on: due || null,
    }),
    onSuccess: () => {
      setDesc(''); setDue('')
      void qc.invalidateQueries({ queryKey: ['actions'] })
    },
  })

  return (
    <div className="mt-3 space-y-3 rounded-lg border border-slate-200 p-3">
      {meeting.agenda && (
        <div>
          <p className="text-[10px] font-bold uppercase tracking-widest text-slate-500">Agenda</p>
          <p className="mt-0.5 whitespace-pre-line text-sm">{meeting.agenda}</p>
        </div>
      )}

      <div>
        <p className="text-[10px] font-bold uppercase tracking-widest text-slate-500">Minutes</p>
        <textarea value={minutes} onChange={(e) => setMinutes(e.target.value)} rows={4}
                  onBlur={() => minutes !== (meeting.minutes ?? '') && save.mutate()}
                  placeholder="What was decided"
                  className="mt-1 w-full rounded-lg border border-slate-300 p-2 text-sm" />
        <p className="text-[10px] text-slate-400">Saved when you click away.</p>
      </div>

      <div>
        <p className="text-[10px] font-bold uppercase tracking-widest text-slate-500">
          Actions arising
        </p>
        {(actions.data ?? []).length === 0 && (
          <p className="mt-1 text-xs text-slate-500">
            None recorded. Minutes without follow-up tend to stay decorative.
          </p>
        )}
        <ul className="mt-1 divide-y divide-slate-100">
          {(actions.data ?? []).map((a: ActionItem) => (
            <li key={a.id} className="flex items-center justify-between py-1.5 text-sm">
              <span className={a.status === 'done' ? 'text-slate-400 line-through' : ''}>
                {a.description}
                {a.due_on && (
                  <span className="ml-2 text-xs text-slate-400">by {formatDate(a.due_on)}</span>
                )}
              </span>
              {a.status === 'open' && (
                <button
                  onClick={() => api.completeAction(a.id).then(() =>
                    qc.invalidateQueries({ queryKey: ['actions'] }))}
                  className="shrink-0 text-xs text-slate-400 hover:text-present">
                  Done
                </button>
              )}
            </li>
          ))}
        </ul>
        <div className="mt-2 flex gap-2">
          <input value={desc} onChange={(e) => setDesc(e.target.value)}
                 placeholder="New action"
                 className="h-9 flex-1 rounded-lg border border-slate-300 px-2.5 text-xs" />
          <input type="date" value={due} onChange={(e) => setDue(e.target.value)}
                 className="h-9 rounded-lg border border-slate-300 px-2 text-xs" />
          <button disabled={!desc.trim()} onClick={() => add.mutate()}
                  className="h-9 rounded-lg bg-brand px-3 text-xs font-semibold text-white disabled:opacity-40">
            Add
          </button>
        </div>
      </div>
    </div>
  )
}

function Actions({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const actions = useQuery({
    queryKey: ['my-actions', claims.person_id],
    queryFn: () => api.fetchActions({ mine: claims.person_id! }),
  })
  const today = todayInMauritius()

  const open = (actions.data ?? []).filter((a) => a.status === 'open')
  const done = (actions.data ?? []).filter((a) => a.status !== 'open')

  return (
    <div className="px-4 py-4">
      {open.length === 0 ? (
        <p className="py-10 text-center text-sm text-slate-500">Nothing outstanding.</p>
      ) : (
        <ul className="divide-y divide-slate-100">
          {open.map((a: ActionItem) => {
            const overdue = a.due_on !== null && a.due_on < today
            return (
              <li key={a.id} className="flex items-start justify-between gap-3 py-3">
                <div>
                  <p className="text-sm">{a.description}</p>
                  <p className={`text-xs ${overdue ? 'text-absent' : 'text-slate-400'}`}>
                    {a.due_on ? `Due ${formatDate(a.due_on)}` : 'No date set'}
                    {overdue && ' — overdue'}
                  </p>
                </div>
                <button
                  onClick={() => api.completeAction(a.id).then(() =>
                    qc.invalidateQueries({ queryKey: ['my-actions'] }))}
                  className="h-9 shrink-0 rounded-lg border border-slate-200 px-3 text-xs
                             font-medium hover:border-present hover:text-present">
                  Mark done
                </button>
              </li>
            )
          })}
        </ul>
      )}

      {done.length > 0 && (
        <>
          <h2 className="mt-6 text-xs font-semibold uppercase tracking-wide text-slate-500">
            Completed
          </h2>
          <ul className="mt-1 divide-y divide-slate-100">
            {done.map((a: ActionItem) => (
              <li key={a.id} className="py-2 text-sm text-slate-400 line-through">
                {a.description}
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  )
}
