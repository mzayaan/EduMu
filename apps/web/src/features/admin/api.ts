import { supabase } from '@/lib/supabase'

const list = async (table: string, select: string, order: string, asc = false) => {
  const { data, error } = await supabase.from(table).select(select)
    .order(order, { ascending: asc }).limit(100)
  if (error) throw error
  return data ?? []
}

export const fetchAssets = () =>
  list('asset', 'id,tag,name,category,condition,status,room:room_id ( code )', 'tag', true)

export const fetchMaintenance = () =>
  list('maintenance_request',
       'id,description,priority,status,reported_on,completed_on,room:room_id ( code )',
       'reported_on')

export const fetchLibraryLoans = () =>
  list('library_loan',
       'id,out_on,due_on,returned_on,student_id,library_item:library_item_id ( title, author )',
       'due_on', true)

export const fetchVisitors = () =>
  list('visitor_log', 'id,name,organisation,purpose,signed_in_at,signed_out_at,badge_no',
       'signed_in_at')

export const fetchHealth = () =>
  list('health_record',
       'id,student_id,kind,occurred_at,description,action_taken,sent_home,guardian_notified_at',
       'occurred_at')

export const fetchNotices = () =>
  list('notice', 'id,title,body,publish_at,expires_at,pinned', 'publish_at')

export const fetchCirculars = () =>
  list('circular', 'id,reference,issued_on,source,subject,target_roles', 'issued_on')

export const fetchCorrespondence = () =>
  list('correspondence',
       'id,direction,dated_on,counterparty,subject,abc_code,unique_file_number,status,due_on',
       'dated_on')

export const fetchWaterCerts = () =>
  list('water_quality_certificate', 'id,issued_on,expires_on,tanks_cleaned_on,issued_by_body',
       'issued_on')

export async function createMaintenance(v: {
  school_id: string; reported_by: string; description: string; priority: string
}) {
  const { error } = await supabase.from('maintenance_request').insert(v)
  if (error) throw error
}

export async function completeMaintenance(id: string) {
  const { error } = await supabase.from('maintenance_request')
    .update({ status: 'completed', completed_on: new Date().toISOString().slice(0, 10) })
    .eq('id', id)
  if (error) throw error
}

export async function signInVisitor(v: {
  school_id: string; name: string; organisation: string; purpose: string; badge_no: string
}) {
  const { error } = await supabase.from('visitor_log').insert(v)
  if (error) throw error
}

export async function signOutVisitor(id: string) {
  const { error } = await supabase.from('visitor_log')
    .update({ signed_out_at: new Date().toISOString() }).eq('id', id)
  if (error) throw error
}

export async function publishNotice(v: {
  school_id: string; title: string; body: string; created_by: string; pinned: boolean
}) {
  const { error } = await supabase.from('notice').insert(v)
  if (error) throw error
}

export async function logCorrespondence(v: {
  school_id: string; direction: string; counterparty: string; subject: string
  abc_code: string; unique_file_number: number | null
}) {
  const { error } = await supabase.from('correspondence').insert(v)
  if (error) throw error
}

export async function returnLoan(id: string) {
  const { error } = await supabase.from('library_loan')
    .update({ returned_on: new Date().toISOString().slice(0, 10) }).eq('id', id)
  if (error) throw error
}
