import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { hasCap, supabase, type EduClaims } from '@/lib/supabase'
import {
  normaliseMauritianNumber, resolveProvider, segmentCount, type SmsMessage,
} from '@/lib/sms'

interface OutboxRow {
  id: string
  person_id: string
  recipient_name: string
  phone: string | null
  template: string
  body: string
  status: string
  scheduled_for: string | null
  error: string | null
}

async function fetchOutbox(): Promise<OutboxRow[]> {
  const { data, error } = await supabase.rpc('notification_outbox', {
    p_channel: 'sms', p_limit: 200,
  })
  if (error) throw error
  return (data ?? []) as OutboxRow[]
}

async function markSent(id: string, ok: boolean, providerRef?: string, err?: string) {
  const { error } = await supabase.rpc('rpc_mark_notification_sent', {
    p_id: id, p_ok: ok, p_provider_ref: providerRef ?? null, p_error: err ?? null,
  })
  if (error) throw error
}

interface Recipient { id: string; first_name: string; last_name: string; phone: string | null }

async function searchGuardians(q: string): Promise<Recipient[]> {
  if (q.trim().length < 2) return []
  const like = `%${q.trim()}%`
  const { data, error } = await supabase
    .from('person')
    .select('id,first_name,last_name,phone')
    .eq('person_type', 'guardian')
    .or(`first_name.ilike.${like},last_name.ilike.${like},phone.ilike.${like}`)
    .limit(10)
  if (error) throw error
  return (data ?? []) as Recipient[]
}

/** Queues an ad-hoc message. It joins the same outbox as everything else. */
async function queueMessage(personId: string, body: string) {
  const { error } = await supabase.rpc('rpc_queue_message', {
    p_person: personId, p_body: body, p_channel: 'sms',
  })
  if (error) throw error
}

/**
 * Message one guardian directly, for the cases no template covers.
 *
 * It queues rather than sends, so it lands in the same outbox and goes out
 * through the same provider with the same segment accounting. A second send
 * path would be a second place for the cost and the audit trail to diverge.
 */
function Compose({ onQueued }: { onQueued: () => void }) {
  const [q, setQ] = useState('')
  const [to, setTo] = useState<Recipient | null>(null)
  const [body, setBody] = useState('')
  const [err, setErr] = useState<string | null>(null)

  const results = useQuery({
    queryKey: ['guardian-search', q],
    queryFn: () => searchGuardians(q),
    enabled: q.trim().length >= 2,
  })

  const send = useMutation({
    mutationFn: () => queueMessage(to!.id, body.trim()),
    onSuccess: () => { setErr(null); setBody(''); setTo(null); setQ(''); onQueued() },
    onError: (e) => setErr(e instanceof Error ? e.message : String(e)),
  })

  const seg = segmentCount(body)

  return (
    <section className="rounded-lg border border-slate-200 p-4">
      <h2 className="text-sm font-semibold text-slate-900">Message one guardian</h2>
      {err && <p className="mt-2 rounded bg-red-50 px-2 py-1.5 text-sm text-red-800">{err}</p>}

      <div className="mt-3 space-y-2">
        {to ? (
          <div className="flex items-center gap-2 rounded-md bg-slate-100 px-2 py-1.5 text-sm">
            <span className="font-medium">{to.first_name} {to.last_name}</span>
            <span className="text-xs text-slate-500">
              {normaliseMauritianNumber(to.phone ?? '') ?? 'no usable number'}
            </span>
            <button onClick={() => setTo(null)}
                    className="ml-auto text-xs text-slate-500 hover:text-slate-800">change</button>
          </div>
        ) : (
          <>
            <input value={q} onChange={(e) => setQ(e.target.value)}
                   placeholder="Search guardian by name or number"
                   className="w-full rounded-md border-slate-300 text-sm" />
            {(results.data ?? []).length > 0 && (
              <ul className="max-h-40 overflow-y-auto rounded-md border border-slate-200 text-sm">
                {results.data!.map((r) => (
                  <li key={r.id}>
                    <button onClick={() => { setTo(r); setQ('') }}
                            className="flex w-full justify-between px-2 py-1.5 text-left hover:bg-slate-50">
                      <span>{r.first_name} {r.last_name}</span>
                      <span className="text-xs text-slate-400">{r.phone}</span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </>
        )}

        <textarea value={body} onChange={(e) => setBody(e.target.value)} rows={3}
                  placeholder="Message"
                  className="w-full rounded-md border-slate-300 text-sm" />

        <div className="flex items-center gap-3">
          <span className="text-xs text-slate-500">
            {body.length} characters · {seg.segments} segment{seg.segments === 1 ? '' : 's'}
            {seg.unicode && ' · non-GSM characters cut the segment to 70'}
          </span>
          <button
            disabled={!to || !body.trim() || send.isPending}
            onClick={() => send.mutate()}
            className="ml-auto rounded-md bg-white px-3 py-1.5 text-sm font-semibold text-slate-700 ring-1 ring-slate-300 disabled:opacity-40"
          >
            {send.isPending ? 'Queueing…' : 'Add to outbox'}
          </button>
        </div>
      </div>
    </section>
  )
}

/**
 * The SMS outbox.
 *
 * `notification` has been filling correctly since phase 3 and nothing has ever
 * emptied it — the queue was right and the dispatcher did not exist. This is
 * the dispatcher.
 *
 * Sending is a button rather than a cron job on purpose. In a system with no
 * pilot, an automatic sender that quietly burns credit — or quietly stops — is
 * worse than one a person presses and watches. Move the loop into a scheduled
 * Edge Function once a real school is using it; the provider adapters in
 * lib/sms.ts do not change.
 */
export function OutboxScreen({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const provider = useMemo(() => resolveProvider(), [])
  const [sending, setSending] = useState(false)
  const [log, setLog] = useState<string[]>([])
  const [selected, setSelected] = useState<Set<string>>(new Set())

  const canSend = hasCap(claims, 'person.read.all')
  const rows = useQuery({ queryKey: ['outbox'], queryFn: fetchOutbox, enabled: canSend })

  const all = rows.data ?? []
  const sendable = all.filter((r) => normaliseMauritianNumber(r.phone ?? '') !== null)
  const unreachable = all.filter((r) => normaliseMauritianNumber(r.phone ?? '') === null)

  const chosen = selected.size > 0
    ? sendable.filter((r) => selected.has(r.id))
    : sendable

  const cost = chosen.reduce((t, r) => t + segmentCount(r.body).segments, 0)

  const send = useMutation({
    mutationFn: async () => {
      setSending(true)
      setLog([])
      const lines: string[] = []

      // One at a time rather than one bulk call: providers batch by identical
      // body, and every message here is personalised. Sending them as a batch
      // would deliver the first pupil's name to every parent.
      for (const r of chosen) {
        const to = normaliseMauritianNumber(r.phone ?? '')!
        const msg: SmsMessage = { to, body: r.body, ref: r.id }
        // A provider that returns nothing for a message it was given is a
        // provider bug, but the message must not silently vanish from the
        // queue — treat it as a failure so it stays visible and retryable.
        const res = (await provider.send([msg]))[0]
          ?? { to, ok: false, error: `${provider.name} returned no result` }

        await markSent(r.id, res.ok, res.providerRef, res.error)
        lines.push(`${res.ok ? '✓' : '✗'} ${r.recipient_name} ${to}${res.error ? ` — ${res.error}` : ''}`)
        setLog([...lines])
      }
      return lines.length
    },
    onSettled: () => {
      setSending(false)
      setSelected(new Set())
      qc.invalidateQueries({ queryKey: ['outbox'] })
    },
  })

  if (!canSend) {
    return <p className="p-6 text-sm text-slate-600">
      Messaging guardians is an office function.
    </p>
  }

  return (
    <div className="mx-auto max-w-4xl space-y-5 p-4 sm:p-6">
      <header>
        <h1 className="text-lg font-semibold text-slate-900">SMS outbox</h1>
        <p className="mt-1 text-sm text-slate-600">
          Messages queued by unauthorised absence, discipline escalation and
          report publication.
        </p>
      </header>

      {/*
        A demo that pretends to text parents would be a worse lie than one that
        says plainly it did not. `delivers` comes from the adapter, so this
        cannot drift from what actually happened.
      */}
      {!provider.delivers && (
        <div className="rounded-lg border-2 border-dashed border-amber-400 bg-amber-50 p-3">
          <p className="text-sm font-semibold text-amber-900">
            No messages will reach a phone
          </p>
          <p className="mt-1 text-xs leading-relaxed text-amber-800">
            The <code>{provider.name}</code> provider is configured, which
            records the send and delivers nothing. There is no permanent free
            tier for real SMS: Twilio&apos;s trial prefixes every message and
            reaches only five verified numbers, Vonage gives about €2 of
            credit. For real delivery set <code>VITE_SMS_PROVIDER</code> to{' '}
            <code>africastalking</code> (free sandbox) or <code>textbee</code>{' '}
            (your own Android handset as the gateway). See <code>SMS.md</code>.
          </p>
        </div>
      )}

      <div className="flex flex-wrap items-center gap-3 rounded-lg border border-slate-200 p-4 text-sm">
        <div>
          <div className="text-xs uppercase tracking-wide text-slate-500">Queued</div>
          <div className="text-lg font-semibold tabular-nums">{all.length}</div>
        </div>
        <div>
          <div className="text-xs uppercase tracking-wide text-slate-500">Segments</div>
          <div className="text-lg font-semibold tabular-nums">{cost}</div>
          <div className="text-xs text-slate-500">what a provider bills</div>
        </div>
        {unreachable.length > 0 && (
          <div>
            <div className="text-xs uppercase tracking-wide text-slate-500">No usable number</div>
            <div className="text-lg font-semibold tabular-nums text-amber-700">
              {unreachable.length}
            </div>
          </div>
        )}
        <button
          disabled={chosen.length === 0 || sending}
          onClick={() => send.mutate()}
          className="ml-auto rounded-md bg-brand px-3 py-1.5 text-sm font-semibold text-white disabled:opacity-40"
        >
          {sending ? 'Sending…' : `Send ${chosen.length}`}
        </button>
      </div>

      {log.length > 0 && (
        <pre className="max-h-48 overflow-y-auto rounded-md bg-slate-900 p-3 text-xs text-slate-100">
          {log.join('\n')}
        </pre>
      )}

      <Compose onQueued={() => qc.invalidateQueries({ queryKey: ['outbox'] })} />

      {all.length === 0 ? (
        <p className="text-sm text-slate-500">The queue is empty.</p>
      ) : (
        <table className="min-w-full text-sm">
          <thead className="text-left text-xs uppercase tracking-wide text-slate-500">
            <tr>
              <th className="w-8 py-2" />
              <th className="py-2 pr-3">Recipient</th>
              <th className="py-2 pr-3">Message</th>
              <th className="py-2 pr-3 text-right">Seg</th>
              <th className="py-2">Status</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {all.map((r) => {
              const to = normaliseMauritianNumber(r.phone ?? '')
              const seg = segmentCount(r.body)
              return (
                <tr key={r.id} className={to ? '' : 'opacity-60'}>
                  <td className="py-2">
                    <input
                      type="checkbox" disabled={!to}
                      checked={selected.has(r.id)}
                      onChange={(e) => {
                        const next = new Set(selected)
                        e.target.checked ? next.add(r.id) : next.delete(r.id)
                        setSelected(next)
                      }}
                    />
                  </td>
                  <td className="py-2 pr-3">
                    <div className="font-medium text-slate-900">{r.recipient_name}</div>
                    <div className="text-xs text-slate-500">
                      {to ?? (r.phone ? `${r.phone} — not a valid Mauritian mobile` : 'no number on file')}
                    </div>
                  </td>
                  <td className="py-2 pr-3 text-slate-700">{r.body}</td>
                  <td className="py-2 pr-3 text-right tabular-nums">
                    {seg.segments}
                    {seg.unicode && (
                      <span className="ml-1 text-xs text-amber-700"
                            title="Non-GSM characters cut the segment to 70 chars — often a curly apostrophe or an accent">
                        U
                      </span>
                    )}
                  </td>
                  <td className="py-2">
                    {r.error
                      ? <span className="text-xs text-red-700">{r.error}</span>
                      : <span className="text-xs text-slate-500">{r.status}</span>}
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      )}
    </div>
  )
}
