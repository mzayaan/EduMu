import { describe, expect, it } from 'vitest'
import {
  pctPresent,
  pctPresentExcludingAuthorised,
  screenExamEligibility,
  tally,
  type AttendanceStatus,
} from './attendance'

const s = (...v: AttendanceStatus[]) => v

describe('attendance tallies', () => {
  it('counts late and school activity as present', () => {
    const c = tally(s('present', 'late', 'school_activity', 'absent_unauth'))
    expect(c.sessionsPresent).toBe(3)
    expect(c.timesLate).toBe(1)
    expect(pctPresent(c)).toBe(75)
  })

  it('separates authorised from unauthorised absence', () => {
    const c = tally(s('present', 'absent_auth', 'on_leave', 'absent_unauth'))
    expect(c.sessionsAbsentAuth).toBe(2)
    expect(c.sessionsAbsentUnauth).toBe(1)
  })

  it('excludes authorised absence from the scholarship denominator', () => {
    const c = tally(s('present', 'present', 'absent_auth', 'absent_unauth'))
    expect(pctPresent(c)).toBe(50)
    expect(pctPresentExcludingAuthorised(c)).toBeCloseTo(66.67, 1)
  })

  it('returns null rather than 0 when no sessions are possible', () => {
    expect(pctPresent(tally([]))).toBeNull()
  })
})

describe('exam eligibility screening (80% rule)', () => {
  it('passes a student at exactly the threshold', () => {
    const c = tally(Array<AttendanceStatus>(100).fill('present').map((v, i) =>
      i < 80 ? v : ('absent_unauth' as AttendanceStatus)))
    const v = screenExamEligibility(c)
    expect(v.pct).toBe(80)
    expect(v.eligible).toBe(true)
    expect(v.shortfallSessions).toBe(0)
  })

  it('reports how many sessions short a debarred student is', () => {
    const c = tally(Array<AttendanceStatus>(100).fill('present').map((v, i) =>
      i < 70 ? v : ('absent_unauth' as AttendanceStatus)))
    const v = screenExamEligibility(c)
    expect(v.eligible).toBe(false)
    expect(v.shortfallSessions).toBe(10)
  })
})
