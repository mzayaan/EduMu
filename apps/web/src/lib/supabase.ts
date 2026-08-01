import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

if (!url || !key) {
  throw new Error('Missing VITE_SUPABASE_URL or VITE_SUPABASE_PUBLISHABLE_KEY')
}

export const supabase = createClient(url, key, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    // Shared staff-room machines: never leave a session lying around in a tab
    // the next teacher inherits.
    storageKey: 'edumu.auth',
  },
})

/** Claims packed into the JWT by app.custom_access_token_hook. */
export interface EduClaims {
  school_id?: string
  person_id?: string
  person_type?: 'staff' | 'student' | 'guardian'
  year_id?: string
  roles?: { c: string; s: string; id?: string }[]
  caps?: string[]
}

export function readClaims(accessToken: string | undefined): EduClaims {
  if (!accessToken) return {}
  try {
    const payload = accessToken.split('.')[1]
    if (!payload) return {}
    return JSON.parse(atob(payload.replace(/-/g, '+').replace(/_/g, '/')))
  } catch {
    return {}
  }
}

export const hasCap = (claims: EduClaims, cap: string) =>
  Boolean(claims.caps?.includes(cap))

/**
 * Scope ids for a role the caller holds, e.g. the class_group ids they are
 * Form Teacher of. Used to narrow the UI; RLS is what actually enforces it.
 */
export const roleScopeIds = (claims: EduClaims, roleCode: string): string[] =>
  (claims.roles ?? [])
    .filter((r) => r.c === roleCode && r.id)
    .map((r) => r.id as string)
