import type { LucideIcon } from 'lucide-react'

export interface Staff {
  id: string
  staffId: string
  fullName: string
  firstName: string
  position: string
  academicRole: string
  department: string
  college: string
  email: string
  phone: string
  office: string
  avatarInitials: string
}

export type SectionStatus = 'Active' | 'Completed' | 'Upcoming'

export interface CourseSection {
  id: string
  code: string
  title: string
  section: string
  credits: number
  semester: string
  studentsCount: number
  schedule: { day: string; start: string; end: string }[]
  room: string
  status: SectionStatus
  materials: { name: string; type: 'PDF' | 'Slides' | 'Link' }[]
  assignments: { name: string; due: string; submitted: number; total: number }[]
  announcements: { title: string; date: string; body: string }[]
}

export type AttendanceStatus = 'Present' | 'Absent' | 'Excused' | 'Late'

export interface Student {
  id: string
  studentId: string
  fullName: string
  college: string
  department: string
  level: string
  section: string
  email: string
  attendancePct: number
  gradeStatus: 'On Track' | 'At Risk' | 'Failing' | 'Excellent'
  courses: string[]
}

export interface AttendanceRecord {
  studentId: string
  studentName: string
  status: AttendanceStatus
  absenceCount?: number
  enrollmentStatus?: string
}

export interface GradeRow {
  studentId: string
  studentName: string
  coursework: number
  week7Exam: number
  week12Exam: number
  finalExam: number
  total: number
  grade: string
  gpaPoints: number
}

export interface ScheduleSlot {
  day: string
  start: string
  end: string
  courseCode: string
  courseTitle: string
  room: string
  section: string
  type: 'Lecture' | 'Lab' | 'Tutorial'
}

export interface ExamRecord {
  id: string
  courseCode: string
  courseTitle: string
  section: string
  date: string
  start: string
  end: string
  room: string
  type: 'Midterm' | 'Final' | 'Quiz'
  status: 'Upcoming' | 'Completed'
}

export interface ExamCommittee {
  id: string
  examCourse: string
  role: 'Chief Invigilator' | 'Invigilator' | 'Committee Member'
  date: string
  room: string
}

export type RequestStatus = 'Pending' | 'In Progress' | 'Approved' | 'Rejected' | 'Completed'
export type RequestPriority = 'Low' | 'Normal' | 'High' | 'Urgent'

export interface RequestRecord {
  id: string
  type: string
  origin: 'staff' | 'student'
  originName?: string
  date: string
  status: RequestStatus
  priority: RequestPriority
  details: string
}

export interface Notification {
  id: string
  title: string
  category: 'University' | 'Academic' | 'Department' | 'Requests' | 'System'
  timestamp: string
  read: boolean
  body: string
}

export interface Announcement {
  id: string
  title: string
  category: 'University' | 'Academic' | 'Department' | 'Events'
  date: string
  body: string
  read: boolean
}

export type ServiceKind = 'redirect' | 'form' | 'viewer' | 'info'

export interface ServiceFormField {
  label: string
  type: 'text' | 'textarea' | 'select' | 'date'
  options?: string[]
  placeholder?: string
}

export interface ServiceRecord {
  label: string
  value: string
}

export interface StaffService {
  id: string
  slug: string
  name: string
  description: string
  icon: LucideIcon
  kind: ServiceKind
  destinationLabel?: string
  redirectNote?: string
  fields?: ServiceFormField[]
  records?: ServiceRecord[]
}

/* ---------------------------------------------------------------------- */
/* Advisor / Staff Case Management                                         */
/* ---------------------------------------------------------------------- */

export type InterventionStatus = 'Open' | 'Follow-up Scheduled' | 'Resolved'
export type InterventionOutcome = 'Improved' | 'No Change' | 'Declined' | 'Pending'

export interface Intervention {
  id: string
  studentId: string
  note: string
  createdBy: string
  createdDate: string
  followUpDate: string
  assignedAdvisor: string
  status: InterventionStatus
  /** Snapshot of the student's metrics at the time this intervention was logged, used to measure impact later. */
  baselineAttendancePct: number
  baselineAvgScore: number
}

export type TimelineEventKind = 'grade' | 'attendance' | 'request' | 'intervention'

export interface TimelineEvent {
  id: string
  date: string
  kind: TimelineEventKind
  title: string
  description: string
  tone: 'success' | 'warning' | 'error' | 'info' | 'neutral'
}
