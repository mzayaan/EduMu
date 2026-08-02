import { formatDate } from '@/lib/format'

/**
 * The EduMU term report book.
 *
 * Designed rather than copied, and built to carry everything a Mauritian
 * secondary school actually records for a term: the pupil and class details a
 * parent checks first, every assessment as its own column so continuous work
 * and the examination are visible separately, the teacher of record for each
 * subject, per-subject remarks and difficulties, conduct, attendance broken
 * into authorised and unauthorised, and signature blocks for the three people
 * who sign it.
 *
 * Rank is rendered only when the school records one — several schools
 * deliberately do not rank the lower forms, and `school.settings
 * .suppress_ranks_grades` drives that.
 */

export interface Column {
  key: string
  title: string
  kind: string
  max_score: number | null
  weight: number
}

export interface SubjectRow {
  subject: string
  code: string | null
  teacher: string | null
  aggregate: number | null
  grade: string | null
  rank_in_set: number | null
  set_size: number | null
  comment: string | null
  difficulties: string | null
  marks: Record<string, { score: number | null; code: string | null; max: number | null }>
}

export interface CardData {
  school: {
    name: string; code: string; motto: string | null; logo_path: string | null
    address: any; contact: any; type: string; zone: number | null
  }
  term: { name: string; sequence: number; year: string; starts_on: string; ends_on: string }
  next_term: { name: string; starts_on: string } | null
  pupil: {
    first_name: string; last_name: string; preferred_name: string | null
    admission_number: string; date_of_birth: string | null; sex: string | null
    house: string | null; extended_programme: boolean; photo_path: string | null
  }
  class: {
    name: string; stream: string; grade: number; legacy_form: string | null
    room: string | null; size: number; form_teacher: string | null
  } | null
  columns: Column[]
  subjects: SubjectRow[]
  summary: {
    overall_score: number | null; overall_rank: number | null; class_size: number | null
    attendance_pct: number | null; times_late: number | null
    form_teacher_comment: string | null; rector_comment: string | null
    status: 'draft' | 'published'; published_at: string | null
  } | null
  attendance: {
    sessions_possible: number; sessions_present: number
    absent_authorised: number; absent_unauthorised: number
    absent_total?: number
    times_late: number
    /** Recorded at the gate. Not the same as register entries marked late:
     *  a pupil who arrives after the morning register is absent AM, late PM. */
    late_arrivals?: number
    pct_present: number | null
  } | null
  conduct: {
    merits: { kind: string; reason: string; awarded_on: string }[]
    sanctions: number
    open_cases: number
  }
}

const GRADE_KEY = [
  ['A', '75–100'], ['B', '65–74'], ['C', '50–64'],
  ['D', '40–49'], ['E', '30–39'], ['U', 'below 30'],
]

export function ReportCard({ card, showRank = true }: {
  card: CardData
  showRank?: boolean
}) {
  const s = card.summary
  const a = card.attendance
  const cls = card.class
  const name = `${card.pupil.last_name.toUpperCase()}, ${card.pupil.first_name}`

  return (
    <article className="report-card mx-auto w-full max-w-[210mm] bg-white px-9 py-8 text-[11px] leading-snug text-ink">

      {/* ── Letterhead ─────────────────────────────────────────────── */}
      <header className="flex items-start justify-between gap-4 border-b-[3px] border-double border-ink pb-3">
        <div className="flex items-center gap-3">
          {card.school.logo_path
            ? <img src={card.school.logo_path} alt="" className="h-14 w-14 object-contain" />
            : <div className="grid h-14 w-14 place-items-center rounded-full border-2 border-ink text-sm font-bold">
                {card.school.code.slice(0, 3)}
              </div>}
          <div>
            <h1 className="text-lg font-bold uppercase tracking-wide">{card.school.name}</h1>
            {card.school.motto && <p className="text-[10px] italic text-slate-600">{card.school.motto}</p>}
            <p className="text-[10px] text-slate-500">
              {[card.school.address?.street, card.school.address?.town].filter(Boolean).join(', ')}
              {card.school.zone ? ` · Zone ${card.school.zone}` : ''}
            </p>
          </div>
        </div>
        <div className="text-right">
          <p className="text-sm font-bold uppercase tracking-wider">Term Report</p>
          <p className="text-[10px] text-slate-600">
            {card.term.name} {card.term.year}
          </p>
          <p className="text-[10px] text-slate-500">
            {formatDate(card.term.starts_on)} – {formatDate(card.term.ends_on)}
          </p>
          {s?.status === 'draft' && (
            <p className="mt-1 text-[9px] font-bold uppercase tracking-widest text-absent">
              Draft — not for issue
            </p>
          )}
        </div>
      </header>

      {/* ── Pupil and class ────────────────────────────────────────── */}
      <section className="mt-3 grid grid-cols-2 gap-x-8 border-b border-slate-300 pb-3">
        <dl className="space-y-0.5">
          <Row label="Pupil" value={name} strong />
          <Row label="Admission no." value={card.pupil.admission_number} />
          <Row label="Date of birth"
               value={card.pupil.date_of_birth ? formatDate(card.pupil.date_of_birth) : '—'} />
          <Row label="House" value={card.pupil.house ?? '—'} />
        </dl>
        <dl className="space-y-0.5">
          <Row label="Class" value={cls ? `${cls.name} (${cls.size} pupils)` : '—'} strong />
          <Row label="Grade"
               value={cls ? `Grade ${cls.grade}${cls.legacy_form ? ` · ${cls.legacy_form}` : ''}` : '—'} />
          <Row label="Stream"
               value={cls
                 ? cls.stream === 'regular' ? 'Regular'
                   : cls.stream.charAt(0).toUpperCase() + cls.stream.slice(1)
                 : '—'} />
          <Row label="Form Teacher" value={cls?.form_teacher ?? '—'} />
        </dl>
      </section>

      {/* ── Marks matrix ───────────────────────────────────────────── */}
      <table className="mt-3 w-full border-collapse">
        <thead>
          <tr className="border-y border-ink text-[9px] uppercase tracking-wide">
            <th className="w-[18%] py-1.5 pr-2 text-left">Subject</th>
            <th className="w-[13%] py-1.5 pr-2 text-left font-normal">Teacher</th>
            {card.columns.map((c) => (
              <th key={c.key} className="px-1 py-1.5 text-center">
                <div className="leading-tight">{shortTitle(c.title)}</div>
                <div className="font-normal normal-case text-slate-500">
                  {c.max_score !== null ? `/${fmt(c.max_score)}` : 'varies'} · ×{fmt(c.weight)}
                </div>
              </th>
            ))}
            <th className="px-1 py-1.5 text-center">Term</th>
            <th className="px-1 py-1.5 text-center">Grade</th>
            {showRank && <th className="px-1 py-1.5 text-center">Pos.</th>}
            <th className="w-[20%] py-1.5 pl-2 text-left">Remarks</th>
          </tr>
        </thead>
        <tbody>
          {card.subjects.map((r) => (
            <tr key={r.subject} className="border-b border-slate-200 align-top">
              <td className="py-1.5 pr-2 font-semibold">{r.subject}</td>
              <td className="py-1.5 pr-2 text-[10px] text-slate-600">{r.teacher ?? '—'}</td>
              {card.columns.map((c) => {
                const m = r.marks[c.key]
                return (
                  <td key={c.key} className="px-1 py-1.5 text-center tabular-nums">
                    {!m ? <span className="text-slate-300">–</span>
                      : m.code ? <span className="text-[9px] font-semibold">{m.code}</span>
                      : <>
                          {fmt(m.score)}
                          {c.max_score === null && m.max !== null && (
                            <span className="text-[9px] text-slate-400">/{fmt(m.max)}</span>
                          )}
                        </>}
                  </td>
                )
              })}
              <td className="px-1 py-1.5 text-center font-bold tabular-nums">
                {r.aggregate === null ? '—' : `${fmt(r.aggregate)}%`}
              </td>
              <td className="px-1 py-1.5 text-center font-bold">{r.grade ?? '—'}</td>
              {showRank && (
                <td className="px-1 py-1.5 text-center text-[10px] tabular-nums">
                  {r.rank_in_set ? `${r.rank_in_set}/${r.set_size}` : '—'}
                </td>
              )}
              <td className="py-1.5 pl-2 text-[10px]">
                {r.comment}
                {r.difficulties && (
                  <span className="block italic text-slate-500">{r.difficulties}</span>
                )}
                {!r.comment && !r.difficulties && <span className="text-slate-300">—</span>}
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {/* ── Summary and attendance ─────────────────────────────────── */}
      <section className="mt-3 grid grid-cols-[3fr_2fr] gap-4">
        <div className="border border-slate-300 p-2.5">
          <h2 className="text-[9px] font-bold uppercase tracking-widest text-slate-500">
            Overall
          </h2>
          <div className="mt-1.5 flex items-end justify-between">
            <Big label="Term average"
                 value={s?.overall_score != null ? `${fmt(s.overall_score)}%` : '—'} />
            {showRank && (
              <Big label="Position in class"
                   value={s?.overall_rank ? `${s.overall_rank} of ${s.class_size}` : '—'} />
            )}
            <Big label="Subjects" value={String(card.subjects.length)} />
          </div>
          <table className="mt-2 w-full text-[9px]">
            <tbody>
              <tr className="text-slate-500">
                {GRADE_KEY.map(([g]) => (
                  <td key={g} className="border border-slate-200 px-1 text-center font-bold text-ink">{g}</td>
                ))}
              </tr>
              <tr className="text-slate-500">
                {GRADE_KEY.map(([g, range]) => (
                  <td key={g} className="border border-slate-200 px-1 text-center">{range}</td>
                ))}
              </tr>
            </tbody>
          </table>
        </div>

        <div className="border border-slate-300 p-2.5">
          <h2 className="text-[9px] font-bold uppercase tracking-widest text-slate-500">
            Attendance
          </h2>
          {a ? (
            <>
              {/* Counts before the percentage. "92%" tells a parent little;
                  "absent 7 sessions, late 4 times" is something they can act on. */}
              <div className="mt-1.5 grid grid-cols-3 gap-2 text-center">
                <Count label="Sessions absent"
                       value={a.absent_total ?? (a.absent_authorised + a.absent_unauthorised)}
                       tone={(a.absent_total ?? (a.absent_authorised + a.absent_unauthorised)) > 0
                             ? 'bad' : 'normal'} />
                <Count label="Times late" value={a.times_late}
                       tone={a.times_late > 0 ? 'warn' : 'normal'} />
                <Count label="Attended"
                       value={a.pct_present != null ? `${fmt(a.pct_present)}%` : '—'}
                       tone={a.pct_present != null && a.pct_present < 80 ? 'bad' : 'normal'} />
              </div>

              <p className="mt-1.5 text-[9.5px] leading-relaxed text-slate-600">
                Present for {a.sessions_present} of {a.sessions_possible} sessions.
                {' '}Of the absences, {a.absent_authorised} authorised and{' '}
                {a.absent_unauthorised} unauthorised.
                {a.late_arrivals !== undefined && a.late_arrivals > 0 && (
                  <> {a.late_arrivals} late arrival{a.late_arrivals === 1 ? '' : 's'}{' '}
                  recorded at the gate.</>
                )}
              </p>

              {a.pct_present != null && a.pct_present < 80 && (
                <p className="mt-1 text-[9px] font-semibold text-absent">
                  Below the 80% the school requires before examinations.
                </p>
              )}
              {a.absent_unauthorised > 0 && (
                <p className="mt-0.5 text-[9px] text-slate-600">
                  Unauthorised absence should be explained by the Responsible
                  Party. Attendance is recorded on the Leaving Certificate.
                </p>
              )}
            </>
          ) : <p className="mt-1.5 text-[10px] text-slate-400">Not recorded.</p>}

          <h2 className="mt-2.5 text-[9px] font-bold uppercase tracking-widest text-slate-500">
            Conduct
          </h2>
          {card.conduct.merits.length === 0 && card.conduct.sanctions === 0 ? (
            <p className="mt-1 text-[10px] text-slate-500">
              No matters recorded this term.
            </p>
          ) : (
            <ul className="mt-1 space-y-0.5 text-[10px]">
              {card.conduct.merits.slice(0, 3).map((m, i) => (
                <li key={i}>✓ {m.reason}</li>
              ))}
              {card.conduct.sanctions > 0 && (
                <li className="text-absent">
                  {card.conduct.sanctions} disciplinary matter(s) recorded
                </li>
              )}
            </ul>
          )}
        </div>
      </section>

      {/* ── Remarks ────────────────────────────────────────────────── */}
      <section className="mt-3 space-y-2">
        <Remark label={`Form Teacher${cls?.form_teacher ? ` — ${cls.form_teacher}` : ''}`}
                text={s?.form_teacher_comment} />
        <Remark label="Rector" text={s?.rector_comment} />
      </section>

      {/* ── Signatures ─────────────────────────────────────────────── */}
      <footer className="mt-6 grid grid-cols-3 gap-6">
        {['Form Teacher', 'Rector', 'Responsible Party'].map((role) => (
          <div key={role}>
            <div className="h-9 border-b border-ink" />
            <p className="mt-0.5 text-[9px] uppercase tracking-wide text-slate-500">{role}</p>
            <div className="mt-2.5 h-5 border-b border-dotted border-slate-400" />
            <p className="mt-0.5 text-[9px] text-slate-400">Date</p>
          </div>
        ))}
      </footer>

      <p className="mt-4 border-t border-slate-200 pt-1.5 text-[9px] text-slate-400">
        {card.next_term
          ? `${card.next_term.name} begins ${formatDate(card.next_term.starts_on)}.`
          : 'This is the final term of the academic year.'}
        {' '}This report is issued by {card.school.name} and should be retained by
        the Responsible Party. A pupil transferring school must return their
        report book before a Leaving Certificate can be issued.
      </p>
    </article>
  )
}

function Row({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className="flex gap-2">
      <dt className="w-28 shrink-0 text-slate-500">{label}</dt>
      <dd className={strong ? 'font-semibold' : ''}>{value}</dd>
    </div>
  )
}

/** A single attendance figure. Counts read louder than percentages. */
function Count({ label, value, tone = 'normal' }: {
  label: string; value: number | string; tone?: 'normal' | 'warn' | 'bad'
}) {
  const colour = tone === 'bad' ? 'text-absent' : tone === 'warn' ? 'text-late' : ''
  return (
    <div className="border border-slate-200 py-1">
      <p className={`text-base font-bold leading-none tabular-nums ${colour}`}>{value}</p>
      <p className="mt-0.5 text-[8.5px] uppercase tracking-wide text-slate-500">{label}</p>
    </div>
  )
}

function Big({ label, value, tone = 'normal' }: {
  label: string; value: string; tone?: 'normal' | 'bad'
}) {
  return (
    <div>
      <p className={`text-lg font-bold leading-none tabular-nums ${
        tone === 'bad' ? 'text-absent' : ''}`}>{value}</p>
      <p className="mt-0.5 text-[9px] uppercase tracking-wide text-slate-500">{label}</p>
    </div>
  )
}

function Remark({ label, text }: { label: string; text: string | null | undefined }) {
  return (
    <div className="border border-slate-300 p-2">
      <p className="text-[9px] font-bold uppercase tracking-widest text-slate-500">{label}</p>
      <p className="mt-0.5 min-h-[2.2rem] text-[10.5px]">
        {text || <span className="text-slate-300">—</span>}
      </p>
    </div>
  )
}

/** "July Mock Examination" is too wide for a column; "Second Term Examination" likewise. */
function shortTitle(t: string): string {
  return t
    .replace(/Examination/i, 'Exam')
    .replace(/^Class Test /i, 'Test ')
    .replace(/^Second Term /i, 'Term ')
    .replace(/^First Term /i, 'Term ')
    .replace(/^Third Term /i, 'Term ')
}

function fmt(n: number | null): string {
  if (n === null || n === undefined) return '—'
  return Number.isInteger(Number(n)) ? String(Number(n)) : String(Number(n))
}
