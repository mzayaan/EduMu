/**
 * Attendance mathematics.
 *
 * Getting these definitions wrong invalidates exam eligibility and State of
 * Mauritius Scholarship decisions, so all three denominators are computed from
 * raw counts rather than storing a single percentage.
 *
 * Sources: School Management Manual 4.5 (control of attendance, 80% before
 * mock and end-of-year examinations) and 5.7 (75% at a second attempt).
 */

export type AttendanceStatus =
  | 'present'
  | 'absent_unauth'
  | 'absent_auth'
  | 'late'
  | 'on_leave'
  | 'excluded'
  | 'school_activity'

export interface AttendanceCounts {
  sessionsPossible: number
  sessionsPresent: number
  sessionsAbsentUnauth: number
  sessionsAbsentAuth: number
  timesLate: number
}

/** Statuses that count as "in attendance" for the statutory percentage. */
const PRESENT_STATUSES: ReadonlySet<AttendanceStatus> = new Set([
  'present',
  'late',
  'school_activity',
])

const AUTHORISED_ABSENCE: ReadonlySet<AttendanceStatus> = new Set([
  'absent_auth',
  'on_leave',
])

export function tally(
  statuses: readonly AttendanceStatus[],
  sessionsPossible = statuses.length,
): AttendanceCounts {
  let present = 0
  let unauth = 0
  let auth = 0
  let late = 0
  for (const s of statuses) {
    if (PRESENT_STATUSES.has(s)) present++
    if (s === 'absent_unauth') unauth++
    if (AUTHORISED_ABSENCE.has(s)) auth++
    if (s === 'late') late++
  }
  return {
    sessionsPossible,
    sessionsPresent: present,
    sessionsAbsentUnauth: unauth,
    sessionsAbsentAuth: auth,
    timesLate: late,
  }
}

/** The percentage the 80% and 75% rules read. */
export function pctPresent(c: AttendanceCounts): number | null {
  if (c.sessionsPossible === 0) return null
  return round2((100 * c.sessionsPresent) / c.sessionsPossible)
}

/** Present plus authorised absence — the softer view shown to guardians. */
export function pctAttendedInclAuthorised(c: AttendanceCounts): number | null {
  if (c.sessionsPossible === 0) return null
  return round2(
    (100 * (c.sessionsPresent + c.sessionsAbsentAuth)) / c.sessionsPossible,
  )
}

/**
 * Scholarship rules count absences "exclusive of authorised absences",
 * so the denominator excludes authorised absence entirely.
 */
export function pctPresentExcludingAuthorised(c: AttendanceCounts): number | null {
  const denominator = c.sessionsPossible - c.sessionsAbsentAuth
  if (denominator <= 0) return null
  return round2((100 * c.sessionsPresent) / denominator)
}

export interface EligibilityVerdict {
  eligible: boolean
  pct: number | null
  threshold: number
  shortfallSessions: number
}

/**
 * Exam eligibility screening. The school insists on at least 80% attendance
 * before July mock examinations and end-of-year internal examinations.
 * This produces a recommendation — the Rector always decides.
 */
export function screenExamEligibility(
  c: AttendanceCounts,
  threshold = 80,
): EligibilityVerdict {
  const pct = pctPresent(c)
  const required = Math.ceil((threshold / 100) * c.sessionsPossible)
  return {
    eligible: pct !== null && pct >= threshold,
    pct,
    threshold,
    shortfallSessions: Math.max(0, required - c.sessionsPresent),
  }
}

function round2(n: number): number {
  return Math.round(n * 100) / 100
}
