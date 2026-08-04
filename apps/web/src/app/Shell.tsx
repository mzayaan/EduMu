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
import { CommitteesScreen } from '@/features/committees/CommitteesScreen'
import { MessagesScreen } from '@/features/messages/MessagesScreen'
import { TimetableScreen } from '@/features/timetable/TimetableScreen'
import { ExamsScreen } from '@/features/exams/ExamsScreen'
import { Dashboard } from '@/features/dashboard/Dashboard'
import { CurriculumScreen } from '@/features/curriculum/CurriculumScreen'
import { AdminScreen } from '@/features/admin/AdminScreen'
import { ReportsScreen } from '@/features/reports/ReportsScreen'
import { PlatformConsole } from '@/features/platform/PlatformConsole'
import { GateScreen } from '@/features/gate/GateScreen'
import { YearEndScreen } from '@/features/yearend/YearEndScreen'
import { RoomBookings } from '@/features/rooms/RoomBookings'
import { FeesScreen } from '@/features/fees/FeesScreen'
import { OutboxScreen } from '@/features/notify/OutboxScreen'
import { ChangePassword } from './ChangePassword'

type Tab =
  | 'platform' | 'dashboard' | 'register' | 'lessons' | 'marks' | 'absences'
  | 'conduct' | 'committees' | 'messages' | 'timetable' | 'exams' | 'reports'
  | 'curriculum' | 'admin' | 'discrepancies' | 'eligibility'
  | 'gate' | 'rooms' | 'yearend' | 'fees' | 'outbox'

/**
 * Navigation is capability-driven, not role-driven: a school can move
 * `attendance.read.all` between posts without a code change, and the tab
 * follows. RLS is what actually protects the data either way.
 */
export function Shell({ claims }: { claims: EduClaims }) {
  const tabs: { id: Tab; label: string; visible: boolean }[] = [
    { id: 'platform',      label: 'Platform',      visible: hasCap(claims, 'platform.read.all') },
    { id: 'dashboard',     label: 'Dashboard',     visible: hasCap(claims, 'attendance.read.all') },
    { id: 'register',      label: 'Register',      visible: hasCap(claims, 'attendance.mark') },
    { id: 'lessons',       label: 'Lessons',       visible: hasCap(claims, 'attendance.mark') },
    { id: 'marks',         label: 'Marks',         visible: hasCap(claims, 'marks.enter') },
    { id: 'absences',      label: 'Absence notes', visible: hasCap(claims, 'attendance.resolve') },
    { id: 'conduct',       label: 'Conduct',       visible: hasCap(claims, 'discipline.report') },
    { id: 'committees',    label: 'Committees',    visible: claims.person_type === 'staff' },
    { id: 'messages',      label: 'Messages',      visible: claims.person_type === 'staff' },
    { id: 'timetable',     label: 'Timetable',     visible: hasCap(claims, 'school.manage') },
    { id: 'exams',         label: 'Exams',         visible: hasCap(claims, 'school.manage') },
    { id: 'reports',       label: 'Report books',  visible: hasCap(claims, 'marks.enter') },
    { id: 'curriculum',    label: 'Curriculum',    visible: hasCap(claims, 'marks.enter') },
    { id: 'admin',         label: 'Admin',         visible: claims.person_type === 'staff' },
    { id: 'discrepancies', label: 'Discrepancies', visible: hasCap(claims, 'attendance.read.all') },
    { id: 'eligibility',   label: 'Eligibility',   visible: hasCap(claims, 'attendance.read.all') },
    // The Usher's desk: late arrivals and staff off site. Two separate
    // capabilities because a school may split those duties between posts.
    { id: 'gate',          label: 'Gate',          visible: hasCap(claims, 'attendance.resolve')
                                                          || hasCap(claims, 'staff.manage') },
    { id: 'rooms',         label: 'Rooms',         visible: claims.person_type === 'staff' },
    { id: 'yearend',       label: 'Year end',      visible: hasCap(claims, 'school.manage')
                                                          || hasCap(claims, 'marks.publish') },
    // fees.manage exists so the Bursar can do their job without also being able
    // to republish the timetable. Gating this on school.manage alone locked the
    // one post whose entire job is fees out of the fees screen.
    { id: 'fees',          label: 'Fees',          visible: hasCap(claims, 'fees.manage')
                                                          || hasCap(claims, 'school.manage') },
    { id: 'outbox',        label: 'SMS outbox',    visible: hasCap(claims, 'person.read.all') },
  ]
  const available = tabs.filter((t) => t.visible)
  const [tab, setTab] = useState<Tab>(available[0]?.id ?? 'register')

  // Guardians and pupils never see the staff shell. Pupils were falling through
  // to it and hitting the "no permissions" empty state, because they hold no
  // capabilities by design — their access is relationship-based and decided
  // inside the RLS policies, not by a capability.
  if (claims.person_type === 'guardian' || claims.person_type === 'student') {
    return <GuardianPortal claims={claims} />
  }

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
        <nav className="no-print flex items-center justify-between border-b border-slate-200 px-4">
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

      {tab === 'platform' && <PlatformConsole claims={claims} />}
      {tab === 'dashboard' && <Dashboard claims={claims} />}
      {tab === 'register' && <RegisterScreen claims={claims} />}
      {tab === 'lessons' && <PeriodAttendance claims={claims} />}
      {tab === 'marks' && <MarksGrid claims={claims} />}
      {tab === 'absences' && <AbsenceNotes />}
      {tab === 'conduct' && <DisciplineScreen claims={claims} />}
      {tab === 'committees' && <CommitteesScreen claims={claims} />}
      {tab === 'messages' && <MessagesScreen claims={claims} />}
      {tab === 'timetable' && <TimetableScreen claims={claims} />}
      {tab === 'exams' && <ExamsScreen />}
      {tab === 'reports' && <ReportsScreen claims={claims} />}
      {tab === 'curriculum' && <CurriculumScreen claims={claims} />}
      {tab === 'admin' && <AdminScreen claims={claims} />}
      {tab === 'discrepancies' && <DiscrepancyBoard />}
      {tab === 'eligibility' && <EligibilityScreen />}
      {tab === 'gate' && <GateScreen claims={claims} />}
      {tab === 'rooms' && <RoomBookings claims={claims} />}
      {tab === 'yearend' && <YearEndScreen claims={claims} />}
      {tab === 'fees' && <FeesScreen claims={claims} />}
      {tab === 'outbox' && <OutboxScreen claims={claims} />}
    </div>
  )
}

function SignOut() {
  const [changing, setChanging] = useState(false)
  return (
    <span className="flex items-center gap-3">
      <button
        onClick={() => setChanging(true)}
        className="text-xs font-medium text-slate-400 hover:text-slate-600"
      >
        Change password
      </button>
      {changing && (
        <div className="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4"
             onClick={() => setChanging(false)}>
          <div className="w-full max-w-sm rounded-lg bg-white p-5 shadow-xl"
               onClick={(e) => e.stopPropagation()}>
            <h2 className="mb-3 text-sm font-semibold text-slate-900">Change your password</h2>
            <ChangePassword onDone={() => setTimeout(() => setChanging(false), 1500)} />
          </div>
        </div>
      )}
    <button
      onClick={() => supabase.auth.signOut()}
      className="text-xs font-medium text-slate-400 hover:text-slate-600"
    >
      Sign out
    </button>
    </span>
  )
}
