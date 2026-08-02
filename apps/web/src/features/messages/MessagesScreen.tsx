import { useEffect, useMemo, useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase, type EduClaims } from '@/lib/supabase'
import { formatDate } from '@/lib/format'

interface Thread {
  id: string
  subject: string
  about_student_id: string | null
  created_by: string | null
  created_at: string
  last_message?: string
  last_at?: string
}

/**
 * Messages.
 *
 * The Manual asks educators to "maintain regular communication with the
 * parents" and expects the Rector to write to parents as the need arises. A
 * thread keeps that conversation in one place and gives the school an evidence
 * trail — which matters when a disagreement about a child becomes formal.
 *
 * The same screen serves staff↔staff and staff↔guardian. RLS decides what each
 * person sees; there is no separate guardian version to keep in step.
 *
 * ⚠️ Thread membership is answered by app.in_thread(). A subquery on
 * thread_participant from within its own policy re-enters that policy and
 * Postgres raises "infinite recursion". That cost an hour once already.
 */
export function MessagesScreen({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const [openId, setOpenId] = useState<string | null>(null)
  const [composing, setComposing] = useState(false)
  const [subject, setSubject] = useState('')
  const [recipients, setRecipients] = useState<string[]>([])
  const [q, setQ] = useState('')
  const [body, setBody] = useState('')
  const [error, setError] = useState<string | null>(null)

  const threads = useQuery({
    queryKey: ['threads'],
    queryFn: async (): Promise<Thread[]> => {
      const { data, error } = await supabase
        .from('message_thread')
        .select('id,subject,about_student_id,created_by,created_at')
        .order('created_at', { ascending: false })
      if (error) throw error
      return data ?? []
    },
  })

  const messages = useQuery({
    queryKey: ['messages', openId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('message')
        .select('id,thread_id,sender_id,body,sent_at')
        .eq('thread_id', openId!)
        .order('sent_at')
      if (error) throw error
      return data ?? []
    },
    enabled: Boolean(openId),
    refetchInterval: 30_000,
  })

  const people = useQuery({
    queryKey: ['msg-people', q],
    queryFn: async () => {
      let query = supabase
        .from('person')
        .select('id,first_name,last_name,person_type')
        .neq('id', claims.person_id!)
        .limit(15)
      if (q.trim()) query = query.or(`first_name.ilike.%${q}%,last_name.ilike.%${q}%`)
      const { data, error } = await query
      if (error) throw error
      return data ?? []
    },
    enabled: composing,
  })

  // Sender names, resolved once for the open thread.
  const senderIds = useMemo(
    () => [...new Set((messages.data ?? []).map((m: any) => m.sender_id))],
    [messages.data],
  )
  const senders = useQuery({
    queryKey: ['msg-senders', senderIds.join(',')],
    queryFn: async () => {
      if (senderIds.length === 0) return []
      const { data } = await supabase
        .from('person').select('id,first_name,last_name').in('id', senderIds)
      return data ?? []
    },
    enabled: senderIds.length > 0,
  })
  const nameOf = (id: string) => {
    const p = (senders.data ?? []).find((x: any) => x.id === id)
    return p ? `${p.first_name} ${p.last_name}` : 'Unknown'
  }

  const start = useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase
        .from('message_thread')
        .insert({
          school_id: claims.school_id, subject: subject.trim(),
          created_by: claims.person_id,
        })
        .select('id').single()
      if (error) throw error

      // The creator must be a participant, or their own policy hides it.
      const { error: e2 } = await supabase.from('thread_participant').insert(
        [claims.person_id!, ...recipients].map((person_id) => ({
          thread_id: data.id, person_id,
        })),
      )
      if (e2) throw e2

      if (body.trim()) {
        const { error: e3 } = await supabase.from('message').insert({
          school_id: claims.school_id, thread_id: data.id,
          sender_id: claims.person_id, body: body.trim(),
        })
        if (e3) throw e3
      }
      return data.id as string
    },
    onSuccess: (id) => {
      setComposing(false); setSubject(''); setRecipients([]); setBody(''); setError(null)
      setOpenId(id)
      void qc.invalidateQueries({ queryKey: ['threads'] })
    },
    onError: (e: any) => setError(e.message),
  })

  const send = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.from('message').insert({
        school_id: claims.school_id, thread_id: openId,
        sender_id: claims.person_id, body: body.trim(),
      })
      if (error) throw error
    },
    onSuccess: () => {
      setBody(''); setError(null)
      void qc.invalidateQueries({ queryKey: ['messages', openId] })
    },
    onError: (e: any) => setError(e.message),
  })

  const bottomRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages.data])

  return (
    <div className="mx-auto w-full max-w-4xl pb-32">
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <h1 className="text-lg font-semibold">Messages</h1>
        <p className="text-sm text-slate-500">
          Conversations with colleagues and Responsible Parties
        </p>
        <button onClick={() => { setComposing((v) => !v); setOpenId(null) }}
                className="mt-3 h-10 rounded-lg bg-brand px-4 text-sm font-semibold text-white">
          {composing ? 'Cancel' : 'New conversation'}
        </button>
      </header>

      {error && <p className="px-4 pt-3 text-sm text-absent">{error}</p>}

      {composing && (
        <div className="m-4 space-y-2 rounded-xl border border-slate-200 p-4">
          <input value={subject} onChange={(e) => setSubject(e.target.value)}
                 placeholder="Subject, e.g. Attendance in Term 2"
                 className="h-10 w-full rounded-lg border border-slate-300 px-2.5 text-sm" />

          {recipients.length > 0 && (
            <div className="flex flex-wrap gap-1">
              {recipients.map((id) => {
                const p = (people.data ?? []).find((x: any) => x.id === id)
                return (
                  <span key={id}
                        className="rounded-full bg-brand-light px-2 py-0.5 text-xs text-brand">
                    {p ? `${p.first_name} ${p.last_name}` : id.slice(0, 8)}
                    <button onClick={() => setRecipients(recipients.filter((r) => r !== id))}
                            className="ml-1 text-brand/60 hover:text-brand">×</button>
                  </span>
                )
              })}
            </div>
          )}

          <input value={q} onChange={(e) => setQ(e.target.value)}
                 placeholder="Add people by name"
                 className="h-9 w-full rounded-lg border border-slate-300 px-2.5 text-xs" />
          {q.trim() && (
            <ul className="max-h-40 overflow-y-auto rounded-lg border border-slate-200">
              {(people.data ?? [])
                .filter((p: any) => !recipients.includes(p.id))
                .map((p: any) => (
                <li key={p.id}>
                  <button onClick={() => { setRecipients([...recipients, p.id]); setQ('') }}
                    className="flex w-full items-center justify-between px-2.5 py-1.5
                               text-left text-xs hover:bg-slate-50">
                    <span>{p.last_name}, {p.first_name}</span>
                    <span className="text-slate-400">{p.person_type}</span>
                  </button>
                </li>
              ))}
            </ul>
          )}

          <textarea value={body} onChange={(e) => setBody(e.target.value)} rows={3}
                    placeholder="First message"
                    className="w-full rounded-lg border border-slate-300 p-2 text-sm" />
          <button
            disabled={!subject.trim() || recipients.length === 0 || start.isPending}
            onClick={() => start.mutate()}
            className="h-10 w-full rounded-lg bg-brand text-sm font-semibold text-white disabled:opacity-40"
          >
            Start conversation
          </button>
        </div>
      )}

      <div className="grid gap-4 px-4 py-4 sm:grid-cols-[16rem_1fr]">
        <aside>
          {(threads.data ?? []).length === 0 && !threads.isLoading && (
            <p className="text-sm text-slate-500">No conversations yet.</p>
          )}
          <ul className="divide-y divide-slate-100">
            {(threads.data ?? []).map((t) => (
              <li key={t.id}>
                <button onClick={() => { setOpenId(t.id); setComposing(false) }}
                  className={`w-full px-2 py-2 text-left ${
                    t.id === openId ? 'bg-brand-light' : 'hover:bg-slate-50'}`}>
                  <p className="truncate text-sm font-medium">{t.subject}</p>
                  <p className="text-xs text-slate-400">
                    {formatDate(t.created_at.slice(0, 10))}
                  </p>
                </button>
              </li>
            ))}
          </ul>
        </aside>

        <div>
          {!openId && (
            <p className="py-10 text-center text-sm text-slate-500">
              Select a conversation.
            </p>
          )}
          {openId && (
            <>
              <ul className="space-y-2">
                {(messages.data ?? []).map((m: any) => {
                  const mine = m.sender_id === claims.person_id
                  return (
                    <li key={m.id} className={mine ? 'text-right' : ''}>
                      <div className={`inline-block max-w-[80%] rounded-xl px-3 py-2 text-left
                        ${mine ? 'bg-brand text-white' : 'bg-slate-100'}`}>
                        {!mine && (
                          <p className="text-[10px] font-semibold opacity-70">
                            {nameOf(m.sender_id)}
                          </p>
                        )}
                        <p className="whitespace-pre-line text-sm">{m.body}</p>
                        <p className={`mt-0.5 text-[10px] ${mine ? 'text-white/60' : 'text-slate-400'}`}>
                          {new Date(m.sent_at).toLocaleString('en-GB', {
                            timeZone: 'Indian/Mauritius',
                            day: '2-digit', month: '2-digit',
                            hour: '2-digit', minute: '2-digit',
                          })}
                        </p>
                      </div>
                    </li>
                  )
                })}
                <div ref={bottomRef} />
              </ul>

              <div className="mt-3 flex gap-2">
                <textarea value={body} onChange={(e) => setBody(e.target.value)} rows={2}
                          placeholder="Write a reply"
                          onKeyDown={(e) => {
                            if (e.key === 'Enter' && (e.metaKey || e.ctrlKey) && body.trim()) {
                              send.mutate()
                            }
                          }}
                          className="flex-1 rounded-lg border border-slate-300 p-2 text-sm" />
                <button disabled={!body.trim() || send.isPending}
                        onClick={() => send.mutate()}
                        className="h-10 shrink-0 self-end rounded-lg bg-brand px-4 text-sm
                                   font-semibold text-white disabled:opacity-40">
                  Send
                </button>
              </div>
              <p className="mt-1 text-[10px] text-slate-400">
                Ctrl/⌘ + Enter to send. This conversation is retained as a record
                of contact with the family.
              </p>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
