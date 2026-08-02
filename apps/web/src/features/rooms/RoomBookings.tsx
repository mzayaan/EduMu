import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { hasCap, supabase, type EduClaims } from '@/lib/supabase'

interface Booking {
  id: string
  room_id: string
  date: string
  starts_at: string
  ends_at: string
  purpose: string
  status: 'requested' | 'approved' | 'declined' | 'cancelled'
  requested_by: string
  note: string | null
}

interface Room { id: string; code: string; name: string; capacity: number | null }

async function fetchRooms(): Promise<Room[]> {
  const { data, error } = await supabase
    .from('room').select('id,code,name,capacity').eq('is_active', true).order('code')
  if (error) throw error
  return (data ?? []) as Room[]
}

async function fetchBookings(from: string): Promise<Booking[]> {
  const { data, error } = await supabase
    .from('room_booking')
    .select('id,room_id,date,starts_at,ends_at,purpose,status,requested_by,note')
    .gte('date', from)
    .order('date').order('starts_at')
  if (error) throw error
  return (data ?? []) as Booking[]
}

async function requestBooking(v: {
  roomId: string; date: string; from: string; to: string; purpose: string; me: string
}) {
  // requested_by must be the caller: the RLS insert policy checks it, so a
  // mismatch is refused by the database rather than trusted from the client.
  const { error } = await supabase.from('room_booking').insert({
    room_id: v.roomId, date: v.date, starts_at: v.from, ends_at: v.to,
    purpose: v.purpose, requested_by: v.me, status: 'requested',
  })
  if (error) throw error
}

async function decide(id: string, approve: boolean, note?: string) {
  const { error } = await supabase.rpc('rpc_decide_room_booking', {
    p_booking: id, p_approve: approve, p_note: note ?? null,
  })
  if (error) throw error
}

const TONE: Record<Booking['status'], string> = {
  requested: 'bg-amber-50 text-amber-800 ring-amber-200',
  approved: 'bg-emerald-50 text-emerald-800 ring-emerald-200',
  declined: 'bg-red-50 text-red-800 ring-red-200',
  cancelled: 'bg-slate-100 text-slate-600 ring-slate-200',
}

/**
 * Ad-hoc room use outside the timetable.
 *
 * Two things can block an approval and they fail in different places: another
 * approved booking is refused by an exclusion constraint in Postgres, and a
 * clash with the published timetable is refused by rpc_decide_room_booking,
 * which can see lessons the constraint cannot. Both surface here as the error
 * text from the database — deliberately, rather than being pre-checked in the
 * client and allowed to drift.
 */
export function RoomBookings({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const canApprove = hasCap(claims, 'school.manage')
  // person_id is optional on the claims type because a token issued before the
  // auth hook was enabled carries none. Such a session cannot book: the RLS
  // insert policy requires requested_by = app.person_id(), so sending anything
  // else would be refused by the database anyway.
  const me = claims.person_id
  const [from] = useState(() => new Date().toISOString().slice(0, 10))
  const [err, setErr] = useState<string | null>(null)

  const rooms = useQuery({ queryKey: ['rooms'], queryFn: fetchRooms })
  const bookings = useQuery({ queryKey: ['bookings', from], queryFn: () => fetchBookings(from) })

  const roomOf = useMemo(
    () => new Map((rooms.data ?? []).map((r) => [r.id, r.code])),
    [rooms.data],
  )

  const refresh = () => qc.invalidateQueries({ queryKey: ['bookings', from] })
  const fail = (e: unknown) => setErr(e instanceof Error ? e.message : String(e))

  const create = useMutation({
    mutationFn: requestBooking,
    onSuccess: () => { setErr(null); refresh() },
    onError: fail,
  })
  const act = useMutation({
    mutationFn: (v: { id: string; approve: boolean }) => decide(v.id, v.approve),
    onSuccess: () => { setErr(null); refresh() },
    onError: fail,
  })

  const [form, setForm] = useState({ roomId: '', date: from, start: '14:00', end: '15:00', purpose: '' })

  return (
    <div className="mx-auto max-w-5xl space-y-5 p-4 sm:p-6">
      <header>
        <h1 className="text-lg font-semibold text-slate-900">Room bookings</h1>
        <p className="mt-1 text-sm text-slate-600">
          For use outside the timetable — meetings, rehearsals, extra classes.
          Lessons always win: a booking that clashes with a published lesson is
          refused.
        </p>
      </header>

      {err && <p className="rounded bg-red-50 px-3 py-2 text-sm text-red-800">{err}</p>}

      <section className="rounded-lg border border-slate-200 p-4">
        <h2 className="text-sm font-semibold text-slate-900">Request a room</h2>
        <div className="mt-3 flex flex-wrap items-end gap-3">
          <label className="text-sm">
            <span className="block text-xs font-medium text-slate-600">Room</span>
            <select value={form.roomId} onChange={(e) => setForm({ ...form, roomId: e.target.value })}
                    className="mt-1 rounded-md border-slate-300 text-sm">
              <option value="">Choose…</option>
              {(rooms.data ?? []).map((r) => (
                <option key={r.id} value={r.id}>
                  {r.code} — {r.name}{r.capacity ? ` (${r.capacity})` : ''}
                </option>
              ))}
            </select>
          </label>
          <label className="text-sm">
            <span className="block text-xs font-medium text-slate-600">Date</span>
            <input type="date" value={form.date} onChange={(e) => setForm({ ...form, date: e.target.value })}
                   className="mt-1 rounded-md border-slate-300 text-sm" />
          </label>
          <label className="text-sm">
            <span className="block text-xs font-medium text-slate-600">From</span>
            <input type="time" value={form.start} onChange={(e) => setForm({ ...form, start: e.target.value })}
                   className="mt-1 rounded-md border-slate-300 text-sm" />
          </label>
          <label className="text-sm">
            <span className="block text-xs font-medium text-slate-600">To</span>
            <input type="time" value={form.end} onChange={(e) => setForm({ ...form, end: e.target.value })}
                   className="mt-1 rounded-md border-slate-300 text-sm" />
          </label>
          <label className="min-w-[12rem] flex-1 text-sm">
            <span className="block text-xs font-medium text-slate-600">Purpose</span>
            <input value={form.purpose} onChange={(e) => setForm({ ...form, purpose: e.target.value })}
                   placeholder="Prize-giving rehearsal"
                   className="mt-1 w-full rounded-md border-slate-300 text-sm" />
          </label>
          <button
            disabled={!me || !form.roomId || !form.purpose.trim()
                      || form.end <= form.start || create.isPending}
            onClick={() => create.mutate({
              roomId: form.roomId, date: form.date, from: form.start,
              to: form.end, purpose: form.purpose.trim(), me: me!,
            })}
            className="rounded-md bg-brand px-3 py-1.5 text-sm font-semibold text-white disabled:opacity-40"
          >
            Request
          </button>
        </div>
        {form.end <= form.start && (
          <p className="mt-2 text-xs text-amber-700">The end time must be after the start.</p>
        )}
      </section>

      <section className="rounded-lg border border-slate-200 p-4">
        <h2 className="text-sm font-semibold text-slate-900">Upcoming</h2>
        {(bookings.data ?? []).length === 0 ? (
          <p className="mt-2 text-sm text-slate-500">Nothing booked.</p>
        ) : (
          <table className="mt-2 min-w-full text-sm">
            <thead className="text-left text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="py-1.5 pr-3">Date</th>
                <th className="py-1.5 pr-3">Time</th>
                <th className="py-1.5 pr-3">Room</th>
                <th className="py-1.5 pr-3">Purpose</th>
                <th className="py-1.5 pr-3">Status</th>
                <th className="py-1.5" />
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {bookings.data!.map((b) => (
                <tr key={b.id}>
                  <td className="py-1.5 pr-3 tabular-nums">{b.date}</td>
                  <td className="py-1.5 pr-3 tabular-nums">
                    {b.starts_at.slice(0, 5)}–{b.ends_at.slice(0, 5)}
                  </td>
                  <td className="py-1.5 pr-3">{roomOf.get(b.room_id) ?? '—'}</td>
                  <td className="py-1.5 pr-3 text-slate-700">{b.purpose}</td>
                  <td className="py-1.5 pr-3">
                    <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ring-1 ${TONE[b.status]}`}>
                      {b.status}
                    </span>
                  </td>
                  <td className="py-1.5 text-right">
                    {canApprove && b.status === 'requested' && (
                      <span className="space-x-2">
                        <button onClick={() => act.mutate({ id: b.id, approve: true })}
                                className="text-xs font-medium text-emerald-700 hover:underline">
                          Approve
                        </button>
                        <button onClick={() => act.mutate({ id: b.id, approve: false })}
                                className="text-xs font-medium text-slate-500 hover:underline">
                          Decline
                        </button>
                      </span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </div>
  )
}
