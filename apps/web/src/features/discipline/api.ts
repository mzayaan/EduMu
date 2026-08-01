import { supabase } from '@/lib/supabase'

export const INCIDENT_CATEGORIES = [
  'Uniform', 'Punctuality', 'Mobile phone', 'Bullying or extortion',
  'Damage to property', 'Absconding', 'Violence', 'Prohibited substances',
  'Academic dishonesty', 'Disrespect to staff', 'Other',
] as const

export const MERIT_KINDS = [
  { value: 'commendation', label: 'Commendation' },
  { value: 'bonus_marks', label: 'Bonus marks' },
  { value: 'responsibility', label: 'Given responsibility' },
  { value: 'good_behaviour_certificate', label: 'Good behaviour certificate' },
  { value: 'award', label: 'Award' },
] as const

export type Severity = 'minor' | 'moderate' | 'serious' | 'grave'
export type Stage =
  | 'form_teacher' | 'parent_contact' | 'special_report'
  | 'pastoral' | 'disciplinary_committee' | 'closed'

export async function searchPupils(q: string) {
  let query = supabase
    .from('class_roster')
    .select('student_id,first_name,last_name,preferred_name,admission_number,class_name')
    .limit(20)
  if (q.trim()) {
    query = query.or(
      `first_name.ilike.%${q}%,last_name.ilike.%${q}%,admission_number.ilike.%${q}%`,
    )
  }
  const { data, error } = await query
  if (error) throw error
  return data ?? []
}

export async function createIncident(v: {
  school_id: string
  academic_year_id: string
  reported_by: string
  category: string
  severity: Severity
  location?: string
  description: string
  witnesses?: string
  student_ids: string[]
}) {
  const { student_ids, ...incident } = v
  const { data, error } = await supabase
    .from('incident').insert(incident).select('id').single()
  if (error) throw error

  const { error: e2 } = await supabase.from('incident_student').insert(
    student_ids.map((id) => ({
      incident_id: data.id, student_id: id, involvement: 'perpetrator',
    })),
  )
  if (e2) throw e2
  return data.id as string
}

export async function fetchIncidents() {
  const { data, error } = await supabase
    .from('incident')
    .select('id,occurred_at,category,severity,description,location,status,reported_by')
    .order('occurred_at', { ascending: false })
    .limit(50)
  if (error) throw error
  return data ?? []
}

export async function fetchIncidentPupils(incidentIds: string[]) {
  if (incidentIds.length === 0) return []
  const { data, error } = await supabase
    .from('incident_student')
    .select('incident_id,student_id,involvement')
    .in('incident_id', incidentIds)
  if (error) throw error
  return data ?? []
}

export async function awardMerit(v: {
  school_id: string; student_id: string; kind: string; reason: string
}) {
  const { error } = await supabase.from('merit').insert(v)
  if (error) throw error
}

export async function fetchMerits() {
  const { data, error } = await supabase
    .from('merit')
    .select('id,student_id,kind,reason,awarded_on')
    .order('awarded_on', { ascending: false })
    .limit(50)
  if (error) throw error
  return data ?? []
}

export async function openCase(v: { school_id: string; student_id: string }) {
  const { data, error } = await supabase
    .from('disciplinary_case').insert(v).select('id').single()
  if (error) throw error
  return data.id as string
}

export async function fetchCases() {
  const { data, error } = await supabase
    .from('disciplinary_case')
    .select('id,student_id,opened_on,stage,decision,closed_on')
    .order('opened_on', { ascending: false })
  if (error) throw error
  return data ?? []
}

/** Escalation records an occurrence-log entry and notifies the Responsible Party. */
export async function escalateCase(caseId: string, stage: Stage, note?: string) {
  const { error } = await supabase.rpc('rpc_escalate_case', {
    p_case: caseId, p_stage: stage, p_note: note ?? null,
  })
  if (error) throw error
}

export async function appendOccurrence(v: {
  school_id: string; entered_by: string; category: string; entry: string
}) {
  const { error } = await supabase.from('occurrence_log').insert({
    ...v, occurred_at: new Date().toISOString(),
  })
  if (error) throw error
}

export async function fetchOccurrences() {
  const { data, error } = await supabase
    .from('occurrence_log')
    .select('id,occurred_at,entered_at,category,entry,corrects_entry_id')
    .order('occurred_at', { ascending: false })
    .limit(100)
  if (error) throw error
  return data ?? []
}
