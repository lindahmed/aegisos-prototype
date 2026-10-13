import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react'
import type { Intervention } from '@staff/types'
import { seedInterventions } from '@staff/data/caseManagementData'
import { staff } from '@staff/data/mockData'

interface NewInterventionInput {
  studentId: string
  note: string
  followUpDate: string
  assignedAdvisor: string
  /** Snapshot of the student's metrics at the moment the note is logged (caller computes this). */
  baselineAttendancePct: number
  baselineAvgScore: number
}

interface CaseManagementContextValue {
  interventions: Intervention[]
  advisorAssignments: Record<string, string>
  addIntervention: (input: NewInterventionInput) => void
  resolveIntervention: (interventionId: string) => void
  setAdvisorForStudent: (studentId: string, advisor: string) => void
  getInterventionsForStudent: (studentId: string) => Intervention[]
  getAssignedAdvisor: (studentId: string) => string | undefined
}

const CaseManagementContext = createContext<CaseManagementContextValue | undefined>(undefined)

function initialAdvisorAssignments(interventions: Intervention[]): Record<string, string> {
  const map: Record<string, string> = {}
  // Seed each student's advisor from their most recent intervention record.
  ;[...interventions]
    .sort((a, b) => new Date(a.createdDate).getTime() - new Date(b.createdDate).getTime())
    .forEach((iv) => {
      map[iv.studentId] = iv.assignedAdvisor
    })
  return map
}

export function CaseManagementProvider({ children }: { children: ReactNode }) {
  const [interventions, setInterventions] = useState<Intervention[]>(seedInterventions)
  const [advisorAssignments, setAdvisorAssignments] = useState<Record<string, string>>(() =>
    initialAdvisorAssignments(seedInterventions),
  )

  const addIntervention = useCallback((input: NewInterventionInput) => {
    const newIntervention: Intervention = {
      id: `iv-${Date.now()}`,
      studentId: input.studentId,
      note: input.note,
      createdBy: staff.fullName,
      createdDate: new Date().toISOString().slice(0, 10),
      followUpDate: input.followUpDate,
      assignedAdvisor: input.assignedAdvisor,
      status: 'Follow-up Scheduled',
      baselineAttendancePct: input.baselineAttendancePct,
      baselineAvgScore: input.baselineAvgScore,
    }
    setInterventions((prev) => [...prev, newIntervention])
    setAdvisorAssignments((prev) => ({ ...prev, [input.studentId]: input.assignedAdvisor }))
  }, [])

  const resolveIntervention = useCallback((interventionId: string) => {
    setInterventions((prev) => prev.map((iv) => (iv.id === interventionId ? { ...iv, status: 'Resolved' } : iv)))
  }, [])

  const setAdvisorForStudent = useCallback((studentId: string, advisor: string) => {
    setAdvisorAssignments((prev) => ({ ...prev, [studentId]: advisor }))
  }, [])

  const getInterventionsForStudent = useCallback(
    (studentId: string) => interventions.filter((iv) => iv.studentId === studentId),
    [interventions],
  )

  const getAssignedAdvisor = useCallback((studentId: string) => advisorAssignments[studentId], [advisorAssignments])

  const value = useMemo(
    () => ({
      interventions,
      advisorAssignments,
      addIntervention,
      resolveIntervention,
      setAdvisorForStudent,
      getInterventionsForStudent,
      getAssignedAdvisor,
    }),
    [
      interventions,
      advisorAssignments,
      addIntervention,
      resolveIntervention,
      setAdvisorForStudent,
      getInterventionsForStudent,
      getAssignedAdvisor,
    ],
  )

  return <CaseManagementContext.Provider value={value}>{children}</CaseManagementContext.Provider>
}

export function useCaseManagement() {
  const ctx = useContext(CaseManagementContext)
  if (!ctx) throw new Error('useCaseManagement must be used within CaseManagementProvider')
  return ctx
}
