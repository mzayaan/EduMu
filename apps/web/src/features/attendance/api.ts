import { supabase } from '@/lib/supabase'
import type {
  AttendanceRecord, AttendanceSession, ClassGroup, RosterStudent, SessionType,
} from '@/types/database'

export async function fetchMyClasses(): Promise<ClassGroup[]> {
  // RLS already limits this to classes the caller may see, so no filter here.
  const { data, error } = await supabase
    .from('class_group')
    .select('id,name,stream,grade_level_id,home_room_id')
    .order('name')
  if (error) throw error
  return data ?? []
}

export async function fetchRoster(
  classGroupId: string, onDate: string,
): Promise<RosterStudent[]> {
  // class_roster is a security_invoker view: the join happens in Postgres and
  // the caller's RLS still applies, so this cannot leak another class.
  const { data, error } = await supabase
    .from('class_roster')
    .select('student_id,roll_number,is_class_captain,admission_number,first_name,last_name,preferred_name,photo_path')
    .eq('class_group_id', classGroupId)
    .lte('effective_from', onDate)
    .or(`effective_to.is.null,effective_to.gte.${onDate}`)
    .order('roll_number', { ascending: true, nullsFirst: false })
    .order('last_name')
  if (error) throw error
  return (data ?? []) as RosterStudent[]
}

/**
 * Opens (or re-opens) the register. The RPC is idempotent and pre-fills every
 * enrolled student as present, so the common case is zero taps.
 */
export async function openRegister(
  classGroupId: string, date: string, session: SessionType,
): Promise<string> {
  const { data, error } = await supabase.rpc('rpc_open_register', {
    p_class_group_id: classGroupId, p_date: date, p_session: session,
  })
  if (error) throw error
  return data as string
}

export async function closeRegister(sessionId: string): Promise<void> {
  const { error } = await supabase.rpc('rpc_close_register', { p_session_id: sessionId })
  if (error) throw error
}

export async function fetchSession(
  classGroupId: string, date: string, session: SessionType,
): Promise<AttendanceSession | null> {
  const { data, error } = await supabase
    .from('attendance_session')
    .select('id,class_group_id,date,session,status,taken_at')
    .eq('class_group_id', classGroupId).eq('date', date).eq('session', session)
    .maybeSingle()
  if (error) throw error
  return data
}

export async function fetchRecords(sessionId: string): Promise<AttendanceRecord[]> {
  const { data, error } = await supabase
    .from('attendance_record')
    .select('id,attendance_session_id,student_id,status,minutes_late,note')
    .eq('attendance_session_id', sessionId)
  if (error) throw error
  return data ?? []
}

/** Amend a closed register. A reason is mandatory and is written to audit_log. */
export async function amendRecord(recordId: string, status: string, reason: string) {
  const { error } = await supabase.rpc('rpc_amend_attendance', {
    p_record_id: recordId, p_status: status, p_reason: reason,
  })
  if (error) throw error
}

export interface SchoolDay {
  date: string
  day_type: 'teaching' | 'holiday' | 'weekend' | 'closure' | 'exam_only' | 'activity'
  note: string | null
  closure_reason: string | null
  cycle_day: number | null
  term_id: string | null
}

/**
 * A register can only be opened on a teaching day. Checking here lets the UI
 * explain why rather than surfacing a raw RPC exception.
 */
export async function fetchSchoolDay(date: string): Promise<SchoolDay | null> {
  const { data, error } = await supabase
    .from('calendar_day')
    .select('date,day_type,note,closure_reason,cycle_day,term_id')
    .eq('date', date)
    .maybeSingle()
  if (error) throw error
  return data as SchoolDay | null
}

/** Nearest teaching day on or before `date` — used to offer a sensible jump. */
export async function fetchNearestTeachingDay(date: string): Promise<string | null> {
  const { data, error } = await supabase
    .from('calendar_day')
    .select('date')
    .eq('day_type', 'teaching')
    .lte('date', date)
    .order('date', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (error) throw error
  return data?.date ?? null
}
