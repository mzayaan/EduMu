import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { EduClaims } from '@/lib/supabase'
import { displayName, formatDate } from '@/lib/format'
import * as api from './api'
import { INCIDENT_CATEGORIES, MERIT_KINDS, type Severity, type Stage } from './api'

type Panel = 'incidents' | 'merits' | 'cases' | 'log'

const STAGES: { value: Stage; label: string }[] = [
  { value: 'form_teacher', label: 'Form Teacher counselling' },
  { value: 'parent_contact', label: 'Parent contacted' },
  { value: 'special_report', label: 'Special Report' },
  { value: 'pastoral', label: 'Pastoral Care Committee' },
  { value: 'disciplinary_committee', label: 'Disciplinary Committee' },
  { value: 'closed', label: 'Closed' },
]

export function DisciplineScreen({ claims }: { claims: EduClaims }) {
  const [panel, setPanel] = useState<Panel>('incidents')
  return (
    <div className="mx-auto w-full max-w-3xl pb-32">
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <h1 className="text-lg font-semibold">Conduct</h1>
        <p className="text-sm text-slate-500">
          Recognition as well as sanction — both belong on a pupil's record
        </p>
        <nav className="mt-3 flex gap-1 overflow-x-auto">
          {(['incidents', 'merits', 'cases', 'log'] as Panel[]).map((p) => (
            <button key={p} onClick={() => setPanel(p)}
              className={`h-9 shrink-0 rounded-lg px-3 text-sm font-medium capitalize ${
                panel === p ? 'bg-brand text-white' : 'text-slate-600 hover:bg-slate-100'}`}>
              {p === 'log' ? 'Occurrence log' : p}
            </button>
          ))}
        </nav>
      </header>

      {panel === 'incidents' && <Incidents claims={claims} />}
      {panel === 'merits' && <Merits claims={claims} />}
      {panel === 'cases' && <Cases />}
      {panel === 'log' && <OccurrenceLog claims={claims} />}
    </div>
  )
}

/** Pupil picker shared by the incident and merit forms. */
function PupilPicker({ selected, onToggle, multi = false }: {
  selected: string[]; onToggle: (id: string) => void; multi?: boolean
}) {
  const [q, setQ] = useState('')
  const pupils = useQuery({ queryKey: ['pupil-search', q], queryFn: () => api.searchPupils(q) })
  return (
    <div>
      <input value={q} onChange={(e) => setQ(e.target.value)}
             placeholder="Search pupil by name or admission number"
             className="h-10 w-full rounded-lg border border-slate-300 px-3 text-sm" />
      <ul className="mt-2 max-h-48 overflow-y-auto rounded-lg border border-slate-200">
        {(pupils.data ?? []).map((p: any) => {
          const on = selected.includes(p.student_id)
          return (
            <li key={p.student_id}>
              <button
                onClick={() => onToggle(p.student_id)}
                className={`flex w-full items-center justify-between px-3 py-2 text-left text-sm
                  ${on ? 'bg-brand-light' : 'hover:bg-slate-50'}`}
              >
                <span>{displayName(p)}</span>
                <span className="text-xs text-slate-400">
                  {p.class_name} · {p.admission_number}
                </span>
              </button>
            </li>
          )
        })}
      </ul>
      {!multi && selected.length > 1 && (
        <p className="mt-1 text-xs text-absent">Select one pupil only.</p>
      )}
    </div>
  )
}

function Incidents({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [open, setOpen] = useState(false)
  const [pupils, setPupils] = useState<string[]>([])
  const [category, setCategory] = useState<string>(INCIDENT_CATEGORIES[0])
  const [severity, setSeverity] = useState<Severity>('minor')
  const [location, setLocation] = useState('')
  const [description, setDescription] = useState('')

  const list = useQuery({ queryKey: ['incidents'], queryFn: api.fetchIncidents })

  const create = useMutation({
    mutationFn: () => api.createIncident({
      school_id: claims.school_id!,
      academic_year_id: claims.year_id!,
      reported_by: claims.person_id!,
      category, severity, location, description,
      student_ids: pupils,
    }),
    onSuccess: () => {
      setOpen(false); setPupils([]); setDescription(''); setLocation('')
      void qc.invalidateQueries({ queryKey: ['incidents'] })
    },
  })

  return (
    <div className="px-4 py-4">
      <button onClick={() => setOpen((v) => !v)}
        className="h-11 w-full rounded-lg bg-brand text-sm font-semibold text-white">
        {open ? 'Cancel' : 'Record an incident'}
      </button>

      {open && (
        <div className="mt-3 space-y-3 rounded-xl border border-slate-200 p-4">
          <PupilPicker selected={pupils} multi
            onToggle={(id) => setPupils((s) =>
              s.includes(id) ? s.filter((x) => x !== id) : [...s, id])} />

          <div className="flex gap-2">
            <label className="flex-1 text-xs font-medium">
              Category
              <select value={category} onChange={(e) => setCategory(e.target.value)}
                      className="mt-1 h-10 w-full rounded-lg border border-slate-300 px-2 text-sm">
                {INCIDENT_CATEGORIES.map((c) => <option key={c}>{c}</option>)}
              </select>
            </label>
            <label className="flex-1 text-xs font-medium">
              Severity
              <select value={severity} onChange={(e) => setSeverity(e.target.value as Severity)}
                      className="mt-1 h-10 w-full rounded-lg border border-slate-300 px-2 text-sm">
                <option value="minor">Minor</option>
                <option value="moderate">Moderate</option>
                <option value="serious">Serious</option>
                <option value="grave">Grave</option>
              </select>
            </label>
          </div>

          <label className="block text-xs font-medium">
            Location
            <input value={location} onChange={(e) => setLocation(e.target.value)}
                   placeholder="e.g. corridor, Block B"
                   className="mt-1 h-10 w-full rounded-lg border border-slate-300 px-2 text-sm" />
          </label>

          <label className="block text-xs font-medium">
            What happened
            <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={3}
                      className="mt-1 w-full rounded-lg border border-slate-300 p-2 text-sm" />
          </label>

          <button
            disabled={pupils.length === 0 || description.trim() === '' || create.isPending}
            onClick={() => create.mutate()}
            className="h-10 w-full rounded-lg bg-brand text-sm font-semibold text-white disabled:opacity-40"
          >
            {create.isPending ? 'Saving…' : 'Record'}
          </button>
        </div>
      )}

      <ul className="mt-4 divide-y divide-slate-100">
        {(list.data ?? []).map((i: any) => (
          <li key={i.id} className="py-3">
            <div className="flex items-start justify-between gap-2">
              <div>
                <p className="text-sm font-medium">{i.category}</p>
                <p className="mt-0.5 text-sm text-slate-600">{i.description}</p>
                <p className="mt-0.5 text-xs text-slate-400">
                  {formatDate(i.occurred_at.slice(0, 10))}
                  {i.location && ` · ${i.location}`}
                </p>
              </div>
              <span className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase ${
                i.severity === 'grave' || i.severity === 'serious'
                  ? 'bg-red-50 text-absent' : 'bg-amber-50 text-amber-800'}`}>
                {i.severity}
              </span>
            </div>
          </li>
        ))}
      </ul>
    </div>
  )
}

function Merits({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [pupil, setPupil] = useState<string[]>([])
  const [kind, setKind] = useState<string>(MERIT_KINDS[0].value)
  const [reason, setReason] = useState('')
  const list = useQuery({ queryKey: ['merits'], queryFn: api.fetchMerits })

  const award = useMutation({
    mutationFn: () => api.awardMerit({
      school_id: claims.school_id!, student_id: pupil[0]!, kind, reason,
    }),
    onSuccess: () => {
      setPupil([]); setReason('')
      void qc.invalidateQueries({ queryKey: ['merits'] })
    },
  })

  return (
    <div className="px-4 py-4">
      <div className="space-y-3 rounded-xl border border-slate-200 p-4">
        <p className="text-sm font-medium">Recognise a pupil</p>
        <PupilPicker selected={pupil} onToggle={(id) => setPupil([id])} />
        <label className="block text-xs font-medium">
          For
          <select value={kind} onChange={(e) => setKind(e.target.value)}
                  className="mt-1 h-10 w-full rounded-lg border border-slate-300 px-2 text-sm">
            {MERIT_KINDS.map((k) => <option key={k.value} value={k.value}>{k.label}</option>)}
          </select>
        </label>
        <label className="block text-xs font-medium">
          Reason
          <input value={reason} onChange={(e) => setReason(e.target.value)}
                 className="mt-1 h-10 w-full rounded-lg border border-slate-300 px-2 text-sm" />
        </label>
        <button
          disabled={pupil.length !== 1 || reason.trim() === '' || award.isPending}
          onClick={() => award.mutate()}
          className="h-10 w-full rounded-lg bg-present text-sm font-semibold text-white disabled:opacity-40"
        >
          Award
        </button>
      </div>

      <ul className="mt-4 divide-y divide-slate-100">
        {(list.data ?? []).map((m: any) => (
          <li key={m.id} className="py-3">
            <p className="text-sm font-medium">
              {MERIT_KINDS.find((k) => k.value === m.kind)?.label ?? m.kind}
            </p>
            <p className="text-sm text-slate-600">{m.reason}</p>
            <p className="text-xs text-slate-400">{formatDate(m.awarded_on)}</p>
          </li>
        ))}
      </ul>
    </div>
  )
}

function Cases() {
  const qc = useQueryClient()
  const list = useQuery({ queryKey: ['cases'], queryFn: api.fetchCases })
  const escalate = useMutation({
    mutationFn: (v: { id: string; stage: Stage }) => api.escalateCase(v.id, v.stage),
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['cases'] }) },
  })

  return (
    <div className="px-4 py-4">
      {(list.data ?? []).length === 0 && (
        <p className="text-sm text-slate-500">No open cases.</p>
      )}
      <ul className="divide-y divide-slate-100">
        {(list.data ?? []).map((c: any) => (
          <li key={c.id} className="py-3">
            <p className="text-sm font-medium">
              {STAGES.find((s) => s.value === c.stage)?.label ?? c.stage}
            </p>
            <p className="text-xs text-slate-400">Opened {formatDate(c.opened_on)}</p>
            {c.stage !== 'closed' && (
              <select
                defaultValue=""
                onChange={(e) => e.target.value &&
                  escalate.mutate({ id: c.id, stage: e.target.value as Stage })}
                className="mt-2 h-9 rounded-lg border border-slate-300 px-2 text-xs"
              >
                <option value="">Move to…</option>
                {STAGES.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
              </select>
            )}
          </li>
        ))}
      </ul>
    </div>
  )
}

function OccurrenceLog({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [entry, setEntry] = useState('')
  const [category, setCategory] = useState('general')
  const list = useQuery({ queryKey: ['occurrences'], queryFn: api.fetchOccurrences })

  const append = useMutation({
    mutationFn: () => api.appendOccurrence({
      school_id: claims.school_id!, entered_by: claims.person_id!, category, entry,
    }),
    onSuccess: () => { setEntry(''); void qc.invalidateQueries({ queryKey: ['occurrences'] }) },
  })

  return (
    <div className="px-4 py-4">
      <div className="rounded-xl border border-slate-200 p-4">
        <p className="text-sm font-medium">Add an entry</p>
        <p className="mt-0.5 text-xs text-slate-400">
          The occurrence log is append-only. Entries cannot be edited or deleted;
          a correction is recorded as a new entry.
        </p>
        <textarea value={entry} onChange={(e) => setEntry(e.target.value)} rows={3}
                  className="mt-2 w-full rounded-lg border border-slate-300 p-2 text-sm" />
        <div className="mt-2 flex gap-2">
          <select value={category} onChange={(e) => setCategory(e.target.value)}
                  className="h-10 rounded-lg border border-slate-300 px-2 text-sm">
            <option value="general">General</option>
            <option value="discipline">Discipline</option>
            <option value="safety">Safety</option>
            <option value="visitor">Visitor</option>
            <option value="maintenance">Maintenance</option>
          </select>
          <button
            disabled={entry.trim() === '' || append.isPending}
            onClick={() => append.mutate()}
            className="h-10 flex-1 rounded-lg bg-brand text-sm font-semibold text-white disabled:opacity-40"
          >
            Append
          </button>
        </div>
      </div>

      <ul className="mt-4 divide-y divide-slate-100">
        {(list.data ?? []).map((o: any) => (
          <li key={o.id} className="py-3">
            <p className="text-sm">{o.entry}</p>
            <p className="mt-0.5 text-xs text-slate-400">
              {new Date(o.occurred_at).toLocaleString('en-GB', { timeZone: 'Indian/Mauritius' })}
              {o.category && ` · ${o.category}`}
              {o.corrects_entry_id && ` · corrects #${o.corrects_entry_id}`}
            </p>
          </li>
        ))}
      </ul>
    </div>
  )
}
