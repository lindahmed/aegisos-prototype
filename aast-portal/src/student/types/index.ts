import type { LucideIcon } from 'lucide-react'

export type StudentStatus = 'Active' | 'On Probation' | 'Leave of Absence'

export interface Student {
  id: string
  regNumber: string
  fullName: string
  firstName: string
  program: string
  faculty: string
  level: string
  academicAdvisor: string
  status: StudentStatus
  email: string
  phone: string
  address: string
  dateOfBirth: string
  nationality: string
  gpa: number
  cumulativeGpa: number
  creditsCompleted: number
  creditsRequired: number
  currentSemester: string
  avatarInitials: string
}

export type CourseStatus = 'Registered' | 'Available' | 'Completed' | 'In Progress' | 'Waitlisted'

export interface Course {
  id: string
  code: string
  title: string
  credits: number
  instructor: string
  schedule: { day: string; start: string; end: string }[]
  room: string
  seatsTotal: number
  seatsTaken: number
  status: CourseStatus
  prerequisites?: string[]
  description: string
  materials: { name: string; type: 'PDF' | 'Slides' | 'Link' }[]
  assignments: { name: string; due: string; status: 'Submitted' | 'Pending' | 'Graded'; grade?: string }[]
}

export interface GradeRecord {
  courseCode: string
  courseTitle: string
  credits: number
  grade: string
  gradePoints: number
  semester: string
}

export interface SemesterSummary {
  semester: string
  gpa: number
  creditsAttempted: number
  creditsEarned: number
  standing: string
}

export interface ExamRecord {
  id: string
  courseCode: string
  courseTitle: string
  date: string
  start: string
  end: string
  room: string
  seat: string
  status: 'Upcoming' | 'Completed' | 'Missed'
}

export interface Announcement {
  id: string
  title: string
  type: 'Cancelled' | 'Rescheduled' | 'Location Changed' | 'General'
  publishedAt: string
  courseName?: string
  instructor?: string
  originalDate?: string
  originalTime?: string
  newDate?: string
  newTime?: string
  originalLocation?: string
  newLocation?: string
  body: string
  read: boolean
}

export interface Notification {
  id: string
  title: string
  category: 'Grades' | 'Registration' | 'Financial' | 'System'
  timestamp: string
  read: boolean
  body: string
}

export interface Invoice {
  id: string
  label: string
  semester: string
  amount: number
  paid: number
  invoiceDate: string
  dueDate: string
  status: 'Paid' | 'Partially Paid' | 'Unpaid' | 'Overdue'
}

export interface PaymentRecord {
  id: string
  date: string
  amount: number
  method: string
  reference: string
}

export interface DocumentRecord {
  id: string
  name: string
  category: string
  issuedDate: string
  status: 'Ready' | 'Processing' | 'Requires Action'
}

export interface ScheduleSlot {
  day: string
  start: string
  end: string
  courseCode: string
  courseTitle: string
  room: string
  type: 'Lecture' | 'Lab' | 'Tutorial'
}

export type ServiceCategoryName = 'Academic' | 'Learning' | 'Financial' | 'Student Services' | 'Account & Data'

export type ServiceKind = 'redirect' | 'form' | 'viewer' | 'tool' | 'info'

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

export interface Service {
  id: string
  slug: string
  name: string
  category: ServiceCategoryName
  description: string
  icon: LucideIcon
  kind: ServiceKind
  // redirect
  destinationLabel?: string
  redirectNote?: string
  // form
  fields?: ServiceFormField[]
  // viewer
  records?: ServiceRecord[]
  // info
  paragraphs?: string[]
  tips?: string[]
}
