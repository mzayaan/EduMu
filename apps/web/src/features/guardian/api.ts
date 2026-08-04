import { supabase } from '@/lib/supabase'

export interface Ward {
  student_id: string
  first_name: string
  last_name: string
  preferred_name: string | null
  admission_number: string
  class_name: string | null
  is_responsible_party: boolean
}

/**
 * The pupils this portal should show.
 *
 * For a guardian that is their children, and RLS on student_guardian already
 * limits the read to them.
 *
 * `selfStudentId` covers a pupil signing in for themselves. Pupils hold no
 * capabilities at all — their access is relationship-based, decided inside the
 * policies by `student_id = app.person_id()` — so before this they landed in the
 * staff shell with nothing and saw an error telling them their account had no
 * permissions. They are not a guardian of themselves, so student_guardian
 * returns nothing for them and the id has to come from the caller.
 */
export async function fetchWards(selfStudentId?: string | null): Promise<Ward[]> {
  // RLS on student_guardian limits this to the caller's own children.
  const { data, error } = await supabase
    .from('student_guardian')
    .select('student_id, is_responsible_party')
  if (error) throw error
  const ids = (data ?? []).map((r: any) => r.student_id)
  if (selfStudentId && !ids.includes(selfStudentId)) ids.push(selfStudentId)
  if (ids.length === 0) return []

  const { data: roster, error: e2 } = await supabase
    .from('class_roster')
    .select('student_id,first_name,last_name,preferred_name,admission_number,class_name')
    .in('student_id', ids)
  if (e2) throw e2

  return (roster ?? []).map((r: any) => ({
    ...r,
    is_responsible_party:
      (data ?? []).find((d: any) => d.student_id === r.student_id)?.is_responsible_party ?? false,
  }))
}

export async function fetchWardAttendance(studentId: string) {
  const { data, error } = await supabase
    .from('attendance_summary')
    .select('term_id,sessions_possible,sessions_present,sessions_absent_unauth,sessions_absent_auth,times_late,pct_present')
    .eq('student_id', studentId)
  if (error) throw error
  return data ?? []
}

export async function fetchWardRecentAbsences(studentId: string) {
  const { data, error } = await supabase
    .from('attendance_record')
    .select('id,status,note,attendance_session:attendance_session_id ( date, session )')
    .eq('student_id', studentId)
    .in('status', ['absent_unauth', 'absent_auth', 'late'])
    .order('id', { ascending: false })
    .limit(30)
  if (error) throw error
  return (data ?? []).map((r: any) => ({
    id: r.id,
    status: r.status,
    note: r.note,
    date: r.attendance_session?.date as string,
    session: r.attendance_session?.session as string,
  }))
}

/** Only published assessments are visible here — enforced by RLS, not by this query. */
export async function fetchWardResults(studentId: string) {
  const { data, error } = await supabase
    .from('term_result')
    .select('term_id,subject_id,aggregate_score,band_label,rank_in_set,set_size,subject:subject_id ( name_en )')
    .eq('student_id', studentId)
  if (error) throw error
  return (data ?? []).map((r: any) => ({ ...r, subject_name: r.subject?.name_en }))
}

export async function fetchWardHomework(studentId: string) {
  const { data, error } = await supabase
    .from('homework')
    .select('id,title,description,due_on,set_on,subject_set:subject_set_id ( name )')
    .gte('due_on', new Date(Date.now() - 14 * 864e5).toISOString().slice(0, 10))
    .order('due_on')
  if (error) throw error
  return (data ?? []).map((r: any) => ({ ...r, set_name: r.subject_set?.name }))
}

export async function fetchNotices() {
  const { data, error } = await supabase
    .from('notice')
    .select('id,title,body,publish_at,pinned')
    .order('pinned', { ascending: false })
    .order('publish_at', { ascending: false })
    .limit(20)
  if (error) throw error
  return data ?? []
}

export async function submitAbsenceNote(v: {
  school_id: string
  student_id: string
  covers_from: string
  covers_to: string
  reason: string
  medical_certificate_path?: string | null
}) {
  const { error } = await supabase.from('absence_note').insert(v)
  if (error) throw error
}

export async function fetchWardAbsenceNotes(studentId: string) {
  const { data, error } = await supabase
    .from('absence_note')
    .select('id,covers_from,covers_to,reason,status,decided_at,decision_note')
    .eq('student_id', studentId)
    .order('covers_from', { ascending: false })
  if (error) throw error
  return data ?? []
}
