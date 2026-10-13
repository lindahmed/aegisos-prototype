import type { PortalStudentAcademics } from '@/lib/portalGrades'

export type CalendarEventType = 'exam' | 'assignment' | 'personal' | 'study_session'
export type CalendarEventSource = 'academic' | 'student' | 'ai'

export interface CalendarEvent {
  id: string
  title: string
  description: string
  startAt: string
  endAt: string
  type: CalendarEventType
  source: CalendarEventSource
  courseId?: string
  urgent?: boolean
  completed?: boolean
}

const storageKey = (studentId: string) => `aegisos-calendar:${studentId}`
const examTypes = new Set(['midterm', 'final', 'exam'])

function semesterStart(currentWeek: number): Date {
  const currentWeekSaturday = new Date()
  currentWeekSaturday.setHours(0, 0, 0, 0)
  const daysSinceSaturday = (currentWeekSaturday.getDay() + 1) % 7
  currentWeekSaturday.setDate(currentWeekSaturday.getDate() - daysSinceSaturday)
  currentWeekSaturday.setDate(currentWeekSaturday.getDate() - (currentWeek - 1) * 7)
  // Calendar events retain the established Monday-Sunday placement grid.
  currentWeekSaturday.setDate(currentWeekSaturday.getDate() + 2)
  return currentWeekSaturday
}

function academicDate(currentWeek: number, dueWeek: number, dayOffset: number, hour: number) {
  const date = semesterStart(currentWeek)
  date.setDate(date.getDate() + (dueWeek - 1) * 7 + dayOffset)
  date.setHours(hour, 0, 0, 0)
  return date
}

export function academicCalendarEvents(academics: PortalStudentAcademics | null): CalendarEvent[] {
  if (!academics) return []
  return academics.courses.flatMap((course) =>
    course.assessments.map((assessment) => {
      const isExam = examTypes.has(assessment.assessment_type)
      const start = academicDate(
        academics.current_week,
        assessment.due_week,
        isExam ? 0 : 6,
        isExam ? 9 : 22,
      )
      const end = new Date(start.getTime() + (isExam ? 120 : 60) * 60_000)
      return {
        id: `academic:${assessment.assessment_id}`,
        title: assessment.name,
        description: `${course.course_name} · ${assessment.max_marks} marks · academic week ${assessment.due_week}`,
        startAt: start.toISOString(),
        endAt: end.toISOString(),
        type: isExam ? 'exam' : 'assignment',
        source: 'academic',
        courseId: course.course_id,
        completed: assessment.mark !== null,
      } satisfies CalendarEvent
    }),
  )
}

export function loadCustomCalendarEvents(studentId: string): CalendarEvent[] {
  try {
    const value = localStorage.getItem(storageKey(studentId))
    if (!value) return []
    const parsed = JSON.parse(value) as CalendarEvent[]
    return Array.isArray(parsed)
      ? parsed.filter((event) => event?.id && event?.title && event?.startAt && event?.endAt)
      : []
  } catch {
    return []
  }
}

export function saveCustomCalendarEvents(studentId: string, events: CalendarEvent[]) {
  try {
    localStorage.setItem(storageKey(studentId), JSON.stringify(events))
  } catch {
    // The calendar stays usable for this session if browser storage is unavailable.
  }
}

export function newStudentCalendarEvent(input: {
  title: string
  description: string
  start: Date
  durationMinutes: number
  type: 'personal' | 'study_session'
}): CalendarEvent {
  const end = new Date(input.start.getTime() + input.durationMinutes * 60_000)
  return {
    id: `student:${Date.now()}:${Math.random().toString(36).slice(2)}`,
    title: input.title.trim(),
    description: input.description.trim(),
    startAt: input.start.toISOString(),
    endAt: end.toISOString(),
    type: input.type,
    source: 'student',
  }
}

function overlaps(start: Date, end: Date, events: CalendarEvent[]) {
  return events.some((event) => start < new Date(event.endAt) && end > new Date(event.startAt))
}

function nextStudySlot(events: CalendarEvent[], offset: number) {
  const now = new Date()
  const first = new Date(now)
  first.setMinutes(0, 0, 0)
  if (first.getHours() >= 18) first.setDate(first.getDate() + 1)
  const candidates: Date[] = []
  for (let day = 0; day < 5; day += 1) {
    for (const hour of [18, 20]) {
      const candidate = new Date(first)
      candidate.setDate(first.getDate() + day)
      candidate.setHours(hour, 0, 0, 0)
      candidates.push(candidate)
    }
  }
  const rotated = [...candidates.slice(offset), ...candidates.slice(0, offset)]
  return rotated.find((start) => {
    const end = new Date(start.getTime() + 90 * 60_000)
    return start > now && !overlaps(start, end, events)
  }) ?? candidates[candidates.length - 1]
}

export function addUrgentAiStudySessions(
  academics: PortalStudentAcademics,
  customEvents: CalendarEvent[],
): { events: CalendarEvent[]; added: CalendarEvent[] } {
  const allEvents = [...academicCalendarEvents(academics), ...customEvents]
  const added: CalendarEvent[] = []
  const urgentCourses = academics.courses.filter(
    (course) =>
      course.risk_level === 'high' ||
      (course.metrics.course_health !== null && course.metrics.course_health < 60 && course.risks.length > 0),
  )
  for (const [index, course] of urgentCourses.entries()) {
    const id = `ai:${academics.semester}:${academics.current_week}:${course.course_id}`
    if (customEvents.some((event) => event.id === id)) continue
    const start = nextStudySlot([...allEvents, ...added], index)
    const end = new Date(start.getTime() + 90 * 60_000)
    added.push({
      id,
      title: `Urgent study: ${course.course_name}`,
      description: `AI scheduled this focus session because ${course.risks.slice(0, 2).map((risk) => risk.message).join('; ')}`,
      startAt: start.toISOString(),
      endAt: end.toISOString(),
      type: 'study_session',
      source: 'ai',
      courseId: course.course_id,
      urgent: true,
    })
  }
  return { events: [...customEvents, ...added], added }
}
