import { Link } from 'react-router-dom'
import { Users, Clock, MapPin } from 'lucide-react'
import type { CourseSection } from '@staff/types'
import Card from './Card'
import StatusBadge from './StatusBadge'

const statusTone: Record<CourseSection['status'], 'success' | 'info' | 'neutral'> = {
  Active: 'info',
  Completed: 'success',
  Upcoming: 'neutral',
}

export default function CourseCard({ course }: { course: CourseSection }) {
  return (
    <Card className="flex flex-col gap-3">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="font-mono text-xs font-semibold text-teal-700">
            {course.code} · {course.section}
          </p>
          <Link to={`/courses/${course.id}`} className="mt-0.5 block truncate font-display text-base font-semibold text-text-primary hover:text-teal-700">
            {course.title}
          </Link>
          <p className="mt-0.5 text-sm text-text-secondary">{course.semester}</p>
        </div>
        <StatusBadge label={course.status} tone={statusTone[course.status]} />
      </div>

      <div className="flex flex-wrap gap-x-4 gap-y-1.5 text-xs text-text-secondary">
        <span className="flex items-center gap-1.5">
          <Clock className="h-3.5 w-3.5 text-text-muted" />
          {course.schedule.map((s) => `${s.day} ${s.start}`).join(', ')}
        </span>
        <span className="flex items-center gap-1.5">
          <MapPin className="h-3.5 w-3.5 text-text-muted" />
          {course.room}
        </span>
        <span className="flex items-center gap-1.5">
          <Users className="h-3.5 w-3.5 text-text-muted" />
          {course.studentsCount} students
        </span>
      </div>

      <div className="flex items-center justify-between border-t border-border pt-3">
        <span className="text-xs font-semibold text-text-muted">{course.credits} Credit Hours</span>
        <Link to={`/courses/${course.id}`} className="text-xs font-semibold text-teal-700 hover:underline">
          View Course →
        </Link>
      </div>
    </Card>
  )
}
