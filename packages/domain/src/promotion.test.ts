import { describe, expect, it } from 'vitest'
import {
  conditionHolds, evaluatePromotion, diffCohort,
  type Condition, type Facts, type Rule,
} from './promotion'

const facts = (over: Partial<Facts> = {}): Facts => ({
  aggregate: 50,
  credit_count: 0,
  pass_count: 0,
  pass_count_principal: 0,
  pass_count_subsidiary: 0,
  attendance_pct: 90,
  attendance_pct_incl_authorised: 95,
  times_repeated: 0,
  age_at_jan_1: 15,
  has_medical_certificate_for_prolonged_absence: false,
  core_passed: {},
  grade: 8,
  stream: null,
  ...over,
})

const rule = (over: Partial<Rule> & { id: string }): Rule => ({
  name: over.id, grade: 8, outcome: 'promote', priority: 10, conditions: [], ...over,
})

describe('conditions', () => {
  it('aggregate_gte compares at the boundary inclusively', () => {
    const c: Condition = { kind: 'aggregate_gte', value: 40 }
    expect(conditionHolds(facts({ aggregate: 40 }), c)).toBe(true)
    expect(conditionHolds(facts({ aggregate: 39.99 }), c)).toBe(false)
  })

  // The bug this guards against: treating a missing fact as 0. A pupil with no
  // marks must not be handled as a pupil who scored zero — and for _lte tests,
  // a null read as 0 would silently PASS.
  it('a missing aggregate fails rather than reading as zero', () => {
    expect(conditionHolds(facts({ aggregate: null }), { kind: 'aggregate_gte', value: 0 }))
      .toBe(false)
  })

  it('a missing attendance figure fails', () => {
    expect(conditionHolds(facts({ attendance_pct: null }), { kind: 'attendance_pct_gte', value: 0 }))
      .toBe(false)
  })

  it('counts do treat null as zero, because absent results genuinely mean none', () => {
    expect(conditionHolds(facts({ credit_count: null }), { kind: 'credit_count_gte', value: 0 }))
      .toBe(true)
    expect(conditionHolds(facts({ credit_count: null }), { kind: 'credit_count_gte', value: 1 }))
      .toBe(false)
  })

  it('attendance_pct_gte picks the figure the rule asked for', () => {
    const f = facts({ attendance_pct: 70, attendance_pct_incl_authorised: 88 })
    expect(conditionHolds(f, { kind: 'attendance_pct_gte', value: 75 })).toBe(false)
    expect(conditionHolds(f, {
      kind: 'attendance_pct_gte', value: 75, countAuthorisedAsPresent: true,
    })).toBe(true)
  })

  it('subject_pass_count_gte reads the right level', () => {
    const f = facts({ pass_count: 6, pass_count_principal: 2, pass_count_subsidiary: 1 })
    expect(conditionHolds(f, { kind: 'subject_pass_count_gte', value: 2, level: 'principal' })).toBe(true)
    expect(conditionHolds(f, { kind: 'subject_pass_count_gte', value: 2, level: 'subsidiary' })).toBe(false)
    expect(conditionHolds(f, { kind: 'subject_pass_count_gte', value: 6 })).toBe(true)
  })

  it('times_repeated_lte is inclusive', () => {
    expect(conditionHolds(facts({ times_repeated: 1 }), { kind: 'times_repeated_lte', value: 1 })).toBe(true)
    expect(conditionHolds(facts({ times_repeated: 2 }), { kind: 'times_repeated_lte', value: 1 })).toBe(false)
  })

  // Refusing is the correct answer: exam_date needs the exam timetable, and
  // answering with the wrong date would quietly decide a child's year.
  it('age_on_date_lte refuses asOf: exam_date rather than guessing', () => {
    const f = facts({ age_at_jan_1: 15 })
    expect(conditionHolds(f, { kind: 'age_on_date_lte', value: 19, asOf: 'jan_1' })).toBe(true)
    expect(conditionHolds(f, { kind: 'age_on_date_lte', value: 19, asOf: 'exam_date' })).toBe(false)
  })

  it('core_subject_passed reads the named subject only', () => {
    const f = facts({ core_passed: { english: true, maths: false } })
    expect(conditionHolds(f, { kind: 'core_subject_passed', subject: 'english' })).toBe(true)
    expect(conditionHolds(f, { kind: 'core_subject_passed', subject: 'maths' })).toBe(false)
    expect(conditionHolds(f, { kind: 'core_subject_passed', subject: 'french' })).toBe(false)
  })

  it('an unknown condition kind fails rather than promoting by accident', () => {
    // Reachable in production: rules are data, so a kind can arrive from the
    // database that this build has never heard of.
    const unknown = { kind: 'invented_later', value: 1 } as unknown as Condition
    expect(conditionHolds(facts(), unknown)).toBe(false)
  })
})

describe('evaluation', () => {
  it('first match by priority wins, not best match', () => {
    const rules = [
      rule({ id: 'low', priority: 20, outcome: 'conditional_promote' }),
      rule({ id: 'high', priority: 10, outcome: 'promote' }),
    ]
    expect(evaluatePromotion(facts(), rules).ruleId).toBe('high')
  })

  it('ALL conditions must hold', () => {
    const r = rule({
      id: 'both', conditions: [
        { kind: 'aggregate_gte', value: 40 },
        { kind: 'attendance_pct_gte', value: 95 },
      ],
    })
    expect(evaluatePromotion(facts({ aggregate: 50, attendance_pct: 90 }), [r]).outcome)
      .toBe('repeat')
    expect(evaluatePromotion(facts({ aggregate: 50, attendance_pct: 96 }), [r]).outcome)
      .toBe('promote')
  })

  it('falls through to repeat, which is the safe direction', () => {
    const v = evaluatePromotion(facts({ aggregate: 10 }), [
      rule({ id: 'std', conditions: [{ kind: 'aggregate_gte', value: 40 }] }),
    ])
    expect(v.outcome).toBe('repeat')
    expect(v.ruleId).toBeNull()
    expect(v.ruleName).toBe('no rule matched')
  })

  it('only considers rules for the pupil grade', () => {
    const rules = [rule({ id: 'g9', grade: 9, outcome: 'promote' })]
    expect(evaluatePromotion(facts({ grade: 8 }), rules).outcome).toBe('repeat')
    expect(evaluatePromotion(facts({ grade: 9 }), rules).outcome).toBe('promote')
  })

  it('a null stream on a rule applies to every stream', () => {
    const anyStream = rule({ id: 'any', stream: null, outcome: 'promote' })
    const science = rule({ id: 'sci', stream: 'science', outcome: 'leave', priority: 5 })
    expect(evaluatePromotion(facts({ stream: 'arts' }), [anyStream, science]).ruleId).toBe('any')
    expect(evaluatePromotion(facts({ stream: 'science' }), [anyStream, science]).ruleId).toBe('sci')
  })

  it('skips inactive rules', () => {
    const rules = [rule({ id: 'off', priority: 1, outcome: 'leave', isActive: false }),
                   rule({ id: 'on', priority: 2, outcome: 'promote' })]
    expect(evaluatePromotion(facts(), rules).ruleId).toBe('on')
  })
})

describe('the shipped Mauritian rules', () => {
  // Mirrors app.seed_promotion_rules for grades 7-8.
  const lower: Rule[] = [
    rule({ id: 'std', name: 'Standard promotion', priority: 10, outcome: 'promote',
           conditions: [{ kind: 'aggregate_gte', value: 40 }] }),
    rule({ id: 'relief', name: 'Second-attempt relief', priority: 20,
           outcome: 'conditional_promote', conditions: [
             { kind: 'times_repeated_lte', value: 1 },
             { kind: 'aggregate_gte', value: 35 },
             { kind: 'attendance_pct_gte', value: 75, countAuthorisedAsPresent: true },
           ] }),
  ]

  it('promotes a pupil above the threshold', () => {
    expect(evaluatePromotion(facts({ aggregate: 55 }), lower).outcome).toBe('promote')
  })

  it('gives second-attempt relief to a near-miss who has attended', () => {
    const f = facts({ aggregate: 37, times_repeated: 1, attendance_pct_incl_authorised: 80 })
    expect(evaluatePromotion(f, lower).outcome).toBe('conditional_promote')
  })

  it('withholds relief from a pupil who has already repeated twice', () => {
    const f = facts({ aggregate: 37, times_repeated: 2, attendance_pct_incl_authorised: 95 })
    expect(evaluatePromotion(f, lower).outcome).toBe('repeat')
  })

  it('withholds relief on poor attendance even with the marks', () => {
    const f = facts({ aggregate: 38, times_repeated: 0, attendance_pct_incl_authorised: 60 })
    expect(evaluatePromotion(f, lower).outcome).toBe('repeat')
  })

  it('Lower VI entry needs four credits', () => {
    const g11: Rule[] = [
      rule({ id: 'lvi', grade: 11, priority: 10, outcome: 'promote',
             conditions: [{ kind: 'credit_count_gte', value: 4, sameSitting: true }] }),
    ]
    expect(evaluatePromotion(facts({ grade: 11, credit_count: 4 }), g11).outcome).toBe('promote')
    expect(evaluatePromotion(facts({ grade: 11, credit_count: 3 }), g11).outcome).toBe('repeat')
  })

  it('Upper VI entry needs two Principal and two Subsidiary', () => {
    const g12: Rule[] = [
      rule({ id: 'uvi', grade: 12, priority: 10, outcome: 'promote', conditions: [
        { kind: 'subject_pass_count_gte', value: 2, level: 'principal' },
        { kind: 'subject_pass_count_gte', value: 2, level: 'subsidiary' },
      ] }),
    ]
    const ok = facts({ grade: 12, pass_count_principal: 2, pass_count_subsidiary: 2 })
    const short = facts({ grade: 12, pass_count_principal: 3, pass_count_subsidiary: 1 })
    expect(evaluatePromotion(ok, g12).outcome).toBe('promote')
    expect(evaluatePromotion(short, g12).outcome).toBe('repeat')
  })
})

describe('cohort diff', () => {
  it('reports only pupils whose outcome changes when a threshold moves', () => {
    const before = [rule({ id: 'r', conditions: [{ kind: 'aggregate_gte', value: 40 }] })]
    const after = [rule({ id: 'r', conditions: [{ kind: 'aggregate_gte', value: 50 }] })]
    const cohort = [
      { studentId: 'a', facts: facts({ aggregate: 60 }) }, // unaffected
      { studentId: 'b', facts: facts({ aggregate: 45 }) }, // promote → repeat
      { studentId: 'c', facts: facts({ aggregate: 20 }) }, // unaffected
    ]
    const changed = diffCohort(cohort, before, after)
    expect(changed).toEqual([{ studentId: 'b', from: 'promote', to: 'repeat' }])
  })
})
