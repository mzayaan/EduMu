/**
 * TypeScript half of the promotion parity suite.
 *
 * Cases come from promotion.cases.json, which is the same file
 * scripts/gen-promotion-parity.mjs compiles into
 * supabase/tests/_generated_promotion_parity.sql. Both implementations are
 * checked against identical facts and identical expectations, so a divergence
 * between app.evaluate_promotion and evaluatePromotion() fails one side or the
 * other rather than going unnoticed until a July that decides real children's
 * years.
 *
 * The rules used here mirror app.seed_promotion_rules exactly. If you edit that
 * function, edit SHIPPED_RULES below and regenerate.
 */

import { describe, expect, it } from 'vitest'
import cases from './promotion.cases.json'
import { evaluatePromotion, type Facts, type Rule } from './promotion'

// Mirrors app.seed_promotion_rules (migration 57).
const SHIPPED_RULES: Rule[] = [
  ...[7, 8, 9, 10].flatMap((grade) => [
    {
      id: `std-${grade}`, name: 'Standard promotion', grade, stream: null,
      outcome: 'promote' as const, priority: 10,
      conditions: [{ kind: 'aggregate_gte' as const, value: 40 }],
    },
    {
      id: `relief-${grade}`, name: 'Second-attempt relief', grade, stream: null,
      outcome: 'conditional_promote' as const, priority: 20,
      conditions: [
        { kind: 'times_repeated_lte' as const, value: 1 },
        { kind: 'aggregate_gte' as const, value: 35 },
        { kind: 'attendance_pct_gte' as const, value: 75, countAuthorisedAsPresent: true },
      ],
    },
  ]),
  {
    id: 'lvi-credits', name: 'Lower VI entry — 4 credits', grade: 11, stream: null,
    outcome: 'promote', priority: 10,
    conditions: [{ kind: 'credit_count_gte', value: 4, sameSitting: true }],
  },
  {
    id: 'lvi-age', name: 'Lower VI entry — age relief', grade: 11, stream: null,
    outcome: 'conditional_promote', priority: 20,
    conditions: [
      { kind: 'credit_count_gte', value: 3, sameSitting: true },
      { kind: 'times_repeated_lte', value: 1 },
      { kind: 'age_on_date_lte', value: 19, asOf: 'jan_1' },
    ],
  },
  {
    id: 'lvi-repeat', name: 'Repeat Form V', grade: 11, stream: null,
    outcome: 'repeat', priority: 30,
    conditions: [{ kind: 'times_repeated_lte', value: 0 }],
  },
  {
    id: 'lvi-leave', name: 'Leave after SC', grade: 11, stream: null,
    outcome: 'leave', priority: 40, conditions: [],
  },
  {
    id: 'uvi', name: 'Upper VI entry', grade: 12, stream: null,
    outcome: 'promote', priority: 10,
    conditions: [
      { kind: 'subject_pass_count_gte', value: 2, level: 'principal' },
      { kind: 'subject_pass_count_gte', value: 2, level: 'subsidiary' },
    ],
  },
  {
    id: 'uvi-repeat', name: 'Repeat Lower VI', grade: 12, stream: null,
    outcome: 'repeat', priority: 20,
    conditions: [{ kind: 'times_repeated_lte', value: 0 }],
  },
  {
    id: 'uvi-refer', name: 'Refer for guidance', grade: 12, stream: null,
    outcome: 'refer', priority: 30, conditions: [],
  },
  {
    id: 'g13', name: 'Completes secondary schooling', grade: 13, stream: null,
    outcome: 'leave', priority: 10, conditions: [],
  },
]

describe('promotion parity — shared fixture', () => {
  for (const c of cases.cases) {
    it(c.name, () => {
      const facts = { ...cases.factDefaults, ...c.facts } as unknown as Facts
      expect(evaluatePromotion(facts, SHIPPED_RULES).outcome).toBe(c.expect)
    })
  }

  it('covers every outcome the enum can produce', () => {
    // A fixture that never exercises 'refer' or 'leave' would let either
    // implementation drop them silently.
    const seen = new Set(cases.cases.map((c) => c.expect))
    for (const outcome of ['promote', 'conditional_promote', 'repeat', 'leave', 'refer']) {
      expect(seen.has(outcome), `no case expects ${outcome}`).toBe(true)
    }
  })
})
