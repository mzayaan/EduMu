import { supabase } from '@/lib/supabase'

export type PromotionOutcome =
  | 'promote' | 'conditional_promote' | 'repeat' | 'leave' | 'refer'

export interface PromotionRow {
  student_id: string
  first_name: string
  last_name: string
  admission_number: string | null
  class_name: string | null
  grade: number | null
  engine_outcome: PromotionOutcome
  override_outcome: PromotionOutcome | null
  effective_outcome: PromotionOutcome
  override_reason: string | null
  rule_name: string | null
  aggregate: number | null
  attendance_pct: number | null
  credit_count: number | null
  times_repeated: number | null
  confirmed_at: string | null
}

export interface AcademicYear {
  id: string
  name: string
  starts_on: string
  ends_on: string
  status: 'planning' | 'active' | 'closed'
}

export async function fetchYears(): Promise<AcademicYear[]> {
  const { data, error } = await supabase
    .from('academic_year')
    .select('id,name,starts_on,ends_on,status')
    .order('starts_on', { ascending: false })
  if (error) throw error
  return (data ?? []) as AcademicYear[]
}

export async function fetchPromotions(yearId: string): Promise<PromotionRow[]> {
  const { data, error } = await supabase
    .from('promotion_screen')
    .select('*')
    .eq('academic_year_id', yearId)
    .order('grade')
    .order('last_name')
  if (error) throw error
  return (data ?? []) as PromotionRow[]
}

export async function evaluatePromotions(yearId: string): Promise<number> {
  const { data, error } = await supabase.rpc('rpc_evaluate_promotions', { p_year: yearId })
  if (error) throw error
  return data as number
}

/** A reason is mandatory — the RPC refuses without one, and so should the UI. */
export async function overridePromotion(
  studentId: string, yearId: string, outcome: PromotionOutcome, reason: string,
): Promise<void> {
  const { error } = await supabase.rpc('rpc_override_promotion', {
    p_student: studentId, p_year: yearId, p_outcome: outcome, p_reason: reason,
  })
  if (error) throw error
}

export async function confirmPromotions(yearId: string): Promise<number> {
  const { data, error } = await supabase.rpc('rpc_confirm_promotions', { p_year: yearId })
  if (error) throw error
  return data as number
}

export async function seedPromotionRules(yearId: string): Promise<number> {
  const { data, error } = await supabase.rpc('rpc_seed_promotion_rules', { p_year: yearId })
  if (error) throw error
  return data as number
}

export interface RolloverResult {
  committed: boolean
  promoted: number
  repeated: number
  left: number
  referred: number
  unplaced_count: number
  unplaced: Array<{
    student_id: string; from_grade: number; needs_grade: number; outcome: string
  }>
}

/**
 * Dry run unless `commit` is true. The RPC refuses entirely while any promotion
 * decision is unconfirmed, so the ordering the screen enforces — evaluate,
 * review, confirm, then roll over — is also enforced by the database.
 */
export async function rolloverYear(
  fromYear: string, toYear: string, commit: boolean,
): Promise<RolloverResult> {
  const { data, error } = await supabase.rpc('rpc_rollover_year', {
    p_from_year: fromYear, p_to_year: toYear, p_commit: commit,
  })
  if (error) throw error
  return data as RolloverResult
}

/**
 * Builds calendar_day rows for a year from its terms and the holiday table.
 * cycleLength is the teaching cycle (commonly 5 or 10 days) and determines the
 * cycle_day the timetable is keyed on, so it must match the timetable version.
 */
export async function generateSchoolCalendar(
  yearId: string, cycleLength: number,
): Promise<number> {
  const { data, error } = await supabase.rpc('rpc_generate_school_calendar', {
    p_year_id: yearId, p_cycle_length: cycleLength,
  })
  if (error) throw error
  return (data as number) ?? 0
}

/** Cyclone and emergency closures. Not an edge case in Mauritius. */
export async function declareClosure(
  yearId: string, date: string, reason: string,
): Promise<void> {
  const { error } = await supabase.rpc('rpc_declare_closure', {
    p_year_id: yearId, p_date: date, p_reason: reason,
  })
  if (error) throw error
}
