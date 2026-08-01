import { useEffect, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { readClaims, supabase, type EduClaims } from '@/lib/supabase'
import { startOutboxSync } from '@/lib/outbox'
import { Shell } from '@/app/Shell'
import { SignIn } from '@/app/SignIn'

export function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [claims, setClaims] = useState<EduClaims>({})
  const [ready, setReady] = useState(false)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setClaims(readClaims(data.session?.access_token))
      setReady(true)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => {
      setSession(s)
      setClaims(readClaims(s?.access_token))
    })
    startOutboxSync()
    return () => sub.subscription.unsubscribe()
  }, [])

  if (!ready) return <Splash />
  if (!session) return <SignIn />

  if (!claims.school_id) {
    return (
      <Splash>
        <p className="text-sm text-slate-600">
          This account is signed in but is not linked to a school record yet.
        </p>
        <button
          onClick={() => supabase.auth.signOut()}
          className="mt-4 text-sm font-medium text-brand underline"
        >
          Sign out
        </button>
      </Splash>
    )
  }

  return <Shell claims={claims} />
}

function Splash({ children }: { children?: ReactNode }) {
  return (
    <div className="grid min-h-dvh place-items-center bg-slate-50 p-6 text-center">
      <div>
        <p className="text-2xl font-semibold tracking-tight text-brand">EduMU</p>
        {children ?? <p className="mt-2 text-sm text-slate-400">Loading…</p>}
      </div>
    </div>
  )
}
