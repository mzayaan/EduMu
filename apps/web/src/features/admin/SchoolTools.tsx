import { useState } from 'react'
import { useMutation, useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

/**
 * Two office jobs that had working RPCs and no way to reach them.
 *
 * Leaving certificates are a statutory document a school must issue, and the
 * attendance recompute is the recovery tool for when a register is amended
 * after summaries were built — without it the 80% eligibility figure quietly
 * disagrees with the register it came from.
 */

interface Leaver {
  id: string
  first_name: string
  last_name: string
  admission_number: string | null
}

async function fetchLeavers(q: string): Promise<Leaver[]> {
  let sel = supabase
    .from('class_roster')
    .select('student_id,first_name,last_name,admission_number')
    .limit(15)
  if (q.trim().length >= 2) {
    const like = `%${q.trim()}%`
    sel = sel.or(`first_name.ilike.${like},last_name.ilike.${like},admission_number.ilike.${like}`)
  }
  const { data, error } = await sel
  if (error) throw error
  type Raw = { student_id: string; first_name: string; last_name: string; admission_number: string | null }
  return ((data ?? []) as Raw[]).map((r) => ({
    id: r.student_id, first_name: r.first_name,
    last_name: r.last_name, admission_number: r.admission_number,
  }))
}

async function issueCertificate(studentId: string, reason: string, conduct: string) {
  const { data, error } = await supabase.rpc('rpc_issue_leaving_certificate', {
    p_student: studentId, p_reason: reason, p_conduct: conduct,
  })
  if (error) throw error
  return data as string
}

async function fetchTerms() {
  const { data, error } = await supabase
    .from('term').select('id,name,starts_on,ends_on').order('starts_on', { ascending: false })
  if (error) throw error
  return (data ?? []) as Array<{ id: string; name: string; starts_on: string }>
}

async function recompute(termId: string) {
  const { data, error } = await supabase.rpc('rpc_recompute_attendance_summary', {
    p_term_id: termId,
  })
  if (error) throw error
  return data as number
}

export function SchoolTools() {
  const [q, setQ] = useState('')
  const [picked, setPicked] = useState<Leaver | null>(null)
  const [reason, setReason] = useState('')
  const [conduct, setConduct] = useState('Good')
  const [termId, setTermId] = useState('')
  const [msg, setMsg] = useState<string | null>(null)
  const [err, setErr] = useState<string | null>(null)

  const leavers = useQuery({ queryKey: ['leavers', q], queryFn: () => fetchLeavers(q) })
  const terms = useQuery({ queryKey: ['terms'], queryFn: fetchTerms })

  const fail = (e: unknown) => { setErr(e instanceof Error ? e.message : String(e)); setMsg(null) }

  const issue = useMutation({
    mutationFn: () => issueCertificate(picked!.id, reason.trim(), conduct.trim()),
    onSuccess: () => {
      setErr(null)
      setMsg(`Leaving certificate issued for ${picked!.first_name} ${picked!.last_name}.`)
      setPicked(null); setReason('')
    },
    onError: fail,
  })

  const redo = useMutation({
    mutationFn: () => recompute(termId),
    onSuccess: (n) => { setErr(null); setMsg(`Recomputed ${n} attendance summar${n === 1 ? 'y' : 'ies'}.`) },
    onError: fail,
  })

  return (
    <div className="space-y-5 px-4 py-4">
      {msg && <p className="rounded bg-emerald-50 px-3 py-2 text-sm text-emerald-900">{msg}</p>}
      {err && <p className="rounded bg-red-50 px-3 py-2 text-sm text-red-800">{err}</p>}

      <section className="rounded-lg border border-slate-200 p-4">
        <h2 className="text-sm font-semibold text-slate-900">Leaving certificate</h2>
        <p className="mt-1 text-xs text-slate-500">
          A pupil may need this decades later. Conduct is recorded as written —
          it goes on the certificate.
        </p>

        <div className="mt-3 space-y-3">
          {picked ? (
            <div className="flex items-center gap-2 rounded-md bg-slate-100 px-2 py-1.5 text-sm">
              <span className="font-medium">{picked.first_name} {picked.last_name}</span>
              {picked.admission_number && (
                <span className="text-xs text-slate-500">{picked.admission_number}</span>
              )}
              <button onClick={() => setPicked(null)}
                      className="ml-auto text-xs text-slate-500 hover:text-slate-800">change</button>
            </div>
          ) : (
            <>
              <input value={q} onChange={(e) => setQ(e.target.value)}
                     placeholder="Search pupil by name or admission number"
                     className="w-full rounded-md border-slate-300 text-sm" />
              {(leavers.data ?? []).length > 0 && (
                <ul className="max-h-40 overflow-y-auto rounded-md border border-slate-200 text-sm">
                  {leavers.data!.map((l) => (
                    <li key={l.id}>
                      <button onClick={() => { setPicked(l); setQ('') }}
                              className="flex w-full justify-between px-2 py-1.5 text-left hover:bg-slate-50">
                        <span>{l.first_name} {l.last_name}</span>
                        <span className="text-xs text-slate-400">{l.admission_number}</span>
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </>
          )}

          <div className="flex flex-wrap gap-3">
            <label className="min-w-[14rem] flex-1 text-sm">
              <span className="block text-xs font-medium text-slate-600">Reason for leaving</span>
              <input value={reason} onChange={(e) => setReason(e.target.value)}
                     placeholder="Completed Upper VI / transferred"
                     className="mt-1 w-full rounded-md border-slate-300 text-sm" />
            </label>
            <label className="text-sm">
              <span className="block text-xs font-medium text-slate-600">Conduct</span>
              <input value={conduct} onChange={(e) => setConduct(e.target.value)}
                     className="mt-1 rounded-md border-slate-300 text-sm" />
            </label>
            <div className="flex items-end">
              <button
                disabled={!picked || !reason.trim() || issue.isPending}
                onClick={() => issue.mutate()}
                className="rounded-md bg-brand px-3 py-1.5 text-sm font-semibold text-white disabled:opacity-40"
              >
                {issue.isPending ? 'Issuing…' : 'Issue certificate'}
              </button>
            </div>
          </div>
        </div>
      </section>

      <section className="rounded-lg border border-slate-200 p-4">
        <h2 className="text-sm font-semibold text-slate-900">Rebuild attendance summaries</h2>
        <p className="mt-1 text-xs text-slate-500">
          Run after amending a register for a past term. Summaries are what the
          80% examination threshold is judged on, so if they lag behind the
          register, a pupil can be debarred on a figure that is no longer true.
        </p>
        <div className="mt-3 flex flex-wrap items-end gap-3">
          <label className="text-sm">
            <span className="block text-xs font-medium text-slate-600">Term</span>
            <select value={termId} onChange={(e) => setTermId(e.target.value)}
                    className="mt-1 rounded-md border-slate-300 text-sm">
              <option value="">Choose…</option>
              {(terms.data ?? []).map((t) => (
                <option key={t.id} value={t.id}>{t.name} — {t.starts_on}</option>
              ))}
            </select>
          </label>
          <button
            disabled={!termId || redo.isPending}
            onClick={() => redo.mutate()}
            className="rounded-md bg-white px-3 py-1.5 text-sm font-semibold text-slate-700 ring-1 ring-slate-300 hover:bg-slate-50 disabled:opacity-40"
          >
            {redo.isPending ? 'Rebuilding…' : 'Rebuild'}
          </button>
        </div>
      </section>
    </div>
  )
}
