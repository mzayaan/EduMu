import { supabase } from '@/lib/supabase'

export type PlanStatus =
  | 'draft' | 'submitted' | 'hod_returned' | 'hod_approved' | 'rector_approved'

export interface SchemeRow {
  subject_set_id: string; set_name: string; subject_name: string
  staff_id: string; staff_name: string; department: string | null
  scheme_id: string | null; status: PlanStatus; due_on: string | null
  hod_comment: string | null; weeks: number
}

export interface SchemeWeek {
  id: string; week_no: number
  objectives: string | null; activities: string | null
  resources: string | null; assessment_strategy: string | null
  revision_notes: string | null
}

export async function fetchSchemeStatus(termId: string): Promise<SchemeRow[]> {
  const { data, error } = await supabase.rpc('scheme_status', { p_term: termId })
  if (error) throw error
  return (data ?? []) as SchemeRow[]
}

export async function ensureScheme(v: {
  school_id: string; academic_year_id: string
  subject_set_id: string; staff_id: string; term_id: string; due_on: string | null
}) {
  const { data, error } = await supabase
    .from('scheme_of_work')
    .upsert(v, { onConflict: 'subject_set_id,term_id' })
    .select('id').single()
  if (error) throw error
  return data.id as string
}

export async function fetchWeeks(schemeId: string): Promise<SchemeWeek[]> {
  const { data, error } = await supabase
    .from('scheme_week')
    .select('id,week_no,objectives,activities,resources,assessment_strategy,revision_notes')
    .eq('scheme_of_work_id', schemeId)
    .order('week_no')
  if (error) throw error
  return data ?? []
}

export async function saveWeek(v: {
  school_id: string; scheme_of_work_id: string; week_no: number
  objectives?: string; activities?: string; resources?: string
  assessment_strategy?: string; revision_notes?: string
}) {
  const { error } = await supabase
    .from('scheme_week')
    .upsert(v, { onConflict: 'scheme_of_work_id,week_no' })
  if (error) throw error
}

export async function submitScheme(id: string) {
  const { error } = await supabase.rpc('rpc_submit_scheme', { p_scheme: id })
  if (error) throw error
}
export async function reviewScheme(id: string, approve: boolean, comment?: string) {
  const { error } = await supabase.rpc('rpc_review_scheme', {
    p_scheme: id, p_approve: approve, p_comment: comment ?? null,
  })
  if (error) throw error
}
export async function approveScheme(id: string) {
  const { error } = await supabase.rpc('rpc_approve_scheme', { p_scheme: id })
  if (error) throw error
}

export async function generateWeeklyPlan(setId: string, weekStart: string) {
  const { data, error } = await supabase.rpc('rpc_generate_weekly_plan', {
    p_set: setId, p_week_start: weekStart,
  })
  if (error) throw error
  return data as number
}

export async function fetchWeeklyPlan(setId: string, weekStart: string) {
  const { data, error } = await supabase
    .from('weekly_plan')
    .select(`id, weekly_plan_row ( id, date, planned, actual, remarks, covered )`)
    .eq('subject_set_id', setId).eq('week_start', weekStart)
    .maybeSingle()
  if (error) throw error
  if (!data) return null
  return {
    id: data.id,
    rows: ((data as any).weekly_plan_row ?? []).sort(
      (a: any, b: any) => a.date.localeCompare(b.date)),
  }
}

export async function savePlanRow(id: string, planned: string) {
  const { error } = await supabase
    .from('weekly_plan_row').update({ planned }).eq('id', id)
  if (error) throw error
}

/** Recording what was actually covered is the earliest slippage signal. */
export async function recordCoverage(
  id: string, actual: string, covered: boolean, remarks?: string,
) {
  const { error } = await supabase.rpc('rpc_record_coverage', {
    p_row: id, p_actual: actual, p_covered: covered, p_remarks: remarks ?? null,
  })
  if (error) throw error
}

export async function fetchCoverage() {
  const { data, error } = await supabase
    .from('syllabus_coverage')
    .select('subject_set_id,set_name,subject_name,term_name,periods_recorded,periods_covered,coverage_pct')
    .order('coverage_pct', { nullsFirst: false })
  if (error) throw error
  return data ?? []
}

export async function fetchHomework(setId: string) {
  const { data, error } = await supabase
    .from('homework')
    .select('id,title,description,set_on,due_on,estimated_minutes')
    .eq('subject_set_id', setId)
    .order('due_on', { ascending: false })
  if (error) throw error
  return data ?? []
}

export async function setHomework(v: {
  school_id: string; subject_set_id: string; set_by: string
  title: string; description: string; due_on: string; estimated_minutes: number
}) {
  const { error } = await supabase.from('homework').insert(v)
  if (error) throw error
}
