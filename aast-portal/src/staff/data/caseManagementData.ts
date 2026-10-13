import { students, requests } from './mockData'
import type { Student, Intervention, TimelineEvent } from '@staff/types'

/** Advisors available for assignment. In a real deployment this would come from a staff directory service. */
export const advisorNames = ['Dr. Omar Fathallah', 'Dr. Salma Ibrahim', 'Dr. Hassan Fathy', 'Eng. Nourhan Adel']

function hashString(value: string): number {
  let hash = 0
  for (let i = 0; i < value.length; i++) hash = (hash * 31 + value.charCodeAt(i)) >>> 0
  return hash
}

/**
 * Self-contained deterministic "current performance" estimate for a student, in the 45-97 range.
 * Kept independent of the (buggy) course-grade generator elsewhere so case-management math never NaNs.
 */
export function estimatedAverageScore(student: Student): number {
  const offset = hashString(student.id) % 20
  const base = Math.round(student.attendancePct * 0.6 + offset)
  return Math.min(97, Math.max(45, base))
}

/** Students flagged as needing advisor attention: At Risk or Failing grade status. */
export function getAtRiskStudents(): Student[] {
  return students.filter((s) => s.gradeStatus === 'At Risk' || s.gradeStatus === 'Failing')
}

function findStudent(id: string): Student {
  const s = students.find((st) => st.id === id)
  if (!s) throw new Error(`Unknown seed student id: ${id}`)
  return s
}

// Seed a few example cases so the feature is demonstrable out of the box.
const ahmed = findStudent('st4') // At Risk
const nour = findStudent('st5') // Failing
const mostafa = findStudent('st10') // Failing

export const seedInterventions: Intervention[] = [
  {
    id: 'iv1',
    studentId: ahmed.id,
    note: 'Missed two consecutive CSE 301 labs and scored low on the Week 7 quiz. Met with the student to discuss workload and time management; recommended the peer-tutoring program.',
    createdBy: 'Dr. Omar Fathallah',
    createdDate: '2026-08-05',
    followUpDate: '2026-08-26',
    assignedAdvisor: 'Dr. Omar Fathallah',
    status: 'Resolved',
    baselineAttendancePct: Math.max(30, ahmed.attendancePct - 18),
    baselineAvgScore: Math.max(40, estimatedAverageScore(ahmed) - 12),
  },
  {
    id: 'iv2',
    studentId: nour.id,
    note: 'Grade status dropped to Failing after the midterm. Student cited a family emergency earlier in the semester. Flagged for close monitoring ahead of the Week 12 exam.',
    createdBy: 'Dr. Omar Fathallah',
    createdDate: '2026-08-28',
    followUpDate: '2026-09-25',
    assignedAdvisor: 'Dr. Salma Ibrahim',
    status: 'Follow-up Scheduled',
    baselineAttendancePct: nour.attendancePct,
    baselineAvgScore: estimatedAverageScore(nour),
  },
  {
    id: 'iv3',
    studentId: mostafa.id,
    note: 'Referred to academic advising after two missed assignments in a row. First check-in did not show improvement; escalating to the department academic-support committee.',
    createdBy: 'Dr. Omar Fathallah',
    createdDate: '2026-07-20',
    followUpDate: '2026-08-15',
    assignedAdvisor: 'Dr. Hassan Fathy',
    status: 'Resolved',
    baselineAttendancePct: mostafa.attendancePct + 9,
    baselineAvgScore: estimatedAverageScore(mostafa) + 10,
  },
]

/**
 * Whether a logged intervention improved the student's performance.
 * Compares the baseline snapshot (captured when the note was created) against current metrics,
 * once the follow-up date has passed or the case has been marked Resolved.
 */
export function getInterventionOutcome(
  intervention: Intervention,
  student: Student,
  today: Date = new Date(),
): 'Improved' | 'No Change' | 'Declined' | 'Pending' {
  const followUpDue = new Date(intervention.followUpDate) <= today
  if (intervention.status !== 'Resolved' && !followUpDue) return 'Pending'

  const currentAttendance = student.attendancePct
  const currentAvgScore = estimatedAverageScore(student)
  const delta = currentAttendance - intervention.baselineAttendancePct + (currentAvgScore - intervention.baselineAvgScore)

  if (delta >= 6) return 'Improved'
  if (delta <= -6) return 'Declined'
  return 'No Change'
}

/** Builds a unified, date-sorted timeline of grades, attendance, requests, and interventions for one student. */
export function buildStudentTimeline(student: Student, interventions: Intervention[]): TimelineEvent[] {
  const events: TimelineEvent[] = []

  events.push({
    id: `attendance-${student.id}`,
    date: new Date().toISOString().slice(0, 10),
    kind: 'attendance',
    title: `Current attendance: ${student.attendancePct}%`,
    description:
      student.attendancePct < 80
        ? 'Below the 80% attendance threshold for this term.'
        : 'Attendance is within the expected range.',
    tone: student.attendancePct < 75 ? 'error' : student.attendancePct < 85 ? 'warning' : 'success',
  })

  events.push({
    id: `grade-${student.id}`,
    date: '2026-08-24',
    kind: 'grade',
    title: `Current standing: ${student.gradeStatus}`,
    description: `Estimated running average across enrolled courses (${student.courses.join(', ')}) is ${estimatedAverageScore(student)}/100.`,
    tone: student.gradeStatus === 'Failing' ? 'error' : student.gradeStatus === 'At Risk' ? 'warning' : 'success',
  })

  requests
    .filter((r) => r.originName === student.fullName)
    .forEach((r) => {
      events.push({
        id: `request-${r.id}`,
        date: r.date,
        kind: 'request',
        title: r.type,
        description: r.details,
        tone: r.status === 'Approved' || r.status === 'Completed' ? 'success' : r.status === 'Rejected' ? 'error' : 'info',
      })
    })

  interventions
    .filter((iv) => iv.studentId === student.id)
    .forEach((iv) => {
      events.push({
        id: `intervention-${iv.id}`,
        date: iv.createdDate,
        kind: 'intervention',
        title: `Intervention logged by ${iv.createdBy}`,
        description: iv.note,
        tone: 'info',
      })
    })

  return events.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
}
