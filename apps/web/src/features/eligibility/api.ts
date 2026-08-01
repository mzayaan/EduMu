import { supabase } from '@/lib/supabase'

export interface ExamSession {
  id: string
  kind: 'term_test' | 'end_of_term' | 'end_of_year' | 'mock' | 'national'
  name: string
  starts_on: string
  ends_on: string
  status: string
}

export interface EligibilityRow {
  student_id: string
  first_name: string
  last_name: string
  preferred_name: string | null
  admission_number: string
  class_name: string | null
  grade: number | null
  pct_present: number | null
  threshold: number
  sessions_possible: number
  sessions_present: number
  shortfall_sessions: number
  absent_unauth: number
  absent_auth: number
  times_late: number
  recommended: 'allow' | 'review' | 'no_data'
  decision: 'allow' | 'debar' | null
  decision_reason: string | null
  decided_at: string | null
  guardian_notified_at: string | null
}

export async function fetchExamSessions(): Promise<ExamSession[]> {
  const { data, error } = await supabase
    .from('exam_session')
    .select('id,kind,name,starts_on,ends_on,status')
    .order('starts_on')
  if (error) throw error
  return (data ?? []) as ExamSession[]
}

export async function fetchEligibility(sessionId: string): Promise<EligibilityRow[]> {
  const { data, error } = await supabase.rpc('exam_eligibility_screen', {
    p_session: sessionId,
  })
  if (error) throw error
  return (data ?? []) as EligibilityRow[]
}

/** Debarring requires a reason — enforced in the RPC, not just the form. */
export async function decideEligibility(
  sessionId: string, studentId: string,
  decision: 'allow' | 'debar', reason?: string,
) {
  const { error } = await supabase.rpc('rpc_decide_eligibility', {
    p_session: sessionId, p_student: studentId,
    p_decision: decision, p_reason: reason ?? null,
  })
  if (error) throw error
}
