import { supabase } from '@/lib/supabase'

/**
 * The gate: who arrived late, and which staff are off site.
 *
 * Both are Usher/office duties in the School Management Manual, and both were
 * previously database-only — rpc_record_late_arrival existed, was tested, and
 * had no screen, so it could never actually fire.
 */

export interface LateArrivalOutcome {
  /**
   * `marked_late_in_am` — the morning register was still open, so the pupil is
   * simply late.
   * `carried_to_pm`     — the register had closed. The morning stands as
   * absent and the lateness lands on the afternoon register, which is the
   * school's paper convention. It costs the pupil a session, so the screen
   * says so rather than reporting a bare success.
   */
  outcome: 'marked_late_in_am' | 'carried_to_pm'
  minutes_late: number
  am_status: string
  after_am_register: boolean
}

export async function recordLateArrival(
  studentId: string, date: string, arrivedAt: string, reason?: string,
): Promise<LateArrivalOutcome> {
  const { data, error } = await supabase.rpc('rpc_record_late_arrival', {
    p_student: studentId, p_date: date, p_arrived_at: arrivedAt,
    p_reason: reason ?? null,
  })
  if (error) throw error
  return data as LateArrivalOutcome
}

export interface LateArrivalRow {
  student_id: string
  date: string
  arrived_at: string
  minutes_late: number | null
  after_am_register: boolean
  reason: string | null
  first_name: string
  last_name: string
  admission_number: string | null
  class_name: string | null
  am_status: string | null
  pm_status: string | null
}

export async function fetchLateArrivals(date: string): Promise<LateArrivalRow[]> {
  const { data, error } = await supabase
    .from('late_arrivals_report')
    .select('*')
    .eq('date', date)
    .order('arrived_at')
  if (error) throw error
  return (data ?? []) as LateArrivalRow[]
}

export interface PupilOption {
  student_id: string
  first_name: string
  last_name: string
  admission_number: string | null
  class_name: string | null
}

export async function searchPupils(q: string): Promise<PupilOption[]> {
  if (q.trim().length < 2) return []
  const like = `%${q.trim()}%`
  const { data, error } = await supabase
    .from('class_roster')
    .select('student_id,first_name,last_name,admission_number,class_name')
    .or(`first_name.ilike.${like},last_name.ilike.${like},admission_number.ilike.${like}`)
    .limit(15)
  if (error) throw error
  return (data ?? []) as PupilOption[]
}

// ── staff register ────────────────────────────────────────────────────────

export interface StaffAttendanceRow {
  id: string
  staff_id: string
  date: string
  status: 'present' | 'absent' | 'late' | 'on_leave' | 'off_site' | 'training'
  arrived_at: string | null
  minutes_late: number | null
  note: string | null
}

export async function openStaffRegister(date: string): Promise<number> {
  const { data, error } = await supabase.rpc('rpc_open_staff_register', { p_date: date })
  if (error) throw error
  return data as number
}

export async function fetchStaffRegister(date: string): Promise<StaffAttendanceRow[]> {
  const { data, error } = await supabase
    .from('staff_attendance')
    .select('id,staff_id,date,status,arrived_at,minutes_late,note')
    .eq('date', date)
  if (error) throw error
  return (data ?? []) as StaffAttendanceRow[]
}

export async function markStaffAttendance(
  staffId: string, date: string, status: string,
  arrivedAt?: string | null, note?: string | null,
): Promise<void> {
  const { error } = await supabase.rpc('rpc_mark_staff_attendance', {
    p_staff: staffId, p_date: date, p_status: status,
    p_arrived_at: arrivedAt ?? null, p_note: note ?? null,
  })
  if (error) throw error
}

export interface StaffOption { id: string; first_name: string; last_name: string; post: string | null }

export async function fetchStaff(): Promise<StaffOption[]> {
  const { data, error } = await supabase
    .from('staff')
    .select('id,post,person:person!inner(first_name,last_name)')
    .is('exited_on', null)
  if (error) throw error
  type Raw = { id: string; post: string | null; person: { first_name: string; last_name: string } }
  return ((data ?? []) as unknown as Raw[])
    .map((r) => ({
      id: r.id, post: r.post,
      first_name: r.person.first_name, last_name: r.person.last_name,
    }))
    .sort((a, b) => a.last_name.localeCompare(b.last_name))
}

// ── staff movement ────────────────────────────────────────────────────────

export interface StaffMovementRow {
  id: string
  staff_id: string
  date: string
  out_at: string
  in_at: string | null
  reason: string
  destination: string | null
}

export async function fetchStaffMovements(date: string): Promise<StaffMovementRow[]> {
  const { data, error } = await supabase
    .from('staff_movement')
    .select('id,staff_id,date,out_at,in_at,reason,destination')
    .eq('date', date)
    .order('out_at')
  if (error) throw error
  return (data ?? []) as StaffMovementRow[]
}

export async function signStaffOut(
  staffId: string, date: string, out: string, reason: string, destination?: string,
): Promise<string> {
  const { data, error } = await supabase.rpc('rpc_sign_staff_out', {
    p_staff: staffId, p_date: date, p_out: out,
    p_reason: reason, p_destination: destination ?? null,
  })
  if (error) throw error
  return data as string
}

export async function signStaffIn(movementId: string, backAt: string): Promise<void> {
  const { error } = await supabase.rpc('rpc_sign_staff_in', {
    p_movement: movementId, p_in: backAt,
  })
  if (error) throw error
}
