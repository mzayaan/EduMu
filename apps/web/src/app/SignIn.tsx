import { useState, type FormEvent } from 'react'
import { supabase } from '@/lib/supabase'

export function SignIn() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function submit(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) setError(error.message)
    setBusy(false)
  }

  return (
    <div className="grid min-h-dvh place-items-center bg-slate-50 p-6">
      <form onSubmit={submit} className="w-full max-w-sm rounded-xl bg-white p-6 shadow-sm">
        <p className="text-2xl font-semibold tracking-tight text-brand">EduMU</p>
        <p className="mt-1 text-sm text-slate-500">Sign in to your school account</p>

        <label className="mt-6 block text-sm font-medium">
          Email
          <input
            type="email" required value={email} autoComplete="username"
            onChange={(e) => setEmail(e.target.value)}
            className="mt-1 h-11 w-full rounded-lg border border-slate-300 px-3 text-base"
          />
        </label>

        <label className="mt-4 block text-sm font-medium">
          Password
          <input
            type="password" required value={password} autoComplete="current-password"
            onChange={(e) => setPassword(e.target.value)}
            className="mt-1 h-11 w-full rounded-lg border border-slate-300 px-3 text-base"
          />
        </label>

        {error && <p className="mt-3 text-sm text-absent">{error}</p>}

        <button
          type="submit" disabled={busy}
          className="mt-6 h-11 w-full rounded-lg bg-brand font-semibold text-white disabled:opacity-50"
        >
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
    </div>
  )
}
