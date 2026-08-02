import { useEffect, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase, hasCap, type EduClaims } from '@/lib/supabase'

/**
 * School crest, used on the report book and every printed document.
 *
 * Stored in the student-photos bucket under {school_id}/logo/... so the
 * existing path convention and its RLS policy apply unchanged — the first path
 * segment is the tenant, which is what app.storage_school() reads.
 */
function LogoUpload({ schools }: { schools: SchoolRow[] }) {
  const qc = useQueryClient()
  const [schoolId, setSchoolId] = useState('')
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!schoolId && schools.length) setSchoolId(schools[0]!.school_id)
  }, [schools, schoolId])

  async function upload(file: File) {
    if (!schoolId) return
    setBusy(true); setError(null); setMsg(null)
    try {
      if (file.size > 2 * 1024 * 1024) {
        throw new Error('The crest must be under 2 MB.')
      }
      const ext = file.name.split('.').pop()?.toLowerCase() ?? 'png'
      const path = `${schoolId}/logo/crest.${ext}`

      const { error: upErr } = await supabase.storage
        .from('student-photos')
        .upload(path, file, { upsert: true, contentType: file.type })
      if (upErr) throw upErr

      const { data } = supabase.storage.from('student-photos').getPublicUrl(path)
      const { error: dbErr } = await supabase
        .from('school').update({ logo_path: data.publicUrl }).eq('id', schoolId)
      if (dbErr) throw dbErr

      setMsg('Crest updated. It appears on report books and printed documents.')
      void qc.invalidateQueries({ queryKey: ['platform-overview'] })
    } catch (e: any) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  if (schools.length === 0) return null

  return (
    <div className="mt-6 rounded-xl border border-slate-200 p-4">
      <p className="text-sm font-medium">School crest</p>
      <p className="mt-0.5 text-xs text-slate-400">
        Appears on the report book, the Ministry return and every printed
        document. PNG or JPEG, square, under 2&nbsp;MB.
      </p>
      <div className="mt-2 flex flex-wrap items-center gap-2">
        <select value={schoolId} onChange={(e) => setSchoolId(e.target.value)}
                className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm">
          {schools.map((s) => (
            <option key={s.school_id} value={s.school_id}>{s.name}</option>
          ))}
        </select>
        <input
          type="file"
          accept="image/png,image/jpeg,image/webp"
          disabled={busy}
          onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f) }}
          className="text-xs file:mr-2 file:h-10 file:rounded-lg file:border-0
                     file:bg-brand file:px-4 file:text-sm file:font-semibold
                     file:text-white"
        />
      </div>
      {busy && <p className="mt-2 text-xs text-slate-500">Uploading…</p>}
      {msg && <p className="mt-2 text-xs text-present">{msg}</p>}
      {error && <p className="mt-2 text-xs text-absent">{error}</p>}
    </div>
  )
}

interface SchoolRow {
  school_id: string; code: string; name: string
  type: string; zone: number | null
  pupils: number; staff: number; classes: number
  mean_attendance: number | null; below_threshold: number; open_discrepancies: number
}

async function fetchOverview(): Promise<SchoolRow[]> {
  const { data, error } = await supabase.rpc('platform_overview')
  if (error) throw error
  return (data ?? []) as SchoolRow[]
}

/**
 * Platform console.
 *
 * Two audiences with the same screen: the operator running EduMU across
 * schools, and a Zone Director whose remit is several schools but only in
 * aggregate. Neither sees a named child here — that is enforced in RLS, and
 * this screen simply has nothing personal to show.
 */
export function PlatformConsole({ claims }: { claims: EduClaims }) {
  const qc = useQueryClient()
  const canProvision = hasCap(claims, 'platform.manage')
  const [open, setOpen] = useState(false)
  const [code, setCode] = useState('')
  const [name, setName] = useState('')
  const [zone, setZone] = useState(1)
  const [type, setType] = useState('state')
  const [year, setYear] = useState('2026')
  const [terms, setTerms] = useState([
    { name: 'First Term',  starts_on: '2026-01-12', ends_on: '2026-04-03' },
    { name: 'Second Term', starts_on: '2026-04-20', ends_on: '2026-07-17' },
    { name: 'Third Term',  starts_on: '2026-08-17', ends_on: '2026-10-30' },
  ])
  const [error, setError] = useState<string | null>(null)

  const schools = useQuery({ queryKey: ['platform-overview'], queryFn: fetchOverview })

  const provision = useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.rpc('rpc_provision_school', {
        p_code: code, p_name: name, p_type: type,
        p_zone: zone, p_year_name: year, p_terms: terms,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: () => {
      setOpen(false); setCode(''); setName(''); setError(null)
      void qc.invalidateQueries({ queryKey: ['platform-overview'] })
    },
    onError: (e: any) => setError(e.message),
  })

  return (
    <div className="mx-auto w-full max-w-5xl pb-32">
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur">
        <h1 className="text-lg font-semibold">
          {canProvision ? 'Platform' : 'Zone Overview'}
        </h1>
        <p className="text-sm text-slate-500">
          {canProvision
            ? 'Schools running on EduMU'
            : 'Schools in your education zone — aggregate figures only'}
        </p>
        {canProvision && (
          <button onClick={() => setOpen((v) => !v)}
                  className="mt-3 h-10 rounded-lg bg-brand px-4 text-sm font-semibold text-white">
            {open ? 'Cancel' : 'Add a school'}
          </button>
        )}
      </header>

      {open && (
        <div className="mx-4 mt-4 space-y-3 rounded-xl border border-slate-200 p-4">
          <div className="grid gap-2 sm:grid-cols-2">
            <label className="text-xs font-medium">
              Code
              <input value={code} onChange={(e) => setCode(e.target.value.toUpperCase())}
                     placeholder="QB-SSS"
                     className="mt-1 h-10 w-full rounded-lg border border-slate-300 px-2.5 text-sm" />
            </label>
            <label className="text-xs font-medium">
              Name
              <input value={name} onChange={(e) => setName(e.target.value)}
                     placeholder="Quatre Bornes State Secondary School"
                     className="mt-1 h-10 w-full rounded-lg border border-slate-300 px-2.5 text-sm" />
            </label>
            <label className="text-xs font-medium">
              Type
              <select value={type} onChange={(e) => setType(e.target.value)}
                      className="mt-1 h-10 w-full rounded-lg border border-slate-300 px-2 text-sm">
                <option value="state">State</option>
                <option value="grant_aided">Grant-aided</option>
                <option value="private">Private</option>
                <option value="academy">Academy</option>
              </select>
            </label>
            <label className="text-xs font-medium">
              Education zone
              <select value={zone} onChange={(e) => setZone(Number(e.target.value))}
                      className="mt-1 h-10 w-full rounded-lg border border-slate-300 px-2 text-sm">
                {[1, 2, 3, 4].map((z) => <option key={z} value={z}>Zone {z}</option>)}
              </select>
            </label>
          </div>

          <div>
            <p className="text-xs font-medium">Academic year {year} — term dates</p>
            <p className="text-[11px] text-slate-400">
              Defaults are the Ministry's official 2026 calendar. The school
              calendar, grades 7–13 and standing committees are created with it.
            </p>
            {terms.map((t, i) => (
              <div key={i} className="mt-1.5 flex gap-2">
                <input value={t.name}
                       onChange={(e) => setTerms(terms.map((x, j) =>
                         j === i ? { ...x, name: e.target.value } : x))}
                       className="h-9 flex-1 rounded-lg border border-slate-300 px-2 text-xs" />
                <input type="date" value={t.starts_on}
                       onChange={(e) => setTerms(terms.map((x, j) =>
                         j === i ? { ...x, starts_on: e.target.value } : x))}
                       className="h-9 rounded-lg border border-slate-300 px-2 text-xs" />
                <input type="date" value={t.ends_on}
                       onChange={(e) => setTerms(terms.map((x, j) =>
                         j === i ? { ...x, ends_on: e.target.value } : x))}
                       className="h-9 rounded-lg border border-slate-300 px-2 text-xs" />
              </div>
            ))}
          </div>

          {error && <p className="text-sm text-absent">{error}</p>}
          <button disabled={!code.trim() || !name.trim() || provision.isPending}
                  onClick={() => provision.mutate()}
                  className="h-10 w-full rounded-lg bg-brand text-sm font-semibold text-white disabled:opacity-40">
            {provision.isPending ? 'Provisioning…' : 'Create school'}
          </button>
        </div>
      )}

      <div className="px-4 py-4">
        {schools.isLoading && <p className="text-sm text-slate-500">Loading…</p>}
        {!schools.isLoading && (schools.data ?? []).length === 0 && (
          <p className="py-12 text-center text-sm text-slate-500">No schools in scope.</p>
        )}
        {(schools.data ?? []).length > 0 && (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-slate-500">
                <th className="p-2">School</th><th className="p-2">Zone</th>
                <th className="p-2 text-right">Pupils</th><th className="p-2 text-right">Staff</th>
                <th className="p-2 text-right">Classes</th>
                <th className="p-2 text-right">Attendance</th>
                <th className="p-2 text-right">Below 80%</th>
                <th className="p-2 text-right">Open disc.</th>
              </tr>
            </thead>
            <tbody>
              {(schools.data ?? []).map((s) => (
                <tr key={s.school_id} className="border-t border-slate-100">
                  <td className="p-2">
                    <div className="font-medium">{s.name}</div>
                    <div className="text-xs text-slate-400">
                      {s.code} · {s.type.replace('_', '-')}
                    </div>
                  </td>
                  <td className="p-2 text-xs text-slate-500">{s.zone ?? '—'}</td>
                  <td className="p-2 text-right tabular-nums">{s.pupils}</td>
                  <td className="p-2 text-right tabular-nums">{s.staff}</td>
                  <td className="p-2 text-right tabular-nums">{s.classes}</td>
                  <td className={`p-2 text-right font-semibold tabular-nums ${
                    s.mean_attendance != null && s.mean_attendance < 80 ? 'text-absent' : ''}`}>
                    {s.mean_attendance != null ? `${s.mean_attendance}%` : '—'}
                  </td>
                  <td className="p-2 text-right tabular-nums">{s.below_threshold}</td>
                  <td className="p-2 text-right tabular-nums">{s.open_discrepancies}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        {canProvision && <LogoUpload schools={schools.data ?? []} />}

        <p className="mt-4 text-xs text-slate-400">
          Aggregate only. No named pupil, mark or attendance record is reachable
          from this screen — RLS confines those to the school that holds them.
        </p>
      </div>
    </div>
  )
}
