import { supabase } from '@/lib/supabase'

export type AssessmentStatus = 'draft' | 'open' | 'submitted' | 'moderated' | 'published'
export type MarkCode = 'ABS' | 'EXEMPT' | 'MED' | 'DEBARRED'

export interface MarksheetRow {
  student_id: string
  first_name: string
  last_name: string
  preferred_name: string | null
  admission_number: string
  assessment_id: string
  title: string
  kind: string
  max_score: number
  weight: number
  status: AssessmentStatus
  mark_id: string | null
  score: number | null
  code: MarkCode | null
}

export interface TeachingSet {
  id: string
  name: string
  subject_id: string
}

export async function fetchMySets(): Promise<TeachingSet[]> {
  // RLS limits subject_set to the caller's school; set_educator narrows to theirs.
  const { data, error } = await supabase
    .from('set_educator')
    .select('subject_set:subject_set_id ( id, name, subject_id )')
  if (error) throw error
  return (data ?? [])
    .map((r: any) => r.subject_set)
    .filter(Boolean)
    .sort((a: TeachingSet, b: TeachingSet) => a.name.localeCompare(b.name))
}

export async function fetchMarksheet(setId: string, termId: string | null) {
  const { data, error } = await supabase.rpc('set_marksheet', {
    p_set: setId, p_term: termId,
  })
  if (error) throw error
  return (data ?? []) as MarksheetRow[]
}

export async function fetchTerms() {
  const { data, error } = await supabase
    .from('term')
    .select('id,name,sequence,starts_on,ends_on')
    .order('sequence')
  if (error) throw error
  return data ?? []
}

export async function setAssessmentStatus(id: string, status: AssessmentStatus) {
  const { error } = await supabase.rpc('rpc_set_assessment_status', {
    p_assessment: id, p_status: status,
  })
  if (error) throw error
}

export async function computeTermResults(termId: string) {
  const { data, error } = await supabase.rpc('rpc_compute_term_results', {
    p_term: termId,
  })
  if (error) throw error
  return data as number
}
