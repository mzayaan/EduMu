import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { displayName, formatDate } from '@/lib/format'

interface Note {
  id: string
  student_id: string
  covers_from: string
  covers_to: string
  reason: string
  status: 'pending' | 'accepted' | 'rejected'
  submitted_at: string
  medical_certificate_path: string | null
  first_name: string
  last_name: string
  preferred_name: string | null
  admission_number: string
  class_name: string | null
}

async function fetchNotes(status: string): Promise<Note[]> {
  const { data, error } = await supabase
    .from('absence_note')
    .select('id,student_id,covers_from,covers_to,reason,status,submitted_at,medical_certificate_path')
    .eq('status', status)
    .order('submitted_at', { ascending: false })
  if (error) throw error
  const ids = (data ?? []).map((n: any) => n.student_id)
  if (ids.length === 0) return []

  const { data: pupils } = await supabase
    .from('class_roster')
    .select('student_id,first_name,last_name,preferred_name,admission_number,class_name')
    .in('student_id', ids)

  return (data ?? []).map((n: any) => ({
    ...n,
    ...((pupils ?? []).find((p: any) => p.student_id === n.student_id) ?? {}),
  }))
}

export function AbsenceNotes() {
  const qc = useQueryClient()
  const [tab, setTab] = useState<'pending' | 'accepted' | 'rejected'>('pending')

  const notes = useQuery({ queryKey: ['absence-notes', tab], queryFn: () => fetchNotes(tab) })

  const decide = useMutation({
    mutationFn: async (v: { id: string; accept: boolean; note?: string }) => {
      const { data, error } = await supabase.rpc('rpc_decide_absence_note', {
        p_note: v.id, p_accept: v.accept, p_note_text: v.note ?? null,
      })
      if (error) throw error
      return data as number
    },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['absence-notes'] }) },
  })

  return (
    <div className="mx-auto w-full max-w-3xl pb-32">
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <h1 className="text-lg font-semibold">Absence Notes</h1>
        <p className="text-sm text-slate-500">
          Only notes or medical certificates make an absence authorised
        </p>
        <div className="mt-3 flex gap-1">
          {(['pending', 'accepted', 'rejected'] as const).map((t) => (
            <button key={t} onClick={() => setTab(t)}
              className={`h-9 rounded-lg px-3 text-sm font-medium capitalize ${
                tab === t ? 'bg-brand text-white' : 'text-slate-600 hover:bg-slate-100'}`}>
              {t}
            </button>
          ))}
        </div>
      </header>

      {notes.isLoading && <p className="px-4 py-8 text-sm text-slate-500">Loading…</p>}

      {!notes.isLoading && (notes.data ?? []).length === 0 && (
        <p className="px-4 py-12 text-center text-sm text-slate-500">
          Nothing {tab}.
        </p>
      )}

      {decide.isSuccess && decide.data > 0 && (
        <p className="px-4 pt-3 text-xs text-present">
          {decide.data} register entr{decide.data === 1 ? 'y' : 'ies'} changed to authorised.
        </p>
      )}

      <ul className="divide-y divide-slate-100">
        {(notes.data ?? []).map((n) => (
          <li key={n.id} className="px-4 py-3">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="truncate text-sm font-medium">
                  {n.first_name ? displayName(n) : n.student_id}
                  <span className="ml-2 text-xs font-normal text-slate-400">
                    {n.admission_number} · {n.class_name}
                  </span>
                </p>
                <p className="mt-0.5 text-xs text-slate-400">
                  {formatDate(n.covers_from)} – {formatDate(n.covers_to)}
                </p>
                <p className="mt-1 text-sm text-slate-600">{n.reason}</p>
                {n.medical_certificate_path && (
                  <p className="mt-1 text-xs text-authorised">Medical certificate attached</p>
                )}
              </div>
            </div>

            {n.status === 'pending' && (
              <div className="mt-2 flex gap-1.5">
                <button
                  disabled={decide.isPending}
                  onClick={() => decide.mutate({ id: n.id, accept: true })}
                  className="h-9 rounded-lg border border-slate-200 px-3 text-xs font-medium
                             text-slate-600 hover:border-present hover:text-present"
                >
                  Accept — mark authorised
                </button>
                <button
                  disabled={decide.isPending}
                  onClick={() => decide.mutate({ id: n.id, accept: false })}
                  className="h-9 rounded-lg border border-slate-200 px-3 text-xs font-medium
                             text-slate-600 hover:border-absent hover:text-absent"
                >
                  Reject
                </button>
              </div>
            )}
          </li>
        ))}
      </ul>
    </div>
  )
}
