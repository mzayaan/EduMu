import { supabase } from '@/lib/supabase'
import type { SolverInput } from '@edumu/domain'

export interface PeriodDef {
  id: string; sequence: number; name: string
  starts_at: string; ends_at: string; is_teaching: boolean
}
export interface Version {
  id: string; version: number; label: string | null
  cycle_length: number; status: 'draft' | 'published' | 'superseded'
  effective_from: string
}

export async function fetchVersions(): Promise<Version[]> {
  const { data, error } = await supabase
    .from('timetable_version')
    .select('id,version,label,cycle_length,status,effective_from')
    .order('version', { ascending: false })
  if (error) throw error
  return data ?? []
}

export async function fetchPeriods(versionId: string): Promise<PeriodDef[]> {
  const { data, error } = await supabase
    .from('period_definition')
    .select('id,sequence,name,starts_at,ends_at,is_teaching')
    .eq('timetable_version_id', versionId)
    .order('sequence')
  if (error) throw error
  return data ?? []
}

export async function fetchSolverInputs(yearId: string) {
  const { data, error } = await supabase.rpc('timetable_inputs', { p_year: yearId })
  if (error) throw error
  return data as Omit<SolverInput, 'cycleLength' | 'periods'>
}

export async function fetchSlots(versionId: string) {
  const { data, error } = await supabase
    .from('timetable_slot')
    .select(`id,cycle_day,period_id,subject_set_id,room_id,staff_id,
             subject_set:subject_set_id ( name ), room:room_id ( code )`)
    .eq('timetable_version_id', versionId)
  if (error) throw error
  return (data ?? []).map((s: any) => ({
    ...s, set_name: s.subject_set?.name, room_code: s.room?.code,
  }))
}

export async function applyTimetable(versionId: string, placements: any[]) {
  const { data, error } = await supabase.rpc('rpc_apply_timetable', {
    p_version: versionId, p_placements: placements,
  })
  if (error) throw error
  return data as number
}

export async function publishTimetable(versionId: string, from: string) {
  const { error } = await supabase.rpc('rpc_publish_timetable', {
    p_version: versionId, p_from: from,
  })
  if (error) throw error
}

export async function fetchUncovered(date: string) {
  const { data, error } = await supabase.rpc('uncovered_lessons', { p_date: date })
  if (error) throw error
  return data ?? []
}

export async function fetchSubstitutes(date: string, slotId: string) {
  const { data, error } = await supabase.rpc('substitute_candidates', {
    p_date: date, p_slot: slotId,
  })
  if (error) throw error
  return data ?? []
}

export async function assignSubstitute(v: {
  school_id: string; date: string; timetable_slot_id: string
  absent_staff_id: string; substitute_staff_id: string
}) {
  const { error } = await supabase
    .from('lesson_substitution')
    .upsert(v, { onConflict: 'date,timetable_slot_id' })
  if (error) throw error
}
