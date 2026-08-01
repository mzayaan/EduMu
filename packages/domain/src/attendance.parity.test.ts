/**
 * Parity fixture.
 *
 * These cases are also compiled into a SQL suite by scripts/gen-parity-sql.mjs
 * and run against Postgres in CI. The TypeScript functions here are the
 * executable specification; the SQL in app.attendance_stats() is what actually
 * decides exam eligibility. Both are checked against this one file so they
 * cannot drift.
 */
import { describe, expect, it } from 'vitest'
import fixture from '../fixtures/attendance-cases.json'
import {
  pctPresent,
  pctPresentExcludingAuthorised,
  screenExamEligibility,
  tally,
  type AttendanceStatus,
} from './attendance'

describe('attendance parity fixture', () => {
  for (const c of fixture.cases) {
    it(c.name, () => {
      const counts = tally(c.statuses as AttendanceStatus[])
      const verdict = screenExamEligibility(counts, fixture.defaultThreshold)

      expect(pctPresent(counts)).toBe(c.expect.pctPresent)
      expect(pctPresentExcludingAuthorised(counts)).toBe(c.expect.pctExclAuth)
      expect(verdict.eligible).toBe(c.expect.eligible)
      expect(verdict.shortfallSessions).toBe(c.expect.shortfall)
    })
  }
})
