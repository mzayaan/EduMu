import { supabase } from '@/lib/supabase'
import type { AttendanceStatus } from '@/types/database'

export interface Lesson {
  timetable_slot_id: string
  subject_set_id: string
  set_name: string
  subject_name: string
  class_hint: string | null
  period_id: string
  period_name: string
  starts_at: string
  ends_at: string
  room_code: string | null
  cycle_day: number
  marked_count: number
  roster_count: number
}

export interface SetStudent {
  student_id: string
  first_name: string
  last_name: string
  preferred_name: string | null
  admission_number: string
  class_name: string | null
  register_status: AttendanceStatus | null
  period_status: AttendanceStatus | null
}

/** Lessons the caller teaches on a date, resolved via the school calendar. */
export async function fetchMyLessons(date: string): Promise<Lesson[]> {
  const { data, error } = await supabase.rpc('my_lessons', { p_date: date })
  if (error) throw error
  return (data ?? []) as Lesson[]
}

export async function fetchSetRoster(setId: string, date: string): Promise<SetStudent[]> {
  const { data, error } = await supabase.rpc('set_roster', { p_set: setId, p_date: date })
  if (error) throw error
  return (data ?? []) as SetStudent[]
}

/** Carries the morning register forward so only real changes need a tap. */
export async function prefillPeriod(slotId: string, setId: string, date: string) {
  const { data, error } = await supabase.rpc('rpc_prefill_period', {
    p_slot: slotId, p_set: setId, p_date: date,
  })
  if (error) throw error
  return data as number
}
