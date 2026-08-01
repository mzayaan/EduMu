import { supabase } from '@/lib/supabase'

export type DiscrepancyKind =
  | 'present_on_register_absent_in_class'
  | 'absent_on_register_present_in_class'

export type Outcome =
  | 'found_on_premises'
  | 'left_school'
  | 'medical_room'
  | 'authorised'
  | 'unresolved'

export interface Discrepancy {
  id: string
  date: string
  kind: DiscrepancyKind
  detected_at: string
  resolved_at: string | null
  outcome: Outcome | null
  student_id: string
  first_name: string
  last_name: string
  preferred_name: string | null
  admission_number: string
  class_name: string | null
  subject_name: string | null
  set_name: string | null
  period_name: string | null
  period_starts_at: string | null
  reported_by_educator: string | null
  resolved_by_name: string | null
}

export async function fetchDiscrepancies(date: string): Promise<Discrepancy[]> {
  const { data, error } = await supabase
    .from('discrepancy_feed')
    .select('*')
    .eq('date', date)
    .order('detected_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as Discrepancy[]
}

/** Recorded act: stamps who decided and when, and writes to audit_log. */
export async function resolveDiscrepancy(id: string, outcome: Outcome) {
  const { error } = await supabase.rpc('rpc_resolve_discrepancy', {
    p_id: id, p_outcome: outcome,
  })
  if (error) throw error
}
