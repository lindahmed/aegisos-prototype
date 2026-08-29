export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'http://127.0.0.1:8000'

export interface PortalCourse {
  course_id: string
  course_name: string
  semester: string
  student_count: number
}

export interface PortalGradeRow {
  student_id: string
  student_name: string
  assignment_score: number
  midterm_score: number
  final_score: number
  total_score: number
  letter_grade: string
  gpa_points: number
}

export interface PortalCourseGradebook {
  course: {
    course_id: string
    course_name: string
    semester: string
  }
  rows: PortalGradeRow[]
}

export interface PortalStudentGradeRecord extends PortalGradeRow {
  course_id: string
  course_name: string
  semester: string
}

export interface PortalSemesterSummary {
  semester: string
  gpa: number
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
  semesters: PortalSemesterSummary[]
  records: PortalStudentGradeRecord[]
}

export interface PortalGradebookUpdateRow {
  student_id: string
  assignment_score: number
  midterm_score: number
  final_score: number
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
  percentage: number | null
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
