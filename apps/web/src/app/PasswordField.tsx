import { useEffect, useRef, useState } from 'react'
import {
  checkPwnedPassword, describePwned, localPasswordProblems, type PwnedResult,
} from '@/lib/pwned'

/**
 * A password input that checks the password against known breaches before it is
 * ever submitted.
 *
 * Only for setting or changing a password — never for signing in. On a sign-in
 * form this would be both useless (the password is already whatever it is) and
 * actively harmful, since a warning shown at the point of entry tells anyone
 * watching the screen that this account uses a known-breached password.
 */
export function PasswordField({
  value, onChange, onValidityChange, context, label = 'Password', autoComplete = 'new-password',
}: {
  value: string
  onChange: (v: string) => void
  onValidityChange?: (ok: boolean) => void
  context?: { email?: string; firstName?: string; lastName?: string; schoolName?: string }
  label?: string
  autoComplete?: string
}) {
  const [pwned, setPwned] = useState<PwnedResult | null>(null)
  const [checking, setChecking] = useState(false)
  const [show, setShow] = useState(false)
  const seq = useRef(0)

  const local = localPasswordProblems(value, context ?? {})

  useEffect(() => {
    // Debounced, and only once the password is long enough to be plausible.
    // Firing on every keystroke would send a prefix for every prefix of the
    // password, which is a great deal more information than one lookup.
    if (value.length < 8) { setPwned(null); return }

    const mine = ++seq.current
    setChecking(true)
    const t = setTimeout(async () => {
      const r = await checkPwnedPassword(value)
      // A slower earlier request must not overwrite a newer result.
      if (mine === seq.current) { setPwned(r); setChecking(false) }
    }, 600)

    return () => { clearTimeout(t); setChecking(false) }
  }, [value])

  // Unavailable is not a failure. A HIBP outage must not stop a school setting
  // a password; it downgrades to advice.
  const blocked = local.length > 0 || pwned?.breached === true

  useEffect(() => {
    onValidityChange?.(value.length > 0 && !blocked && !checking)
  }, [value, blocked, checking, onValidityChange])

  const message = pwned ? describePwned(pwned) : null

  return (
    <div>
      <label className="block text-sm font-medium">
        {label}
        <div className="relative">
          <input
            type={show ? 'text' : 'password'}
            required value={value} autoComplete={autoComplete}
            onChange={(e) => onChange(e.target.value)}
            className="mt-1 h-11 w-full rounded-lg border border-slate-300 px-3 pr-16 text-base"
          />
          <button
            type="button" onClick={() => setShow(!show)}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-xs font-medium text-slate-500"
          >
            {show ? 'Hide' : 'Show'}
          </button>
        </div>
      </label>

      {local.length > 0 && (
        <ul className="mt-2 space-y-1">
          {local.map((p) => (
            <li key={p} className="text-xs text-amber-800">{p}</li>
          ))}
        </ul>
      )}

      {checking && value.length >= 8 && (
        <p className="mt-2 text-xs text-slate-500">Checking against known breaches…</p>
      )}

      {message && (
        <p className={`mt-2 text-xs ${
          pwned?.breached ? 'font-medium text-red-700' : 'text-slate-500'
        }`}>
          {message}
        </p>
      )}

      {value.length >= 10 && !checking && pwned && !pwned.breached && !pwned.unavailable
        && local.length === 0 && (
        <p className="mt-2 text-xs text-emerald-700">
          Not found in any known breach.
        </p>
      )}

      <p className="mt-2 text-[11px] leading-relaxed text-slate-400">
        Your password is never sent anywhere. Only the first five characters of
        its hash are used to look up known breaches.
      </p>
    </div>
  )
}
