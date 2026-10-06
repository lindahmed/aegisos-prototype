const RAILWAY_API_BASE_URL = 'https://web-production-3a6ad.up.railway.app'
const LEGACY_RAILWAY_API_BASE_URL = 'https://backend-production-6069.up.railway.app'

const configuredApiBaseUrl = import.meta.env.VITE_API_BASE_URL?.replace(/\/+$/, '')

export const API_BASE_URL =
  configuredApiBaseUrl && configuredApiBaseUrl !== LEGACY_RAILWAY_API_BASE_URL
    ? configuredApiBaseUrl
    : RAILWAY_API_BASE_URL

export interface PortalCourse {
  course_id: string
  course_name: string
  semester: string
  student_count: number
}

export interface PortalGradeRow {
  student_id: string
  student_name: string
  coursework_mark: number
  week7_exam_mark: number
  week12_exam_mark: number
  final_exam_mark: number
  total_score: number
  letter_grade: string
  gpa_points: number | null
}

export interface PortalCourseGradebook {
  course: {
    course_id: string
    course_name: string
    semester: string
  }
  rows: PortalGradeRow[]
}

export interface PortalStudentGradeRecord {
  course_id: string
  course_code: string
  course_name: string
  semester: string
  enrollment_status: string
  coursework_mark: number | null
  week7_exam_mark: number | null
  week12_exam_mark: number | null
  final_exam_mark: number | null
  total_score: number | null
  letter_grade: string | null
  gpa_points: number | null
  grade_source: 'gradebook' | 'transcript' | 'none'
  grade_posted: boolean
}

export interface PortalSemesterSummary {
  semester: string
  gpa: number | null
  courses_graded: number
  standing: string
}

export interface PortalStudentGradeReport {
  student: {
    student_id: string
    name: string
    major: string
    year: number
    gpa: number | null
    courses: string[]
  }
  completed_courses: number
  semesters: PortalSemesterSummary[]
  records: PortalStudentGradeRecord[]
}

export interface PortalGradebookUpdateRow {
  student_id: string
  coursework_mark: number
  week7_exam_mark: number
  week12_exam_mark: number
  final_exam_mark: number
}

export type PortalAttendanceStatus = 'Present' | 'Absent' | 'Excused' | 'Late'

export interface PortalAttendanceRow {
  student_id: string
  student_name: string
  status: PortalAttendanceStatus
  enrollment_status: string
  absence_count: number
}

export interface PortalCourseAttendance {
  course: {
    course_id: string
    course_name: string
    semester: string
  }
  session_date: string
  week_number: number
  rows: PortalAttendanceRow[]
  dropped_student_ids?: string[]
  restored_student_ids?: string[]
}

export interface PortalAttendanceUpdateRow {
  student_id: string
  status: PortalAttendanceStatus
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    headers: { 'Content-Type': 'application/json', ...(init?.headers ?? {}) },
    ...init,
  })
  if (!response.ok) {
    const payload = (await response.json().catch(() => null)) as { detail?: string } | null
    throw new Error(payload?.detail ?? `Request failed with status ${response.status}`)
  }
  return (await response.json()) as T
}

export type MessageParticipantType = 'student' | 'staff'

export interface MessageContact {
  type: MessageParticipantType
  id: string
  name: string
  subtitle: string
}

export interface PortalMessage {
  message_id: string
  sender_type: MessageParticipantType
  sender_id: string
  sender_name: string
  recipient_type: MessageParticipantType | null
  recipient_id: string | null
  recipient_name: string
  is_broadcast: boolean
  body: string
  created_at: string
  read: boolean
}

export function getMessageContacts(actorType: MessageParticipantType, actorId: string) {
  const search = new URLSearchParams({ actor_type: actorType, actor_id: actorId }).toString()
  return request<{ actor: MessageContact; contacts: MessageContact[] }>(`/messages/contacts?${search}`)
}

export function getMessages(actorType: MessageParticipantType, actorId: string) {
  const search = new URLSearchParams({ actor_type: actorType, actor_id: actorId }).toString()
  return request<{ messages: PortalMessage[] }>(`/messages?${search}`)
}

export function loginPortalStaff(staffId: string, password: string) {
  return request<{ staff_id: string; name: string; valid: boolean }>('/portal/staff/login', {
    method: 'POST',
    body: JSON.stringify({ staff_id: staffId, password }),
  })
}

export function sendPortalMessage(input: {
  sender_type: MessageParticipantType
  sender_id: string
  recipient_type?: MessageParticipantType
  recipient_id?: string
  is_broadcast?: boolean
  body: string
}) {
  return request<{ message: PortalMessage }>('/messages', {
    method: 'POST',
    body: JSON.stringify(input),
  })
}

export function markPortalMessagesRead(
  actorType: MessageParticipantType,
  actorId: string,
  messageIds: string[],
) {
  return request<{ read: string[] }>('/messages/read', {
    method: 'PUT',
    body: JSON.stringify({ actor_type: actorType, actor_id: actorId, message_ids: messageIds }),
  })
}

export function listPortalCourses() {
  return request<{ courses: PortalCourse[] }>('/portal/courses')
}

export function getPortalCourseGradebook(courseId: string, semester?: string) {
  const search = semester ? `?${new URLSearchParams({ semester }).toString()}` : ''
  return request<PortalCourseGradebook>(`/portal/courses/${courseId}/grades${search}`)
}

export function savePortalCourseGradebook(courseId: string, semester: string, rows: PortalGradebookUpdateRow[]) {
  return request<PortalCourseGradebook>(`/portal/courses/${courseId}/grades`, {
    method: 'PUT',
    body: JSON.stringify({ semester, rows }),
  })
}

export function getPortalCourseAttendance(courseId: string, sessionDate: string) {
  const search = new URLSearchParams({ session_date: sessionDate }).toString()
  return request<PortalCourseAttendance>(
    `/portal/courses/${encodeURIComponent(courseId)}/attendance?${search}`,
  )
}

export function savePortalCourseAttendance(
  courseId: string,
  sessionDate: string,
  rows: PortalAttendanceUpdateRow[],
) {
  return request<PortalCourseAttendance>(
    `/portal/courses/${encodeURIComponent(courseId)}/attendance`,
    {
      method: 'PUT',
      body: JSON.stringify({ session_date: sessionDate, rows }),
    },
  )
}

export function getPortalStudentGrades(studentId: string) {
  return request<PortalStudentGradeReport>(`/portal/students/${studentId}/grades`)
}

export interface PortalAssessment {
  assessment_id: string
  name: string
  assessment_type: 'assignment' | 'lab' | 'quiz' | 'midterm' | 'final' | 'exam'
  weight: number
  due_week: number
  covered_lecture_ids: string[]
  mark: number | null
  max_marks: number
}

export interface PortalLecture {
  lecture_id: string
  lecture_number: number
  title: string
  available_week: number
  completed: boolean
}

export interface PortalCourseMaterial {
  material_id: string
  title: string
  material_type: string
  lecture_id: string | null
  source_url: string | null
}

export interface PortalCourseTwin {
  course_id: string
  course_name: string
  semester: string
  current_week: number
  assessments: PortalAssessment[]
  lectures: PortalLecture[]
  materials: PortalCourseMaterial[]
  completed_lectures: PortalLecture[]
  unstudied_lectures: PortalLecture[]
  metrics: {
    assignment_average: number | null
    lab_average: number | null
    quiz_average: number | null
    exam_percentage: number | null
    weighted_grade: number | null
    lecture_completion: number
    assessment_completion: number
    course_health: number | null
    trend: string
    previous_course_health: number | null
  }
  risks: {
    code: string
    severity: 'low' | 'medium' | 'high'
    message: string
    related_lecture_ids: string[]
    related_assessment_ids: string[]
  }[]
  risk_level: 'low' | 'medium' | 'high' | null
}

export interface PortalStudentAcademics {
  student: {
    student_id: string
    name: string
    major: string
    year: number
    gpa: number | null
    courses: string[]
  }
  semester: string
  current_week: number
  courses: PortalCourseTwin[]
  grades: PortalStudentGradeReport
}

export function getPortalStudentAcademics(studentId: string) {
  return request<PortalStudentAcademics>(`/portal/students/${studentId}/academics`)
}

export interface PortalNotification {
  id: string
  type: 'grade' | 'exam' | 'risk' | 'attendance'
  category: 'Grades' | 'Registration' | 'Financial' | 'System'
  title: string
  body: string
  timestamp: string
  read: boolean
}

export function getPortalStudentNotifications(studentId: string) {
  return request<{ notifications: PortalNotification[] }>(
    `/portal/students/${encodeURIComponent(studentId)}/notifications`,
  )
}

export function setPortalNotificationsRead(studentId: string, notificationIds: string[], read = true) {
  return request<{ notifications: PortalNotification[] }>(
    `/portal/students/${encodeURIComponent(studentId)}/notifications/read`,
    {
      method: 'PUT',
      body: JSON.stringify({ notification_ids: notificationIds, read }),
    },
  )
}

export interface ValidatedStudent {
  student_id: string
  name: string
  major: string
  year: number
  gpa: number | null
  courses: string[]
}

export async function validateStudentId(studentId: string): Promise<ValidatedStudent | null> {
  const response = await fetch(`${API_BASE_URL}/student/${encodeURIComponent(studentId)}`)
  if (response.status === 404) return null
  if (!response.ok) throw new Error(`Validation failed (${response.status})`)
  return response.json() as Promise<ValidatedStudent>
}

export async function validateStaffId(staffId: string): Promise<boolean> {
  const response = await fetch(`${API_BASE_URL}/portal/staff/${encodeURIComponent(staffId)}`)
  if (response.status === 404) return false
  if (!response.ok) throw new Error(`Validation failed (${response.status})`)
  return true
}
