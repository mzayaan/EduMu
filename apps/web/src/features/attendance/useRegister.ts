import { useCallback, useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { enqueueAttendanceMark, drain } from '@/lib/outbox'
import type { AttendanceStatus, SessionType } from '@/types/database'
import * as api from './api'

export function useRegister(
  classGroupId: string | null,
  date: string,
  session: SessionType,
  schoolId: string | null,
) {
  const qc = useQueryClient()
  const [localStatus, setLocalStatus] = useState<Record<string, AttendanceStatus>>({})

  const roster = useQuery({
    queryKey: ['roster', classGroupId, date],
    queryFn: () => api.fetchRoster(classGroupId!, date),
    enabled: Boolean(classGroupId),
  })

  const sessionQ = useQuery({
    queryKey: ['session', classGroupId, date, session],
    queryFn: () => api.fetchSession(classGroupId!, date, session),
    enabled: Boolean(classGroupId),
  })

  const records = useQuery({
    queryKey: ['records', sessionQ.data?.id],
    queryFn: () => api.fetchRecords(sessionQ.data!.id),
    enabled: Boolean(sessionQ.data?.id),
  })

  // Server state, overlaid with anything marked locally but not yet synced.
  const statuses = useMemo(() => {
    const merged: Record<string, AttendanceStatus> = {}
    for (const r of records.data ?? []) merged[r.student_id] = r.status
    return { ...merged, ...localStatus }
  }, [records.data, localStatus])

  useEffect(() => { setLocalStatus({}) }, [classGroupId, date, session])

  const open = useMutation({
    mutationFn: () => api.openRegister(classGroupId!, date, session),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['session', classGroupId, date, session] })
    },
  })

  const close = useMutation({
    mutationFn: () => api.closeRegister(sessionQ.data!.id),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['session', classGroupId, date, session] })
    },
  })

  /** Optimistic, offline-safe. The tap always lands; the network catches up. */
  const mark = useCallback(
    async (studentId: string, status: AttendanceStatus) => {
      const sid = sessionQ.data?.id
      if (!sid || !schoolId) return
      setLocalStatus((s) => ({ ...s, [studentId]: status }))
      await enqueueAttendanceMark({
        school_id: schoolId,
        attendance_session_id: sid,
        student_id: studentId,
        status,
      })
      void drain()
    },
    [sessionQ.data?.id, schoolId],
  )

  const counts = useMemo(() => {
    const list = roster.data ?? []
    let present = 0, absent = 0, late = 0, authorised = 0
    for (const s of list) {
      switch (statuses[s.student_id]) {
        case 'present': case 'school_activity': present++; break
        case 'late': late++; present++; break
        case 'absent_unauth': absent++; break
        case 'absent_auth': case 'on_leave': authorised++; break
      }
    }
    return { total: list.length, present, absent, late, authorised }
  }, [roster.data, statuses])

  return {
    roster, session: sessionQ, records, statuses, counts,
    mark, open, close,
    isLoading: roster.isLoading || sessionQ.isLoading,
  }
}
