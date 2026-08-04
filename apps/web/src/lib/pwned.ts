/**
 * Leaked-password protection, implemented ourselves.
 *
 * WHY THIS EXISTS
 * ---------------
 * Supabase ships this as a built-in Auth setting, but it is **Pro plan and
 * above**. This project runs on the free tier, so the toggle is not available.
 *
 * The service behind it — HaveIBeenPwned's Pwned Passwords range API — is free,
 * public, and needs no API key. So the protection is available to us; only the
 * dashboard switch is not.
 *
 * If the project ever moves to Pro, prefer the built-in: it runs server-side at
 * the Auth layer and therefore also covers password changes made through the
 * API, which this cannot. Delete this file at that point rather than running
 * both — two checks that can disagree are worse than one.
 *
 * K-ANONYMITY — WHY THE PASSWORD IS NOT SENT ANYWHERE
 * ---------------------------------------------------
 * We SHA-1 the password locally, send only the **first five hex characters** of
 * the hash, and HIBP returns every suffix it holds for that prefix — around 500
 * to 1,000 hashes. We compare locally.
 *
 * So HIBP learns five hex characters of a hash. It never sees the password, the
 * full hash, the email, or which of the returned suffixes matched. Roughly one
 * in a million passwords shares a prefix, so the prefix alone identifies
 * nothing.
 *
 * SHA-1 is not a security choice here. It is the algorithm HIBP's corpus is
 * indexed by, and it is being used as a lookup key against a public list of
 * already-leaked passwords, not to protect anything.
 */

const HIBP_RANGE = 'https://api.pwnedpasswords.com/range/'

async function sha1Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input)
  const digest = await crypto.subtle.digest('SHA-1', bytes)
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
    .toUpperCase()
}

export interface PwnedResult {
  /** True only when we positively confirmed the password appears in a breach. */
  breached: boolean
  /** How many times HIBP has seen it. Useful for wording the warning. */
  count: number
  /**
   * True when the check could not be completed — offline, blocked, HIBP down.
   *
   * Callers must treat this as "unknown", never as "safe" and never as
   * "breached". Failing closed would lock a Mauritian school out of its own
   * system during an outage on the other side of the world; failing open and
   * calling it safe would be a lie. Unknown is the honest third state.
   */
  unavailable: boolean
}

export async function checkPwnedPassword(
  password: string,
  opts: { timeoutMs?: number } = {},
): Promise<PwnedResult> {
  if (!password) return { breached: false, count: 0, unavailable: false }

  // crypto.subtle is unavailable on insecure origins. Rather than silently
  // skipping the check, say so.
  if (typeof crypto === 'undefined' || !crypto.subtle) {
    return { breached: false, count: 0, unavailable: true }
  }

  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? 4000)

  try {
    const hash = await sha1Hex(password)
    const prefix = hash.slice(0, 5)
    const suffix = hash.slice(5)

    const res = await fetch(`${HIBP_RANGE}${prefix}`, {
      signal: controller.signal,
      // Pads the response with random hashes so its SIZE leaks nothing either.
      headers: { 'Add-Padding': 'true' },
    })
    if (!res.ok) return { breached: false, count: 0, unavailable: true }

    const text = await res.text()
    for (const line of text.split('\n')) {
      const [candidate, countRaw] = line.trim().split(':')
      if (candidate === suffix) {
        const count = Number(countRaw ?? 0)
        // Padding entries are returned with a count of 0 and are not real hits.
        if (count > 0) return { breached: true, count, unavailable: false }
      }
    }
    return { breached: false, count: 0, unavailable: false }
  } catch {
    return { breached: false, count: 0, unavailable: true }
  } finally {
    clearTimeout(timer)
  }
}

/**
 * Local checks, run before the network one so an obviously weak password is
 * rejected without a round trip.
 *
 * Deliberately not a "strength meter". Composition rules (one uppercase, one
 * symbol) mostly produce `Password1!` and a sticky note on the monitor. Length
 * and not-already-breached are the two that actually correlate with safety.
 */
export function localPasswordProblems(password: string, context: {
  email?: string
  firstName?: string
  lastName?: string
  schoolName?: string
} = {}): string[] {
  const problems: string[] = []
  const lower = password.toLowerCase()

  if (password.length < 10) {
    problems.push('Use at least 10 characters. Length matters more than symbols.')
  }
  if (/^\d+$/.test(password)) {
    problems.push('Digits alone are guessed almost instantly.')
  }
  if (/^(.)\1+$/.test(password)) {
    problems.push('That is a single repeated character.')
  }

  // Anything guessable from the person's own account page.
  const local = context.email?.split('@')[0]
  for (const [label, value] of [
    ['your email', local],
    ['your first name', context.firstName],
    ['your surname', context.lastName],
    ['the school name', context.schoolName],
  ] as const) {
    if (value && value.length >= 4 && lower.includes(value.toLowerCase())) {
      problems.push(`Do not include ${label} in your password.`)
    }
  }

  return problems
}

/** Wording for the UI. Kept here so every screen phrases it the same way. */
export function describePwned(r: PwnedResult): string | null {
  if (r.unavailable) {
    return 'Could not check this password against known breaches right now. ' +
      'You can continue, but choose a password you use nowhere else.'
  }
  if (!r.breached) return null
  return r.count > 100_000
    ? `This password appears in ${r.count.toLocaleString()} known data breaches. ` +
      'Attackers try these first. Please choose a different one.'
    : `This password has appeared in a known data breach (${r.count.toLocaleString()} ` +
      'times). Please choose a different one.'
}
