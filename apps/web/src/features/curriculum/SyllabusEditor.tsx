import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { fetchTerms } from '@/features/marks/api'

interface Unit {
  id: string
  parent_id: string | null
  code: string | null
  title: string
  objectives: string[] | null
  term_id: string | null
  term_name: string | null
  sort_order: number
  depth: number
}

async function fetchSubjects() {
  const { data, error } = await supabase
    .from('subject').select('id,code,name_en').order('name_en')
  if (error) throw error
  return data ?? []
}
async function fetchGrades() {
  const { data, error } = await supabase
    .from('grade_level').select('id,grade,legacy_form').order('grade')
  if (error) throw error
  return data ?? []
}
async function ensureSyllabus(subjectId: string, gradeId: string) {
  const { data, error } = await supabase.rpc('rpc_ensure_syllabus', {
    p_subject: subjectId, p_grade: gradeId,
  })
  if (error) throw error
  return data as string
}
async function fetchTree(syllabusId: string): Promise<Unit[]> {
  const { data, error } = await supabase.rpc('syllabus_tree', { p_syllabus: syllabusId })
  if (error) throw error
  return (data ?? []) as Unit[]
}

/**
 * Syllabus tree editor.
 *
 * The Head of Department works out a syllabus per form and decides, for each
 * term, the portion to be covered. That second part is the one that matters:
 * without a term against each unit, `syllabus_coverage` has nothing to compare
 * recorded teaching against, and the coverage figure on the Rector's dashboard
 * is meaningless.
 *
 * The tree is deliberately shallow — units and topics beneath them. Deeper
 * nesting is possible but nobody maintains it.
 */
export function SyllabusEditor({ schoolId }: { schoolId: string | null }) {
  const qc = useQueryClient()
  const [subjectId, setSubjectId] = useState<string>('')
  const [gradeId, setGradeId] = useState<string>('')
  const [syllabusId, setSyllabusId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [newTitle, setNewTitle] = useState('')
  const [newCode, setNewCode] = useState('')
  const [addingUnder, setAddingUnder] = useState<string | null>(null)

  const subjects = useQuery({ queryKey: ['subjects'], queryFn: fetchSubjects })
  const grades = useQuery({ queryKey: ['grades'], queryFn: fetchGrades })
  const terms = useQuery({ queryKey: ['terms'], queryFn: fetchTerms })

  useEffect(() => {
    if (!subjectId && subjects.data?.length) setSubjectId(subjects.data[0]!.id)
    if (!gradeId && grades.data?.length) setGradeId(grades.data[0]!.id)
  }, [subjects.data, grades.data, subjectId, gradeId])

  // Opening a subject/grade pair creates its syllabus if there isn't one.
  useEffect(() => {
    if (!subjectId || !gradeId) return
    let cancelled = false
    ensureSyllabus(subjectId, gradeId)
      .then((id) => { if (!cancelled) { setSyllabusId(id); setError(null) } })
      .catch((e) => { if (!cancelled) setError(e.message) })
    return () => { cancelled = true }
  }, [subjectId, gradeId])

  const tree = useQuery({
    queryKey: ['syllabus-tree', syllabusId],
    queryFn: () => fetchTree(syllabusId!),
    enabled: Boolean(syllabusId),
  })

  const refresh = () => qc.invalidateQueries({ queryKey: ['syllabus-tree', syllabusId] })

  const add = useMutation({
    mutationFn: async (parentId: string | null) => {
      const siblings = (tree.data ?? []).filter((u) => u.parent_id === parentId)
      const { error } = await supabase.from('syllabus_unit').insert({
        school_id: schoolId, syllabus_id: syllabusId, parent_id: parentId,
        code: newCode.trim() || null, title: newTitle.trim(),
        sort_order: siblings.length + 1,
      })
      if (error) throw error
    },
    onSuccess: () => {
      setNewTitle(''); setNewCode(''); setAddingUnder(null); setError(null)
      void refresh()
    },
    onError: (e: any) => setError(e.message),
  })

  const patch = useMutation({
    mutationFn: async (v: { id: string; fields: Record<string, unknown> }) => {
      const { error } = await supabase
        .from('syllabus_unit').update(v.fields).eq('id', v.id)
      if (error) throw error
    },
    onSuccess: () => void refresh(),
    onError: (e: any) => setError(e.message),
  })

  const drop = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('syllabus_unit').delete().eq('id', id)
      if (error) throw error
    },
    onSuccess: () => void refresh(),
    onError: (e: any) => setError(e.message),
  })

  const untermed = useMemo(
    () => (tree.data ?? []).filter((u) => u.term_id === null).length,
    [tree.data],
  )

  return (
    <div className="px-4 py-4">
      <div className="flex flex-wrap items-center gap-2">
        <select value={subjectId} onChange={(e) => setSubjectId(e.target.value)}
                className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium">
          {(subjects.data ?? []).map((s: any) => (
            <option key={s.id} value={s.id}>{s.name_en}</option>
          ))}
        </select>
        <select value={gradeId} onChange={(e) => setGradeId(e.target.value)}
                className="h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium">
          {(grades.data ?? []).map((g: any) => (
            <option key={g.id} value={g.id}>
              Grade {g.grade}{g.legacy_form ? ` · ${g.legacy_form}` : ''}
            </option>
          ))}
        </select>
        <button onClick={() => setAddingUnder('ROOT')}
                className="h-10 rounded-lg bg-brand px-4 text-sm font-semibold text-white">
          Add unit
        </button>
      </div>

      {error && <p className="mt-3 text-sm text-absent">{error}</p>}

      {untermed > 0 && (tree.data ?? []).length > 0 && (
        <p className="mt-3 rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-800">
          {untermed} unit(s) have no term assigned. Coverage is measured against
          the portion planned for each term, so untermed units never appear in
          the coverage figure.
        </p>
      )}

      {addingUnder === 'ROOT' && (
        <NewUnit code={newCode} title={newTitle}
                 onCode={setNewCode} onTitle={setNewTitle}
                 onCancel={() => setAddingUnder(null)}
                 onSave={() => add.mutate(null)} />
      )}

      {(tree.data ?? []).length === 0 && !tree.isLoading && (
        <p className="py-10 text-center text-sm text-slate-500">
          No syllabus yet for this subject and grade.
        </p>
      )}

      <ul className="mt-3">
        {(tree.data ?? []).map((u) => (
          <li key={u.id} style={{ paddingLeft: `${u.depth * 20}px` }}
              className="border-b border-slate-100 py-2">
            <div className="flex items-start gap-2">
              <div className="min-w-0 flex-1">
                <div className="flex items-baseline gap-2">
                  {u.code && (
                    <span className="font-mono text-[11px] text-slate-400">{u.code}</span>
                  )}
                  <input
                    defaultValue={u.title}
                    onBlur={(e) => e.target.value !== u.title &&
                      patch.mutate({ id: u.id, fields: { title: e.target.value } })}
                    className={`min-w-0 flex-1 rounded border-0 bg-transparent px-1 py-0.5
                                text-sm hover:bg-slate-50 focus:bg-white focus:ring-1
                                focus:ring-brand ${u.depth === 0 ? 'font-semibold' : ''}`}
                  />
                </div>
                <textarea
                  defaultValue={(u.objectives ?? []).join('\n')}
                  rows={Math.max(1, (u.objectives ?? []).length)}
                  placeholder="Learning objectives, one per line"
                  onBlur={(e) => {
                    const next = e.target.value.split('\n').map((s) => s.trim()).filter(Boolean)
                    if (next.join('\n') !== (u.objectives ?? []).join('\n')) {
                      patch.mutate({ id: u.id, fields: { objectives: next } })
                    }
                  }}
                  className="mt-0.5 w-full resize-none rounded border-0 bg-transparent px-1
                             py-0.5 text-xs text-slate-600 hover:bg-slate-50 focus:bg-white
                             focus:ring-1 focus:ring-brand"
                />
              </div>

              <select
                value={u.term_id ?? ''}
                onChange={(e) => patch.mutate({
                  id: u.id, fields: { term_id: e.target.value || null },
                })}
                className={`h-8 shrink-0 rounded border px-1.5 text-xs ${
                  u.term_id ? 'border-slate-200' : 'border-amber-300 bg-amber-50'}`}
              >
                <option value="">No term</option>
                {(terms.data ?? []).map((t: any) => (
                  <option key={t.id} value={t.id}>{t.name}</option>
                ))}
              </select>

              {u.depth === 0 && (
                <button onClick={() => setAddingUnder(u.id)}
                        title="Add a topic beneath this unit"
                        className="shrink-0 px-1 text-xs text-slate-300 hover:text-brand">
                  +
                </button>
              )}
              <button onClick={() => drop.mutate(u.id)}
                      title="Delete, with anything beneath it"
                      className="shrink-0 px-1 text-xs text-slate-300 hover:text-absent">
                ×
              </button>
            </div>

            {addingUnder === u.id && (
              <div style={{ paddingLeft: '20px' }}>
                <NewUnit code={newCode} title={newTitle}
                         onCode={setNewCode} onTitle={setNewTitle}
                         onCancel={() => setAddingUnder(null)}
                         onSave={() => add.mutate(u.id)} />
              </div>
            )}
          </li>
        ))}
      </ul>

      <p className="mt-4 text-xs text-slate-400">
        Edits save when you click away. Deleting a unit removes everything
        beneath it.
      </p>
    </div>
  )
}

function NewUnit({ code, title, onCode, onTitle, onCancel, onSave }: {
  code: string; title: string
  onCode: (v: string) => void; onTitle: (v: string) => void
  onCancel: () => void; onSave: () => void
}) {
  return (
    <div className="my-2 flex gap-2 rounded-lg border border-brand bg-brand-light p-2">
      <input value={code} onChange={(e) => onCode(e.target.value)}
             placeholder="Code"
             className="h-9 w-24 rounded border border-slate-300 px-2 text-xs" />
      <input value={title} onChange={(e) => onTitle(e.target.value)} autoFocus
             placeholder="Title"
             onKeyDown={(e) => e.key === 'Enter' && title.trim() && onSave()}
             className="h-9 flex-1 rounded border border-slate-300 px-2 text-sm" />
      <button disabled={!title.trim()} onClick={onSave}
              className="h-9 rounded bg-brand px-3 text-xs font-semibold text-white disabled:opacity-40">
        Add
      </button>
      <button onClick={onCancel}
              className="h-9 rounded border border-slate-300 px-3 text-xs font-medium">
        Cancel
      </button>
    </div>
  )
}
