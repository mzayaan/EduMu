/**
 * Slim hand-maintained types for the tables the app touches today.
 * Regenerate the full set with:  npm run db:types
 */
export type AttendanceStatus =
  | 'present' | 'absent_unauth' | 'absent_auth' | 'late'
  | 'on_leave' | 'excluded' | 'school_activity'

export type SessionType = 'am' | 'pm'

export interface ClassGroup {
  id: string
  name: string
  stream: 'regular' | 'extended' | 'technical' | 'general'
  grade_level_id: string
  home_room_id: string | null
}

export interface RosterStudent {
  student_id: string
  first_name: string
  last_name: string
  preferred_name: string | null
  admission_number: string
  photo_path: string | null
  roll_number: number | null
  is_class_captain: boolean
}

export interface AttendanceRecord {
  id: string
  attendance_session_id: string
  student_id: string
  status: AttendanceStatus
  minutes_late: number | null
  note: string | null
}

export interface AttendanceSession {
  id: string
  class_group_id: string
  date: string
  session: SessionType
  status: 'open' | 'closed' | 'amended'
  taken_at: string | null
}
