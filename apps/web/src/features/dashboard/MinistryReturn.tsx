import { formatDate } from '@/lib/format'

/**
 * The Ministry statistical return, as a document rather than a payload.
 *
 * Schools are asked for these figures repeatedly and currently spend half a day
 * assembling them by hand. Rendering the same JSON as an A4 sheet that can be
 * printed and signed is most of the value — nobody wants to transcribe from a
 * code block.
 *
 * Shares the print CSS with the report book: `.no-print`, `@page A4`, and
 * `break-inside: avoid` on tables.
 */

export interface MinistryReturnData {
  school: { code: string; name: string; type: string; zone: number | null }
  academic_year: string
  generated_at: string
  roll_by_grade: { grade: number; male: number; female: number; total: number }[]
  teaching_days: { term: string; days: number }[]
  attendance_by_term: { term: string; mean_pct: number | null; pupils_below_80: number }[]
  staff: { total: number; by_post: Record<string, number> }
  results: {
    subject: string; grade: number | null; term: string
    entries: number; mean: number | null; pass_rate: number | null
  }[]
}

export function MinistryReturn({ data }: { data: MinistryReturnData }) {
  const rollTotal = data.roll_by_grade.reduce((n, r) => n + r.total, 0)
  const boysTotal = data.roll_by_grade.reduce((n, r) => n + r.male, 0)
  const girlsTotal = data.roll_by_grade.reduce((n, r) => n + r.female, 0)

  return (
    <article className="report-card mx-auto w-full max-w-[210mm] bg-white px-9 py-8
                        text-[11px] leading-snug text-ink">
      <header className="border-b-[3px] border-double border-ink pb-3 text-center">
        <h1 className="text-base font-bold uppercase tracking-wide">
          Statistical Return
        </h1>
        <p className="text-[10px] text-slate-500">
          Ministry of Education and Human Resource
        </p>
        <p className="mt-2 text-sm font-semibold">{data.school.name}</p>
        <p className="text-[10px] text-slate-600">
          {data.school.code} · {data.school.type.replace('_', '-')}
          {data.school.zone ? ` · Zone ${data.school.zone}` : ''} ·
          {' '}Academic Year {data.academic_year}
        </p>
      </header>

      <Section title="1. Pupils on roll">
        <table className="w-full border-collapse">
          <thead>
            <tr className="border-y border-ink text-[9px] uppercase tracking-wide">
              <th className="py-1 text-left">Grade</th>
              <th className="py-1 text-right">Boys</th>
              <th className="py-1 text-right">Girls</th>
              <th className="py-1 text-right">Total</th>
            </tr>
          </thead>
          <tbody>
            {data.roll_by_grade.map((r) => (
              <tr key={r.grade} className="border-b border-slate-200">
                <td className="py-1">Grade {r.grade}</td>
                <td className="py-1 text-right tabular-nums">{r.male}</td>
                <td className="py-1 text-right tabular-nums">{r.female}</td>
                <td className="py-1 text-right font-semibold tabular-nums">{r.total}</td>
              </tr>
            ))}
            <tr className="border-t border-ink font-bold">
              <td className="py-1">Total</td>
              <td className="py-1 text-right tabular-nums">{boysTotal}</td>
              <td className="py-1 text-right tabular-nums">{girlsTotal}</td>
              <td className="py-1 text-right tabular-nums">{rollTotal}</td>
            </tr>
          </tbody>
        </table>
      </Section>

      <Section title="2. Teaching days">
        <table className="w-full border-collapse">
          <tbody>
            {data.teaching_days.map((t) => (
              <tr key={t.term} className="border-b border-slate-200">
                <td className="py-1">{t.term}</td>
                <td className="py-1 text-right tabular-nums">{t.days} days</td>
              </tr>
            ))}
            <tr className="border-t border-ink font-bold">
              <td className="py-1">Total</td>
              <td className="py-1 text-right tabular-nums">
                {data.teaching_days.reduce((n, t) => n + t.days, 0)} days
              </td>
            </tr>
          </tbody>
        </table>
      </Section>

      <Section title="3. Attendance">
        <table className="w-full border-collapse">
          <thead>
            <tr className="border-y border-ink text-[9px] uppercase tracking-wide">
              <th className="py-1 text-left">Term</th>
              <th className="py-1 text-right">Mean attendance</th>
              <th className="py-1 text-right">Pupils below 80%</th>
            </tr>
          </thead>
          <tbody>
            {data.attendance_by_term.map((a) => (
              <tr key={a.term} className="border-b border-slate-200">
                <td className="py-1">{a.term}</td>
                <td className="py-1 text-right tabular-nums">
                  {a.mean_pct === null ? '—' : `${a.mean_pct}%`}
                </td>
                <td className="py-1 text-right tabular-nums">{a.pupils_below_80}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="mt-1 text-[9px] text-slate-500">
          The school requires at least 80% attendance before mock and end-of-year
          examinations. Pupils below that threshold are screened individually and
          a decision recorded for each.
        </p>
      </Section>

      <Section title="4. Staff">
        <p className="font-semibold">{data.staff.total} in post</p>
        <ul className="mt-1 grid grid-cols-2 gap-x-6">
          {Object.entries(data.staff.by_post ?? {}).map(([post, n]) => (
            <li key={post} className="flex justify-between border-b border-slate-200 py-0.5">
              <span>{post}</span>
              <span className="tabular-nums">{n}</span>
            </li>
          ))}
        </ul>
      </Section>

      {data.results.length > 0 && (
        <Section title="5. Results">
          <table className="w-full border-collapse">
            <thead>
              <tr className="border-y border-ink text-[9px] uppercase tracking-wide">
                <th className="py-1 text-left">Subject</th>
                <th className="py-1 text-left">Grade</th>
                <th className="py-1 text-left">Term</th>
                <th className="py-1 text-right">Entries</th>
                <th className="py-1 text-right">Mean</th>
                <th className="py-1 text-right">Pass rate</th>
              </tr>
            </thead>
            <tbody>
              {data.results.map((r, i) => (
                <tr key={i} className="border-b border-slate-200">
                  <td className="py-1">{r.subject}</td>
                  <td className="py-1">{r.grade ?? '—'}</td>
                  <td className="py-1">{r.term}</td>
                  <td className="py-1 text-right tabular-nums">{r.entries}</td>
                  <td className="py-1 text-right tabular-nums">
                    {r.mean === null ? '—' : `${r.mean}%`}
                  </td>
                  <td className="py-1 text-right tabular-nums">
                    {r.pass_rate === null ? '—' : `${r.pass_rate}%`}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </Section>
      )}

      <footer className="mt-8 grid grid-cols-2 gap-10">
        <div>
          <div className="h-9 border-b border-ink" />
          <p className="mt-0.5 text-[9px] uppercase tracking-wide text-slate-500">Rector</p>
        </div>
        <div>
          <div className="h-9 border-b border-ink" />
          <p className="mt-0.5 text-[9px] uppercase tracking-wide text-slate-500">Date</p>
        </div>
      </footer>

      <p className="mt-4 border-t border-slate-200 pt-1.5 text-[9px] text-slate-400">
        Generated by EduMU on {formatDate(data.generated_at.slice(0, 10))} from the
        school's own records. Figures are as at the date of generation.
      </p>
    </article>
  )
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mt-4 break-inside-avoid">
      <h2 className="mb-1 text-[10px] font-bold uppercase tracking-widest text-slate-600">
        {title}
      </h2>
      {children}
    </section>
  )
}
