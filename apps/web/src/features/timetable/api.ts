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

// ─────────────────────────────────────────────────────── manual editing

export interface UnplacedLesson {
  subject_set_id: string
  set_name: string
  subject_name: string
  required: number
  placed: number
  outstanding: number
  required_room_type: string | null
  size: number
}

/** What the solver could not fit — surfaced, never silently dropped. */
export async function fetchUnplaced(versionId: string): Promise<UnplacedLesson[]> {
  const { data, error } = await supabase.rpc('unplaced_lessons', { p_version: versionId })
  if (error) throw error
  return (data ?? []) as UnplacedLesson[]
}

/**
 * Move one lesson — a targeted update rather than rewriting the version.
 *
 * The three hard constraints live in the database: unique indexes for room and
 * staff clashes, and a trigger for the pupil clash that no index can express.
 * A bad drop is refused there, so a wrong prediction in the UI is a cosmetic
 * bug rather than a corrupt timetable.
 */
export async function moveSlot(slotId: string, cycleDay: number, periodId: string) {
  const { error } = await supabase.rpc('rpc_move_timetable_slot', {
    p_slot: slotId, p_cycle_day: cycleDay, p_period: periodId, p_room: null,
  })
  if (error) throw error
}

export async function placeLesson(
  versionId: string, setId: string, cycleDay: number, periodId: string,
) {
  const { error } = await supabase.rpc('rpc_place_lesson', {
    p_version: versionId, p_set: setId,
    p_cycle_day: cycleDay, p_period: periodId, p_room: null,
  })
  if (error) throw error
}

/** Returns a lesson to the unplaced tray rather than deleting the requirement. */
export async function removeLesson(slotId: string) {
  const { error } = await supabase.rpc('rpc_remove_lesson', { p_slot: slotId })
  if (error) throw error
}
