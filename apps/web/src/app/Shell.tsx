import { useState } from 'react'
import { hasCap, supabase, type EduClaims } from '@/lib/supabase'
import { RegisterScreen } from '@/features/attendance/RegisterScreen'
import { DiscrepancyBoard } from '@/features/discrepancy/DiscrepancyBoard'
import { PeriodAttendance } from '@/features/period/PeriodAttendance'
import { EligibilityScreen } from '@/features/eligibility/EligibilityScreen'
import { MarksGrid } from '@/features/marks/MarksGrid'
import { AbsenceNotes } from '@/features/absence/AbsenceNotes'
import { GuardianPortal } from '@/features/guardian/GuardianPortal'
import { DisciplineScreen } from '@/features/discipline/DisciplineScreen'
import { TimetableScreen } from '@/features/timetable/TimetableScreen'

type Tab = 'register' | 'lessons' | 'marks' | 'absences' | 'conduct' | 'timetable' | 'discrepancies' | 'eligibility'

/**
 * Navigation is capability-driven, not role-driven: a school can move
 * `attendance.read.all` between posts without a code change, and the tab
 * follows. RLS is what actually protects the data either way.
 */
export function Shell({ claims }: { claims: EduClaims }) {
  const tabs: { id: Tab; label: string; visible: boolean }[] = [
    { id: 'register',      label: 'Register',      visible: hasCap(claims, 'attendance.mark') },
    { id: 'lessons',       label: 'Lessons',       visible: hasCap(claims, 'attendance.mark') },
    { id: 'marks',         label: 'Marks',         visible: hasCap(claims, 'marks.enter') },
    { id: 'absences',      label: 'Absence notes', visible: hasCap(claims, 'attendance.resolve') },
    { id: 'conduct',       label: 'Conduct',       visible: hasCap(claims, 'discipline.report') },
    { id: 'timetable',     label: 'Timetable',     visible: hasCap(claims, 'school.manage') },
    { id: 'discrepancies', label: 'Discrepancies', visible: hasCap(claims, 'attendance.read.all') },
    { id: 'eligibility',   label: 'Eligibility',   visible: hasCap(claims, 'attendance.read.all') },
  ]
  const available = tabs.filter((t) => t.visible)
  const [tab, setTab] = useState<Tab>(available[0]?.id ?? 'register')

  // Guardians and pupils never see the staff shell.
  if (claims.person_type === 'guardian') return <GuardianPortal claims={claims} />

  if (available.length === 0) {
    return (
      <div className="grid min-h-dvh place-items-center p-6 text-center">
        <div>
          <p className="text-sm text-slate-600">
            Your account has no attendance permissions yet.
          </p>
          <SignOut />
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-dvh bg-white">
      {available.length > 1 && (
        <nav className="flex items-center justify-between border-b border-slate-200 px-4">
          <div className="flex">
            {available.map((t) => (
              <button
                key={t.id}
                onClick={() => setTab(t.id)}
                className={`h-12 px-4 text-sm font-semibold border-b-2 -mb-px ${
                  tab === t.id
                    ? 'border-brand text-brand'
                    : 'border-transparent text-slate-500 hover:text-slate-700'
                }`}
              >
                {t.label}
              </button>
            ))}
          </div>
          <SignOut />
        </nav>
      )}

      {tab === 'register' && <RegisterScreen claims={claims} />}
      {tab === 'lessons' && <PeriodAttendance claims={claims} />}
      {tab === 'marks' && <MarksGrid claims={claims} />}
      {tab === 'absences' && <AbsenceNotes />}
      {tab === 'conduct' && <DisciplineScreen claims={claims} />}
      {tab === 'timetable' && <TimetableScreen claims={claims} />}
      {tab === 'discrepancies' && <DiscrepancyBoard />}
      {tab === 'eligibility' && <EligibilityScreen />}
    </div>
  )
}

function SignOut() {
  return (
    <button
      onClick={() => supabase.auth.signOut()}
      className="text-xs font-medium text-slate-400 hover:text-slate-600"
    >
      Sign out
    </button>
  )
}
