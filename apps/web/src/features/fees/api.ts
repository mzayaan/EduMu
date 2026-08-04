import { supabase } from '@/lib/supabase'

/**
 * Fees — DEMONSTRATION ONLY.
 *
 * Nothing here processes a payment. The guardian pays the school by MCB Juice
 * out-of-band, screenshots the confirmation, and uploads it; somebody at the
 * school opens their bank app and confirms the money arrived. Every function
 * below is filing, not finance.
 */

export type PaymentMethod = 'mcb_juice' | 'bank_transfer' | 'cash' | 'cheque' | 'waiver'
export type PaymentStatus = 'awaiting_verification' | 'verified' | 'rejected'

export interface StatementRow {
  charge_id: string
  student_id: string
  first_name: string
  last_name: string
  admission_number: string | null
  description: string
  amount: number
  due_on: string | null
  waived: boolean
  waived_reason: string | null
  paid: number
  pending: number
  balance: number
}

export interface PaymentRow {
  id: string
  student_id: string
  fee_charge_id: string | null
  amount: number
  paid_on: string
  method: PaymentMethod
  reference: string | null
  proof_path: string | null
  status: PaymentStatus
  submitted_at: string
  decision_note: string | null
}

export async function fetchStatement(studentId?: string): Promise<StatementRow[]> {
  let q = supabase.from('fee_statement').select('*').order('due_on', { nullsFirst: false })
  if (studentId) q = q.eq('student_id', studentId)
  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as StatementRow[]
}

export async function fetchPayments(status?: PaymentStatus): Promise<PaymentRow[]> {
  let q = supabase
    .from('fee_payment')
    .select('id,student_id,fee_charge_id,amount,paid_on,method,reference,proof_path,status,submitted_at,decision_note')
    .order('submitted_at', { ascending: false })
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as PaymentRow[]
}

/**
 * Uploads the MCB Juice screenshot.
 *
 * Path is `{school_id}/fees/{student_id}/…` so the existing storage RLS
 * helpers apply unchanged — the bucket policy resolves the school from the
 * first path segment, and getting that wrong is how a file ends up readable by
 * the wrong tenant.
 */
export async function uploadProof(
  schoolId: string, studentId: string, file: File,
): Promise<string> {
  const ext = file.name.split('.').pop()?.toLowerCase() ?? 'png'
  const path = `${schoolId}/fees/${studentId}/${crypto.randomUUID()}.${ext}`
  const { error } = await supabase.storage
    .from('fee-proofs')
    .upload(path, file, { contentType: file.type, upsert: false })
  if (error) throw error
  return path
}

export async function proofUrl(path: string): Promise<string | null> {
  // Signed rather than public: a payment screenshot shows a family's bank
  // balance and their name.
  const { data, error } = await supabase.storage
    .from('fee-proofs').createSignedUrl(path, 300)
  if (error) return null
  return data?.signedUrl ?? null
}

export async function submitPayment(v: {
  studentId: string
  chargeId: string | null
  amount: number
  paidOn: string
  method: PaymentMethod
  reference?: string
  proofPath?: string
}): Promise<string> {
  const { data, error } = await supabase.rpc('rpc_submit_fee_payment', {
    p_student: v.studentId, p_charge: v.chargeId, p_amount: v.amount,
    p_paid_on: v.paidOn, p_method: v.method,
    p_reference: v.reference ?? null, p_proof_path: v.proofPath ?? null,
  })
  if (error) throw error
  return data as string
}

/** The only step with financial meaning, and a human makes it. */
export async function verifyPayment(
  paymentId: string, verified: boolean, note?: string,
): Promise<void> {
  const { error } = await supabase.rpc('rpc_verify_fee_payment', {
    p_payment: paymentId, p_verified: verified, p_note: note ?? null,
  })
  if (error) throw error
}

export async function waiveFee(chargeId: string, reason: string): Promise<void> {
  const { error } = await supabase.rpc('rpc_waive_fee', {
    p_charge: chargeId, p_reason: reason,
  })
  if (error) throw error
}

export async function generateCharges(yearId: string): Promise<number> {
  const { data, error } = await supabase.rpc('rpc_generate_fee_charges', { p_year: yearId })
  if (error) throw error
  return data as number
}

export interface FeeStructure {
  id: string
  grade: number | null
  name: string
  amount: number
  due_on: string | null
  is_mandatory: boolean
  is_active: boolean
}

export async function fetchStructures(yearId: string): Promise<FeeStructure[]> {
  const { data, error } = await supabase
    .from('fee_structure')
    .select('id,grade,name,amount,due_on,is_mandatory,is_active')
    .eq('academic_year_id', yearId)
    .order('grade', { nullsFirst: true })
  if (error) throw error
  return (data ?? []) as FeeStructure[]
}

export async function addStructure(v: {
  schoolId: string; yearId: string; grade: number | null
  name: string; amount: number; dueOn: string | null; mandatory: boolean
}): Promise<void> {
  const { error } = await supabase.from('fee_structure').insert({
    school_id: v.schoolId, academic_year_id: v.yearId, grade: v.grade,
    name: v.name, amount: v.amount, due_on: v.dueOn, is_mandatory: v.mandatory,
  })
  if (error) throw error
}

export const rupees = (n: number) =>
  new Intl.NumberFormat('en-MU', { style: 'currency', currency: 'MUR' }).format(n)
