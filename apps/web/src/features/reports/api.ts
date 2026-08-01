import { supabase } from '@/lib/supabase'
// The card's shape is defined alongside the component that renders it.
// Imported for local use in signatures, and re-exported for callers.
import type { CardData } from './ReportCard'

export type { CardData, Column, SubjectRow } from './ReportCard'

export async function buildReportCards(termId: string) {
  const { data, error } = await supabase.rpc('rpc_build_report_cards', { p_term: termId })
  if (error) throw error
  return data as number
}

export async function publishReportCards(termId: string) {
  const { data, error } = await supabase.rpc('rpc_publish_report_cards', { p_term: termId })
  if (error) throw error
  return data as number
}

export async function fetchCard(termId: string, studentId: string): Promise<CardData | null> {
  const { data, error } = await supabase.rpc('report_card_data', {
    p_term: termId, p_student: studentId,
  })
  if (error) throw error
  return data as CardData | null
}

export async function fetchCardList(termId: string) {
  const { data, error } = await supabase
    .from('report_card')
    .select('student_id,overall_score,overall_rank,class_size,attendance_pct,status,form_teacher_comment')
    .eq('term_id', termId)
    .order('overall_rank')
  if (error) throw error
  const ids = (data ?? []).map((r: any) => r.student_id)
  if (ids.length === 0) return []
  const { data: pupils } = await supabase
    .from('class_roster')
    .select('student_id,first_name,last_name,preferred_name,admission_number,class_name')
    .in('student_id', ids)
  return (data ?? []).map((r: any) => ({
    ...r, ...((pupils ?? []).find((p: any) => p.student_id === r.student_id) ?? {}),
  }))
}

export async function setComment(
  termId: string, studentId: string, which: 'form_teacher' | 'rector', comment: string,
) {
  const { error } = await supabase.rpc('rpc_set_report_comment', {
    p_term: termId, p_student: studentId, p_which: which, p_comment: comment,
  })
  if (error) throw error
}
