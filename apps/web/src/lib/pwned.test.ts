import { describe, expect, it, vi, afterEach } from 'vitest'
import { checkPwnedPassword, describePwned, localPasswordProblems } from './pwned'

afterEach(() => { vi.restoreAllMocks() })

// SHA-1("password") = 5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8
const PASSWORD_PREFIX = '5BAA6'
const PASSWORD_SUFFIX = '1E4C9B93F3F0682250B6CF8331B7EE68FD8'

function mockRange(body: string, ok = true) {
  return vi.spyOn(globalThis, 'fetch').mockResolvedValue({
    ok, text: async () => body,
  } as Response)
}

describe('breach lookup', () => {
  it('sends only the first five hex characters of the hash', async () => {
    const f = mockRange('')
    await checkPwnedPassword('password')
    const url = new URL(String(f.mock.calls[0]![0]))

    expect(url.href).toBe(`https://api.pwnedpasswords.com/range/${PASSWORD_PREFIX}`)

    // The whole point: neither the password nor the rest of the hash leaves the
    // device. Asserted against the path and query only — the HOST legitimately
    // contains the substring "password" (pwnedpasswords.com), and an earlier
    // version of this test failed on exactly that.
    const sent = url.pathname + url.search
    expect(sent).not.toContain('password')
    expect(sent).not.toContain(PASSWORD_SUFFIX)
    expect(sent).toBe(`/range/${PASSWORD_PREFIX}`)
  })

  it('detects a breached password from the returned suffixes', async () => {
    mockRange(`${PASSWORD_SUFFIX}:9659365\nAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:12`)
    const r = await checkPwnedPassword('password')
    expect(r.breached).toBe(true)
    expect(r.count).toBe(9659365)
    expect(r.unavailable).toBe(false)
  })

  it('passes a password whose suffix is absent', async () => {
    mockRange('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:12\nBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB:3')
    const r = await checkPwnedPassword('password')
    expect(r.breached).toBe(false)
  })

  // With Add-Padding, HIBP returns decoy hashes with a count of 0. Treating one
  // as a hit would reject a perfectly good password for no reason.
  it('ignores zero-count padding entries', async () => {
    mockRange(`${PASSWORD_SUFFIX}:0`)
    const r = await checkPwnedPassword('password')
    expect(r.breached).toBe(false)
  })

  it('requests padding so the response size leaks nothing either', async () => {
    const f = mockRange('')
    await checkPwnedPassword('password')
    const init = f.mock.calls[0]![1] as RequestInit
    expect((init.headers as Record<string, string>)['Add-Padding']).toBe('true')
  })

  // The three-state result is the whole design. An outage must not be reported
  // as "safe" — and must not lock a school out either.
  it('reports unavailable rather than safe when the network fails', async () => {
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('offline'))
    const r = await checkPwnedPassword('password')
    expect(r.unavailable).toBe(true)
    expect(r.breached).toBe(false)
  })

  it('reports unavailable on a non-OK response', async () => {
    mockRange('', false)
    const r = await checkPwnedPassword('password')
    expect(r.unavailable).toBe(true)
  })

  it('does not call the network for an empty password', async () => {
    const f = mockRange('')
    const r = await checkPwnedPassword('')
    expect(f).not.toHaveBeenCalled()
    expect(r).toEqual({ breached: false, count: 0, unavailable: false })
  })
})

describe('local checks', () => {
  it('requires length over composition', () => {
    expect(localPasswordProblems('Ab1!')).toContainEqual(
      expect.stringContaining('at least 10 characters'))
    // No complexity rule: a long passphrase of plain words is fine.
    expect(localPasswordProblems('correct horse battery staple')).toEqual([])
  })

  it('rejects digits only and single repeated characters', () => {
    expect(localPasswordProblems('12345678901')).toContainEqual(
      expect.stringContaining('Digits alone'))
    expect(localPasswordProblems('aaaaaaaaaaaa')).toContainEqual(
      expect.stringContaining('repeated character'))
  })

  it('rejects anything guessable from the account itself', () => {
    const ctx = {
      email: 'anjali.ramdin@demo-sss.mu',
      firstName: 'Anjali', lastName: 'Ramdin', schoolName: 'Demo State',
    }
    expect(localPasswordProblems('anjali.ramdin2026', ctx)).toContainEqual(
      expect.stringContaining('your email'))
    expect(localPasswordProblems('RamdinRamdin1', ctx)).toContainEqual(
      expect.stringContaining('your surname'))
    // Short values must not match by accident — 'Demo State' contains 'Demo',
    // but a 3-character name should never disqualify half the dictionary.
    expect(localPasswordProblems('thunderous parsnip', ctx)).toEqual([])
  })
})

describe('wording', () => {
  it('says nothing when the password is clean', () => {
    expect(describePwned({ breached: false, count: 0, unavailable: false })).toBeNull()
  })

  it('advises rather than blocks when the check could not run', () => {
    const msg = describePwned({ breached: false, count: 0, unavailable: true })!
    expect(msg).toContain('You can continue')
  })

  it('escalates the wording for very common passwords', () => {
    const common = describePwned({ breached: true, count: 9_659_365, unavailable: false })!
    expect(common).toContain('Attackers try these first')
  })
})
