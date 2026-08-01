import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { EduClaims } from '@/lib/supabase'
import { formatDate } from '@/lib/format'
import * as api from './api'

type Panel = 'notices' | 'maintenance' | 'library' | 'visitors' | 'health' | 'mail' | 'assets'

export function AdminScreen({ claims }: { claims: EduClaims }) {
  const [panel, setPanel] = useState<Panel>('notices')
  const tabs: [Panel, string][] = [
    ['notices', 'Notices'], ['maintenance', 'Maintenance'], ['library', 'Library'],
    ['visitors', 'Visitors'], ['health', 'Health'], ['mail', 'Mail register'],
    ['assets', 'Assets'],
  ]
  return (
    <div className="mx-auto w-full max-w-4xl pb-32">
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <h1 className="text-lg font-semibold">Administration</h1>
        <p className="text-sm text-slate-500">
          The registers and books the School Management Manual requires
        </p>
        <nav className="mt-3 flex gap-1 overflow-x-auto">
          {tabs.map(([id, label]) => (
            <button key={id} onClick={() => setPanel(id)}
              className={`h-9 shrink-0 rounded-lg px-3 text-sm font-medium ${
                panel === id ? 'bg-brand text-white' : 'text-slate-600 hover:bg-slate-100'}`}>
              {label}
            </button>
          ))}
        </nav>
      </header>

      {panel === 'notices' && <Notices claims={claims} />}
      {panel === 'maintenance' && <Maintenance claims={claims} />}
      {panel === 'library' && <Library />}
      {panel === 'visitors' && <Visitors claims={claims} />}
      {panel === 'health' && <Health />}
      {panel === 'mail' && <Mail claims={claims} />}
      {panel === 'assets' && <Assets />}
    </div>
  )
}

function Notices({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [pinned, setPinned] = useState(false)
  const list = useQuery({ queryKey: ['admin-notices'], queryFn: api.fetchNotices })
  const create = useMutation({
    mutationFn: () => api.publishNotice({
      school_id: claims.school_id!, title, body, created_by: claims.person_id!, pinned,
    }),
    onSuccess: () => {
      setTitle(''); setBody(''); setPinned(false)
      void qc.invalidateQueries({ queryKey: ['admin-notices'] })
    },
  })
  return (
    <div className="px-4 py-4">
      <div className="space-y-2 rounded-xl border border-slate-200 p-4">
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Notice title"
               className="h-10 w-full rounded-lg border border-slate-300 px-2.5 text-sm" />
        <textarea value={body} onChange={(e) => setBody(e.target.value)} rows={3}
                  placeholder="Body — appears on the digital board and in the guardian portal"
                  className="w-full rounded-lg border border-slate-300 p-2 text-sm" />
        <label className="flex items-center gap-2 text-xs">
          <input type="checkbox" checked={pinned} onChange={(e) => setPinned(e.target.checked)} />
          Pin to the top
        </label>
        <button disabled={title.trim() === '' || create.isPending} onClick={() => create.mutate()}
                className="h-10 w-full rounded-lg bg-brand text-sm font-semibold text-white disabled:opacity-40">
          Publish
        </button>
      </div>
      <ul className="mt-4 divide-y divide-slate-100">
        {(list.data ?? []).map((n: any) => (
          <li key={n.id} className="py-3">
            <div className="flex items-start justify-between gap-2">
              <p className="text-sm font-medium">{n.title}</p>
              {n.pinned && <span className="shrink-0 rounded bg-brand-light px-1.5 py-0.5 text-[10px] font-semibold uppercase text-brand">Pinned</span>}
            </div>
            <p className="mt-0.5 whitespace-pre-line text-sm text-slate-600">{n.body}</p>
            <p className="text-xs text-slate-400">{formatDate(n.publish_at.slice(0, 10))}</p>
          </li>
        ))}
      </ul>
    </div>
  )
}

function Maintenance({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [description, setDescription] = useState('')
  const [priority, setPriority] = useState('normal')
  const list = useQuery({ queryKey: ['maintenance'], queryFn: api.fetchMaintenance })
  const create = useMutation({
    mutationFn: () => api.createMaintenance({
      school_id: claims.school_id!, reported_by: claims.person_id!, description, priority,
    }),
    onSuccess: () => { setDescription(''); void qc.invalidateQueries({ queryKey: ['maintenance'] }) },
  })
  const complete = useMutation({
    mutationFn: (id: string) => api.completeMaintenance(id),
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['maintenance'] }) },
  })
  return (
    <div className="px-4 py-4">
      <div className="flex flex-wrap gap-2 rounded-xl border border-slate-200 p-4">
        <input value={description} onChange={(e) => setDescription(e.target.value)}
               placeholder="What needs fixing, and where"
               className="h-10 flex-1 rounded-lg border border-slate-300 px-2.5 text-sm" />
        <select value={priority} onChange={(e) => setPriority(e.target.value)}
                className="h-10 rounded-lg border border-slate-300 px-2 text-sm">
          <option value="low">Low</option><option value="normal">Normal</option>
          <option value="high">High</option><option value="urgent">Urgent</option>
        </select>
        <button disabled={description.trim() === ''} onClick={() => create.mutate()}
                className="h-10 rounded-lg bg-brand px-4 text-sm font-semibold text-white disabled:opacity-40">
          Report
        </button>
      </div>
      <p className="mt-1 text-xs text-slate-400">Anyone may report a problem — that is what a maintenance book is for.</p>
      <ul className="mt-4 divide-y divide-slate-100">
        {(list.data ?? []).map((m: any) => (
          <li key={m.id} className="flex items-start justify-between gap-3 py-3">
            <div>
              <p className="text-sm">{m.description}</p>
              <p className="text-xs text-slate-400">
                {formatDate(m.reported_on)}{m.room?.code && ` · ${m.room.code}`} · {m.priority}
              </p>
            </div>
            {m.status !== 'completed' ? (
              <button onClick={() => complete.mutate(m.id)}
                      className="h-9 shrink-0 rounded-lg border border-slate-200 px-3 text-xs font-medium
                                 hover:border-present hover:text-present">
                Mark done
              </button>
            ) : (
              <span className="shrink-0 text-xs text-present">Completed {formatDate(m.completed_on)}</span>
            )}
          </li>
        ))}
      </ul>
    </div>
  )
}

function Library() {
  const qc = useQueryClient()
  const list = useQuery({ queryKey: ['loans'], queryFn: api.fetchLibraryLoans })
  const ret = useMutation({
    mutationFn: (id: string) => api.returnLoan(id),
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['loans'] }) },
  })
  const today = new Date().toISOString().slice(0, 10)
  const out = (list.data ?? []).filter((l: any) => !l.returned_on)
  return (
    <div className="px-4 py-4">
      <p className="text-xs text-slate-500">
        Outstanding loans block a Leaving Certificate automatically — the pupil
        must return school property before it can be issued.
      </p>
      {out.length === 0 ? (
        <p className="py-10 text-center text-sm text-slate-500">Nothing on loan.</p>
      ) : (
        <ul className="mt-3 divide-y divide-slate-100">
          {out.map((l: any) => (
            <li key={l.id} className="flex items-center justify-between py-3">
              <div>
                <p className="text-sm font-medium">{l.library_item?.title}</p>
                <p className={`text-xs ${l.due_on < today ? 'text-absent' : 'text-slate-400'}`}>
                  Due {formatDate(l.due_on)}{l.due_on < today && ' — overdue'}
                </p>
              </div>
              <button onClick={() => ret.mutate(l.id)}
                      className="h-9 rounded-lg border border-slate-200 px-3 text-xs font-medium">
                Returned
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

function Visitors({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [name, setName] = useState('')
  const [organisation, setOrganisation] = useState('')
  const [purpose, setPurpose] = useState('')
  const [badge, setBadge] = useState('')
  const list = useQuery({ queryKey: ['visitors'], queryFn: api.fetchVisitors })
  const signIn = useMutation({
    mutationFn: () => api.signInVisitor({
      school_id: claims.school_id!, name, organisation, purpose, badge_no: badge,
    }),
    onSuccess: () => {
      setName(''); setOrganisation(''); setPurpose(''); setBadge('')
      void qc.invalidateQueries({ queryKey: ['visitors'] })
    },
  })
  const signOut = useMutation({
    mutationFn: (id: string) => api.signOutVisitor(id),
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['visitors'] }) },
  })
  return (
    <div className="px-4 py-4">
      <div className="grid gap-2 rounded-xl border border-slate-200 p-4 sm:grid-cols-2">
        <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Visitor name"
               className="h-10 rounded-lg border border-slate-300 px-2.5 text-sm" />
        <input value={organisation} onChange={(e) => setOrganisation(e.target.value)}
               placeholder="Organisation"
               className="h-10 rounded-lg border border-slate-300 px-2.5 text-sm" />
        <input value={purpose} onChange={(e) => setPurpose(e.target.value)} placeholder="Purpose"
               className="h-10 rounded-lg border border-slate-300 px-2.5 text-sm" />
        <input value={badge} onChange={(e) => setBadge(e.target.value)} placeholder="Badge no."
               className="h-10 rounded-lg border border-slate-300 px-2.5 text-sm" />
        <button disabled={name.trim() === ''} onClick={() => signIn.mutate()}
                className="h-10 rounded-lg bg-brand text-sm font-semibold text-white disabled:opacity-40 sm:col-span-2">
          Sign in
        </button>
      </div>
      <ul className="mt-4 divide-y divide-slate-100">
        {(list.data ?? []).map((v: any) => (
          <li key={v.id} className="flex items-center justify-between py-3">
            <div>
              <p className="text-sm font-medium">{v.name}</p>
              <p className="text-xs text-slate-400">
                {v.organisation} · {v.purpose}
                {v.badge_no && ` · badge ${v.badge_no}`}
              </p>
            </div>
            {v.signed_out_at ? (
              <span className="text-xs text-slate-400">Signed out</span>
            ) : (
              <button onClick={() => signOut.mutate(v.id)}
                      className="h-9 rounded-lg border border-slate-200 px-3 text-xs font-medium">
                Sign out
              </button>
            )}
          </li>
        ))}
      </ul>
    </div>
  )
}

function Health() {
  const list = useQuery({ queryKey: ['health'], queryFn: api.fetchHealth })
  const certs = useQuery({ queryKey: ['water'], queryFn: api.fetchWaterCerts })
  const today = new Date().toISOString().slice(0, 10)
  return (
    <div className="px-4 py-4">
      <h2 className="text-sm font-semibold">Water quality</h2>
      {(certs.data ?? []).length === 0 ? (
        <p className="mt-1 text-sm text-absent">
          No certificate on file. The Manual requires one displayed, with the
          date the tanks were last cleaned.
        </p>
      ) : (
        <ul className="mt-2 space-y-1">
          {(certs.data ?? []).map((c: any) => (
            <li key={c.id} className="text-sm">
              Issued {formatDate(c.issued_on)}
              {c.expires_on && (
                <span className={c.expires_on < today ? 'text-absent' : 'text-slate-400'}>
                  {' '}· expires {formatDate(c.expires_on)}
                  {c.expires_on < today && ' — EXPIRED'}
                </span>
              )}
              {c.tanks_cleaned_on && ` · tanks cleaned ${formatDate(c.tanks_cleaned_on)}`}
            </li>
          ))}
        </ul>
      )}

      <h2 className="mt-6 text-sm font-semibold">Health records</h2>
      {(list.data ?? []).length === 0 ? (
        <p className="mt-1 text-sm text-slate-500">Nothing recorded.</p>
      ) : (
        <ul className="mt-2 divide-y divide-slate-100">
          {(list.data ?? []).map((h: any) => (
            <li key={h.id} className="py-3">
              <p className="text-sm">{h.description}</p>
              <p className="text-xs text-slate-400">
                {h.kind} · {formatDate(h.occurred_at.slice(0, 10))}
                {h.sent_home && ' · sent home'}
                {h.guardian_notified_at && ' · guardian notified'}
              </p>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

function Mail({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [direction, setDirection] = useState('in')
  const [counterparty, setCounterparty] = useState('')
  const [subject, setSubject] = useState('')
  const [ufn, setUfn] = useState('')
  const list = useQuery({ queryKey: ['correspondence'], queryFn: api.fetchCorrespondence })
  const log = useMutation({
    mutationFn: () => api.logCorrespondence({
      school_id: claims.school_id!, direction, counterparty, subject,
      // The Manual's ABC scheme: the file's code is the first letter of the keyword.
      abc_code: subject.trim().charAt(0).toUpperCase(),
      unique_file_number: ufn ? Number(ufn) : null,
    }),
    onSuccess: () => {
      setCounterparty(''); setSubject(''); setUfn('')
      void qc.invalidateQueries({ queryKey: ['correspondence'] })
    },
  })
  return (
    <div className="px-4 py-4">
      <p className="text-xs text-slate-500">
        Incoming and outgoing mail, kept in the ABC filing scheme the Manual
        prescribes so the physical cabinet and this register stay reconcilable.
      </p>
      <div className="mt-3 grid gap-2 rounded-xl border border-slate-200 p-4 sm:grid-cols-2">
        <select value={direction} onChange={(e) => setDirection(e.target.value)}
                className="h-10 rounded-lg border border-slate-300 px-2 text-sm">
          <option value="in">Incoming</option><option value="out">Outgoing</option>
        </select>
        <input value={counterparty} onChange={(e) => setCounterparty(e.target.value)}
               placeholder="From / to"
               className="h-10 rounded-lg border border-slate-300 px-2.5 text-sm" />
        <input value={subject} onChange={(e) => setSubject(e.target.value)}
               placeholder="Subject (its first letter becomes the ABC code)"
               className="h-10 rounded-lg border border-slate-300 px-2.5 text-sm" />
        <input value={ufn} onChange={(e) => setUfn(e.target.value)} type="number"
               placeholder="Unique file number"
               className="h-10 rounded-lg border border-slate-300 px-2.5 text-sm" />
        <button disabled={subject.trim() === ''} onClick={() => log.mutate()}
                className="h-10 rounded-lg bg-brand text-sm font-semibold text-white disabled:opacity-40 sm:col-span-2">
          Record
        </button>
      </div>
      <ul className="mt-4 divide-y divide-slate-100">
        {(list.data ?? []).map((c: any) => (
          <li key={c.id} className="flex items-start justify-between gap-3 py-3">
            <div>
              <p className="text-sm font-medium">{c.subject}</p>
              <p className="text-xs text-slate-400">
                {c.direction === 'in' ? 'From' : 'To'} {c.counterparty} · {formatDate(c.dated_on)}
              </p>
            </div>
            <span className="shrink-0 font-mono text-xs text-slate-400">
              {c.abc_code}{c.unique_file_number ? `/${c.unique_file_number}` : ''}
            </span>
          </li>
        ))}
      </ul>
    </div>
  )
}

function Assets() {
  const list = useQuery({ queryKey: ['assets'], queryFn: api.fetchAssets })
  return (
    <div className="px-4 py-4">
      {(list.data ?? []).length === 0 ? (
        <p className="py-10 text-center text-sm text-slate-500">
          No assets recorded. Import the school's existing register to begin.
        </p>
      ) : (
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-xs text-slate-500">
              <th className="p-2">Tag</th><th className="p-2">Item</th>
              <th className="p-2">Room</th><th className="p-2">Condition</th>
            </tr>
          </thead>
          <tbody>
            {(list.data ?? []).map((a: any) => (
              <tr key={a.id} className="border-t border-slate-100">
                <td className="p-2 font-mono text-xs">{a.tag}</td>
                <td className="p-2">{a.name}</td>
                <td className="p-2 text-xs text-slate-400">{a.room?.code ?? '—'}</td>
                <td className="p-2 text-xs">{a.condition}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}
