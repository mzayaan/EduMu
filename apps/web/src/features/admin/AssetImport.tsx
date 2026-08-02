import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

interface ImportRow {
  out_row_no: number
  out_tag: string
  out_action: 'create' | 'update' | 'error'
  out_detail: string
}

const COLUMNS = ['tag', 'name', 'category', 'room', 'acquired_on', 'cost', 'condition']

/**
 * Asset register import.
 *
 * Schools already keep this in a spreadsheet, so the job is to accept theirs
 * rather than ask them to retype it. Three things make that survivable:
 *
 *   1. A dry run first, always. Nothing is written until the diff is reviewed.
 *   2. Idempotent on the asset tag — the same file run twice updates rather
 *      than duplicating, because it WILL be run twice.
 *   3. Per-row errors, not a single failure. One unknown room should not
 *      reject four hundred good rows.
 */
export function AssetImport() {
  const qc = useQueryClient()
  const [text, setText] = useState('')
  const [rows, setRows] = useState<ImportRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [committed, setCommitted] = useState(false)

  function parse(): Record<string, string>[] {
    const lines = text.trim().split(/\r?\n/).filter((l) => l.trim())
    if (lines.length === 0) throw new Error('Nothing to import.')

    const split = (line: string) => {
      // Minimal CSV: quoted fields with embedded commas, doubled quotes.
      const out: string[] = []
      let cur = ''
      let inQuotes = false
      for (let i = 0; i < line.length; i++) {
        const c = line[i]
        if (c === '"') {
          if (inQuotes && line[i + 1] === '"') { cur += '"'; i++ }
          else inQuotes = !inQuotes
        } else if (c === ',' && !inQuotes) { out.push(cur); cur = '' }
        else cur += c
      }
      out.push(cur)
      return out.map((s) => s.trim())
    }

    const header = split(lines[0]!).map((h) => h.toLowerCase())
    const unknown = header.filter((h) => h && !COLUMNS.includes(h))
    if (!header.includes('tag') || !header.includes('name')) {
      throw new Error('The header row must include at least "tag" and "name".')
    }
    if (unknown.length) {
      throw new Error(`Unrecognised column(s): ${unknown.join(', ')}. ` +
                      `Expected: ${COLUMNS.join(', ')}.`)
    }

    return lines.slice(1).map((line) => {
      const cells = split(line)
      const row: Record<string, string> = {}
      header.forEach((h, i) => { if (h) row[h] = cells[i] ?? '' })
      return row
    })
  }

  const run = useMutation({
    mutationFn: async (commit: boolean) => {
      const parsed = parse()
      const { data, error } = await supabase.rpc('rpc_import_assets', {
        p_rows: parsed, p_commit: commit,
      })
      if (error) throw error
      return { rows: (data ?? []) as ImportRow[], commit }
    },
    onSuccess: ({ rows, commit }) => {
      setRows(rows); setError(null); setCommitted(commit)
      if (commit) void qc.invalidateQueries({ queryKey: ['assets'] })
    },
    onError: (e: any) => { setError(e.message); setRows(null) },
  })

  const errors = (rows ?? []).filter((r) => r.out_action === 'error')
  const creates = (rows ?? []).filter((r) => r.out_action === 'create')
  const updates = (rows ?? []).filter((r) => r.out_action === 'update')

  return (
    <div className="space-y-3 rounded-xl border border-slate-200 p-4">
      <div>
        <p className="text-sm font-medium">Import an asset register</p>
        <p className="mt-0.5 text-xs text-slate-400">
          Paste CSV with a header row. Required: <code>tag</code>,{' '}
          <code>name</code>. Optional: <code>category</code>, <code>room</code>{' '}
          (a room code such as LAB-C), <code>acquired_on</code>,{' '}
          <code>cost</code>, <code>condition</code>.
        </p>
      </div>

      <textarea
        value={text}
        onChange={(e) => { setText(e.target.value); setRows(null); setCommitted(false) }}
        rows={6}
        spellCheck={false}
        placeholder={'tag,name,category,room\nLAB-001,Bunsen burner,Laboratory,LAB-C\nIT-014,Desktop PC,IT,IT-1'}
        className="w-full rounded-lg border border-slate-300 p-2 font-mono text-xs"
      />

      <div className="flex flex-wrap gap-2">
        <button
          disabled={!text.trim() || run.isPending}
          onClick={() => run.mutate(false)}
          className="h-10 rounded-lg border border-slate-300 px-4 text-sm font-semibold disabled:opacity-40"
        >
          {run.isPending ? 'Checking…' : 'Dry run'}
        </button>
        <button
          disabled={!rows || errors.length > 0 || committed || run.isPending}
          onClick={() => run.mutate(true)}
          className="h-10 rounded-lg bg-brand px-4 text-sm font-semibold text-white disabled:opacity-40"
          title={errors.length > 0 ? 'Fix the errors first' : undefined}
        >
          Import {creates.length + updates.length} row(s)
        </button>
      </div>

      {error && <p className="text-sm text-absent">{error}</p>}

      {rows && (
        <div>
          <p className="text-xs">
            {committed ? (
              <span className="text-present">
                Imported — {creates.length} created, {updates.length} updated.
              </span>
            ) : (
              <>
                <b>{creates.length}</b> to create · <b>{updates.length}</b> to update
                {errors.length > 0 && (
                  <span className="text-absent"> · <b>{errors.length}</b> with errors</span>
                )}
              </>
            )}
          </p>

          {errors.length > 0 && !committed && (
            <p className="mt-1 text-xs text-absent">
              Nothing will be written until every row is valid — one bad room
              should not cost you the other {rows.length - errors.length}.
            </p>
          )}

          <div className="mt-2 max-h-64 overflow-auto rounded-lg border border-slate-200">
            <table className="w-full text-xs">
              <thead className="sticky top-0 bg-slate-50">
                <tr className="text-left text-slate-500">
                  <th className="p-1.5">Row</th>
                  <th className="p-1.5">Tag</th>
                  <th className="p-1.5">Action</th>
                  <th className="p-1.5">Detail</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.out_row_no} className="border-t border-slate-100">
                    <td className="p-1.5 tabular-nums text-slate-400">{r.out_row_no}</td>
                    <td className="p-1.5 font-mono">{r.out_tag || '—'}</td>
                    <td className={`p-1.5 font-semibold ${
                      r.out_action === 'error' ? 'text-absent'
                        : r.out_action === 'create' ? 'text-present' : 'text-late'}`}>
                      {r.out_action}
                    </td>
                    <td className="p-1.5 text-slate-600">{r.out_detail}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}
