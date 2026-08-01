import { supabase } from '@/lib/supabase'

export interface Paper {
  id: string; subject_id: string; grade_level_id: string
  paper_number: number; date: string; starts_at: string
  duration_minutes: number; max_score: number | null
  subject_name?: string; grade?: number
}

export interface Candidate {
  student_id: string; first_name: string; last_name: string
  admission_number: string; class_name: string | null
  arrangement: string | null; extra_minutes: number | null; debarred: boolean
}

export interface Seat {
  room_code: string; seat_label: string; row_no: number; col_no: number
  first_name: string; last_name: string; admission_number: string
  class_name: string | null; arrangement: string | null
}

export async function fetchPapers(sessionId: string): Promise<Paper[]> {
  const { data, error } = await supabase
    .from('exam_paper')
    .select(`id,subject_id,grade_level_id,paper_number,date,starts_at,
             duration_minutes,max_score,
             subject:subject_id ( name_en ), grade_level:grade_level_id ( grade )`)
    .eq('exam_session_id', sessionId)
    .order('date').order('starts_at')
  if (error) throw error
  return (data ?? []).map((p: any) => ({
    ...p, subject_name: p.subject?.name_en, grade: p.grade_level?.grade,
  }))
}

export async function fetchCandidates(paperId: string): Promise<Candidate[]> {
  const { data, error } = await supabase.rpc('exam_candidates', { p_paper: paperId })
  if (error) throw error
  return (data ?? []) as Candidate[]
}

export async function fetchSeatingPlan(paperId: string): Promise<Seat[]> {
  const { data, error } = await supabase.rpc('seating_plan', { p_paper: paperId })
  if (error) throw error
  return (data ?? []) as Seat[]
}

export async function allocateSeats(paperId: string, strategy: string) {
  const { data, error } = await supabase.rpc('rpc_allocate_seats', {
    p_paper: paperId, p_strategy: strategy,
  })
  if (error) throw error
  return data as number
}

export async function assignInvigilators(paperId: string, perRoom: number) {
  const { data, error } = await supabase.rpc('rpc_assign_invigilators', {
    p_paper: paperId, p_per_room: perRoom,
  })
  if (error) throw error
  return data as number
}

export async function fetchDuties(paperId: string) {
  const { data, error } = await supabase
    .from('invigilation_duty')
    .select('id,role,status,room:room_id ( code ), staff:staff_id ( id )')
    .eq('exam_paper_id', paperId)
  if (error) throw error
  const ids = (data ?? []).map((d: any) => d.staff?.id).filter(Boolean)
  const { data: people } = ids.length
    ? await supabase.from('person').select('id,first_name,last_name').in('id', ids)
    : { data: [] as any[] }
  return (data ?? []).map((d: any) => {
    const p = (people ?? []).find((x: any) => x.id === d.staff?.id)
    return {
      id: d.id, role: d.role, status: d.status, room_code: d.room?.code,
      staff_name: p ? `${p.first_name} ${p.last_name}` : '—',
    }
  })
}
