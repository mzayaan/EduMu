import { supabase } from '@/lib/supabase'

export interface Committee {
  id: string
  code: string
  name: string
  terms_of_reference: string | null
  min_meetings_per_term: number | null
  member_count?: number
  meetings_held?: number
}

export interface Member {
  person_id: string
  role_in_committee: string | null
  first_name: string
  last_name: string
  person_type: string
}

export interface Meeting {
  id: string
  kind: string
  title: string
  held_on: string
  venue: string | null
  agenda: string | null
  minutes: string | null
  visibility: string
  committee_id: string | null
}

export interface ActionItem {
  id: string
  description: string
  owner_person_id: string | null
  due_on: string | null
  status: 'open' | 'done' | 'cancelled'
  completed_on: string | null
  meeting_id: string | null
  owner_name?: string
}

export async function fetchCommittees(): Promise<Committee[]> {
  const { data, error } = await supabase
    .from('committee')
    .select('id,code,name,terms_of_reference,min_meetings_per_term')
    .order('name')
  if (error) throw error
  return data ?? []
}

export async function fetchMembers(committeeId: string): Promise<Member[]> {
  const { data, error } = await supabase
    .from('committee_member')
    .select('person_id,role_in_committee')
    .eq('committee_id', committeeId)
  if (error) throw error

  const ids = (data ?? []).map((m: any) => m.person_id)
  if (ids.length === 0) return []

  const { data: people, error: e2 } = await supabase
    .from('person')
    .select('id,first_name,last_name,person_type')
    .in('id', ids)
  if (e2) throw e2

  return (data ?? []).map((m: any) => ({
    ...m,
    ...((people ?? []).find((p: any) => p.id === m.person_id) ?? {
      first_name: '', last_name: '', person_type: '',
    }),
  }))
}

/** Staff and guardians both sit on committees — the Pastoral Care Committee
 *  is required to include a parent, not necessarily a PTA Executive member. */
export async function searchPeople(q: string) {
  let query = supabase
    .from('person')
    .select('id,first_name,last_name,person_type')
    .in('person_type', ['staff', 'guardian'])
    .limit(20)
  if (q.trim()) {
    query = query.or(`first_name.ilike.%${q}%,last_name.ilike.%${q}%`)
  }
  const { data, error } = await query
  if (error) throw error
  return data ?? []
}

export async function addMember(committeeId: string, personId: string, role: string) {
  const { error } = await supabase.from('committee_member').insert({
    committee_id: committeeId, person_id: personId,
    role_in_committee: role || null,
  })
  if (error) throw error
}

export async function removeMember(committeeId: string, personId: string) {
  const { error } = await supabase
    .from('committee_member')
    .delete()
    .eq('committee_id', committeeId)
    .eq('person_id', personId)
  if (error) throw error
}

export async function fetchMeetings(committeeId?: string): Promise<Meeting[]> {
  let q = supabase
    .from('meeting')
    .select('id,kind,title,held_on,venue,agenda,minutes,visibility,committee_id')
    .order('held_on', { ascending: false })
    .limit(50)
  if (committeeId) q = q.eq('committee_id', committeeId)
  const { data, error } = await q
  if (error) throw error
  return data ?? []
}

export async function createMeeting(v: {
  school_id: string
  kind: string
  committee_id: string | null
  title: string
  held_on: string
  venue: string
  agenda: string
  chaired_by: string
}) {
  const { data, error } = await supabase
    .from('meeting').insert(v).select('id').single()
  if (error) throw error
  return data.id as string
}

export async function saveMinutes(meetingId: string, minutes: string) {
  const { error } = await supabase
    .from('meeting').update({ minutes }).eq('id', meetingId)
  if (error) throw error
}

export async function fetchAttendance(meetingId: string) {
  const { data, error } = await supabase
    .from('meeting_attendance')
    .select('person_id,present,apology')
    .eq('meeting_id', meetingId)
  if (error) throw error
  return data ?? []
}

export async function setAttendance(
  meetingId: string, personId: string, present: boolean, apology = false,
) {
  const { error } = await supabase
    .from('meeting_attendance')
    .upsert({ meeting_id: meetingId, person_id: personId, present, apology },
            { onConflict: 'meeting_id,person_id' })
  if (error) throw error
}

/** Minutes without follow-up are decoration; actions carry an owner and a date. */
export async function fetchActions(opts: { mine?: string; meetingId?: string } = {}) {
  let q = supabase
    .from('action_item')
    .select('id,description,owner_person_id,due_on,status,completed_on,meeting_id')
    .order('due_on', { nullsFirst: false })
  if (opts.mine) q = q.eq('owner_person_id', opts.mine)
  if (opts.meetingId) q = q.eq('meeting_id', opts.meetingId)
  const { data, error } = await q
  if (error) throw error

  const ids = [...new Set((data ?? []).map((a: any) => a.owner_person_id).filter(Boolean))]
  const { data: people } = ids.length
    ? await supabase.from('person').select('id,first_name,last_name').in('id', ids)
    : { data: [] as any[] }

  return (data ?? []).map((a: any) => {
    const o = (people ?? []).find((p: any) => p.id === a.owner_person_id)
    return { ...a, owner_name: o ? `${o.first_name} ${o.last_name}` : null } as ActionItem
  })
}

export async function addAction(v: {
  school_id: string
  meeting_id: string | null
  description: string
  owner_person_id: string | null
  due_on: string | null
}) {
  const { error } = await supabase.from('action_item').insert(v)
  if (error) throw error
}

export async function completeAction(id: string) {
  const { error } = await supabase.from('action_item').update({
    status: 'done', completed_on: new Date().toISOString().slice(0, 10),
  }).eq('id', id)
  if (error) throw error
}
