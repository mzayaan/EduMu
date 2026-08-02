import {
  Bar, BarChart, CartesianGrid, Cell, Legend, Line, LineChart,
  ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts'

/**
 * Charts for the Rector's dashboard.
 *
 * Two rules throughout:
 *
 *   1. The 80% attendance threshold is drawn as a reference line wherever
 *      attendance appears. A percentage without the line it must clear is just
 *      a number; with it, the reader sees the decision.
 *   2. Bars are coloured by whether they clear the threshold, not by category.
 *      Colour should carry meaning, not decoration.
 *
 * Everything renders from the same views the tables use, so a chart can never
 * disagree with the figure beside it.
 */

const INK = '#0f172a'
const MUTED = '#94a3b8'
const PRESENT = '#15803d'
const ABSENT = '#b91c1c'
const LATE = '#b45309'
const BRAND = '#0f4c5c'

const axis = { fontSize: 11, fill: MUTED }

function Empty({ children }: { children: string }) {
  return <p className="py-8 text-center text-sm text-slate-400">{children}</p>
}

/** Mean attendance per class for a term, against the 80% rule. */
export function AttendanceByClassChart({ rows, threshold = 80 }: {
  rows: { class_name: string; mean_pct: number | null; below_threshold: number }[]
  threshold?: number
}) {
  const data = rows
    .filter((r) => r.mean_pct !== null)
    .map((r) => ({ name: r.class_name, pct: Number(r.mean_pct), below: r.below_threshold }))
  if (data.length === 0) return <Empty>No attendance recorded yet.</Empty>

  return (
    <ResponsiveContainer width="100%" height={220}>
      <BarChart data={data} margin={{ top: 8, right: 8, left: -18, bottom: 4 }}>
        <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#e2e8f0" />
        <XAxis dataKey="name" tick={axis} tickLine={false} axisLine={false} />
        <YAxis domain={[0, 100]} tick={axis} tickLine={false} axisLine={false} unit="%" />
        <Tooltip
          formatter={(v: any, _n, p: any) =>
            [`${v}%`, `${p.payload.below} pupil(s) below ${threshold}%`]}
          contentStyle={{ fontSize: 12, borderRadius: 8, border: '1px solid #e2e8f0' }}
        />
        <ReferenceLine y={threshold} stroke={ABSENT} strokeDasharray="4 4"
          label={{ value: `${threshold}% required`, position: 'right',
                   fontSize: 10, fill: ABSENT }} />
        <Bar dataKey="pct" radius={[3, 3, 0, 0]}>
          {data.map((d, i) => (
            <Cell key={i} fill={d.pct >= threshold ? PRESENT : ABSENT} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  )
}

/** Attendance across the terms of the year — is the school drifting? */
export function AttendanceTrendChart({ rows, threshold = 80 }: {
  rows: { term_name: string; mean_pct: number | null }[]
  threshold?: number
}) {
  const data = rows
    .filter((r) => r.mean_pct !== null)
    .map((r) => ({ term: r.term_name.replace(' Term', ''), pct: Number(r.mean_pct) }))
  if (data.length < 2) return <Empty>Needs at least two terms of attendance.</Empty>

  return (
    <ResponsiveContainer width="100%" height={200}>
      <LineChart data={data} margin={{ top: 8, right: 12, left: -18, bottom: 4 }}>
        <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#e2e8f0" />
        <XAxis dataKey="term" tick={axis} tickLine={false} axisLine={false} />
        <YAxis domain={[50, 100]} tick={axis} tickLine={false} axisLine={false} unit="%" />
        <Tooltip formatter={(v: any) => [`${v}%`, 'Mean attendance']}
                 contentStyle={{ fontSize: 12, borderRadius: 8, border: '1px solid #e2e8f0' }} />
        <ReferenceLine y={threshold} stroke={ABSENT} strokeDasharray="4 4" />
        <Line type="monotone" dataKey="pct" stroke={BRAND} strokeWidth={2}
              dot={{ r: 4, fill: BRAND }} />
      </LineChart>
    </ResponsiveContainer>
  )
}

/**
 * Pass rate by subject, worst first.
 *
 * Sorted ascending deliberately: a Rector opens this to find the subject in
 * trouble, not to admire the strongest one.
 */
export function PassRateChart({ rows }: {
  rows: { subject_name: string; pass_rate: number | null; entries: number }[]
}) {
  const data = rows
    .filter((r) => r.pass_rate !== null)
    .map((r) => ({ name: r.subject_name, rate: Number(r.pass_rate), n: r.entries }))
    .sort((a, b) => a.rate - b.rate)
  if (data.length === 0) return <Empty>No published results yet.</Empty>

  return (
    <ResponsiveContainer width="100%" height={Math.max(180, data.length * 26)}>
      <BarChart data={data} layout="vertical"
                margin={{ top: 4, right: 16, left: 8, bottom: 4 }}>
        <CartesianGrid strokeDasharray="3 3" horizontal={false} stroke="#e2e8f0" />
        <XAxis type="number" domain={[0, 100]} tick={axis}
               tickLine={false} axisLine={false} unit="%" />
        <YAxis type="category" dataKey="name" width={110} tick={axis}
               tickLine={false} axisLine={false} />
        <Tooltip formatter={(v: any, _n, p: any) => [`${v}%`, `${p.payload.n} entries`]}
                 contentStyle={{ fontSize: 12, borderRadius: 8, border: '1px solid #e2e8f0' }} />
        <ReferenceLine x={60} stroke={MUTED} strokeDasharray="4 4"
          label={{ value: '60%', position: 'top', fontSize: 10, fill: MUTED }} />
        <Bar dataKey="rate" radius={[0, 3, 3, 0]}>
          {data.map((d, i) => (
            <Cell key={i} fill={d.rate >= 60 ? PRESENT : d.rate >= 40 ? LATE : ABSENT} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  )
}

/** Roll by grade, split by sex — the Ministry's most-requested figure. */
export function RollChart({ rows }: {
  rows: { grade: number; male: number; female: number }[]
}) {
  const data = rows.map((r) => ({
    grade: `G${r.grade}`, Boys: r.male, Girls: r.female,
  }))
  if (data.length === 0) return <Empty>No pupils on roll.</Empty>

  return (
    <ResponsiveContainer width="100%" height={200}>
      <BarChart data={data} margin={{ top: 8, right: 8, left: -18, bottom: 4 }}>
        <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#e2e8f0" />
        <XAxis dataKey="grade" tick={axis} tickLine={false} axisLine={false} />
        <YAxis tick={axis} tickLine={false} axisLine={false} allowDecimals={false} />
        <Tooltip contentStyle={{ fontSize: 12, borderRadius: 8, border: '1px solid #e2e8f0' }} />
        <Legend wrapperStyle={{ fontSize: 11 }} />
        <Bar dataKey="Boys" stackId="a" fill={BRAND} radius={[0, 0, 0, 0]} />
        <Bar dataKey="Girls" stackId="a" fill={MUTED} radius={[3, 3, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  )
}

export const chartInk = INK
