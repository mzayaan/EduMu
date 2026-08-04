import { useEffect, useState, type FormEvent } from 'react'
import { supabase } from '@/lib/supabase'
import { PasswordField } from './PasswordField'

/**
 * Change your own password, with the breach check applied.
 *
 * This is where leaked-password protection belongs. On the sign-in form it
 * would be useless — the password is already whatever it is — and worse than
 * useless, because a "this password has been breached" warning appearing as
 * someone signs in announces that fact to anyone looking at the screen.
 */
export function ChangePassword({ onDone }: { onDone?: () => void }) {
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [ok, setOk] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [done, setDone] = useState(false)
  // The email is not in our JWT claims — it lives on the auth user. Needed so
  // the local checks can refuse a password built out of the person's own
  // address, which is one of the most common weak choices.
  const [email, setEmail] = useState<string | undefined>()

  useEffect(() => {
    void supabase.auth.getUser().then(({ data }) => setEmail(data.user?.email ?? undefined))
  }, [])

  const mismatch = confirm.length > 0 && confirm !== password

  async function submit(e: FormEvent) {
    e.preventDefault()
    if (!ok || mismatch) return
    setBusy(true)
    setError(null)

    const { error } = await supabase.auth.updateUser({ password })
    if (error) setError(error.message)
    else {
      setDone(true)
      setPassword(''); setConfirm('')
      onDone?.()
    }
    setBusy(false)
  }

  if (done) {
    return (
      <div className="rounded-lg border border-emerald-200 bg-emerald-50 p-4">
        <p className="text-sm font-medium text-emerald-900">Password changed.</p>
        <p className="mt-1 text-xs text-emerald-800">
          Sign in with the new password next time.
        </p>
      </div>
    )
  }

  return (
    <form onSubmit={submit} className="max-w-sm space-y-4">
      <PasswordField
        label="New password"
        value={password}
        onChange={setPassword}
        onValidityChange={setOk}
        context={{ email }}
      />

      <label className="block text-sm font-medium">
        Confirm
        <input
          type="password" required value={confirm} autoComplete="new-password"
          onChange={(e) => setConfirm(e.target.value)}
          className="mt-1 h-11 w-full rounded-lg border border-slate-300 px-3 text-base"
        />
      </label>
      {mismatch && <p className="text-xs text-amber-800">The two passwords do not match.</p>}

      {error && <p className="text-sm text-absent">{error}</p>}

      <button
        type="submit" disabled={busy || !ok || mismatch}
        className="h-11 w-full rounded-lg bg-brand font-semibold text-white disabled:opacity-50"
      >
        {busy ? 'Changing…' : 'Change password'}
      </button>
    </form>
  )
}
