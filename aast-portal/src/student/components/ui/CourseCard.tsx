import { Users, Clock, MapPin, Plus, Check, Hourglass } from 'lucide-react'
import type { Course } from '@student/types'
import Card from './Card'
import StatusBadge from './StatusBadge'
import Button from './Button'
import { Link } from 'react-router-dom'

interface CourseCardProps {
  course: Course
  onAction?: (course: Course) => void
  actionState?: 'add' | 'added' | 'full'
}

export default function CourseCard({ course, onAction, actionState }: CourseCardProps) {
  const seatsLeft = course.seatsTotal - course.seatsTaken
  const isFull = seatsLeft <= 0

  return (
    <Card className="flex flex-col gap-3">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="font-mono text-xs font-semibold text-teal-700">{course.code}</p>
          <Link to={`/courses/${course.id}`} className="mt-0.5 block truncate font-display text-base font-semibold text-text-primary hover:text-teal-700">
            {course.title}
          </Link>
          <p className="mt-0.5 text-sm text-text-secondary">{course.instructor}</p>
        </div>
        <StatusBadge
          label={course.status}
          tone={
            course.status === 'Waitlisted'
              ? 'warning'
              : course.status === 'Registered' || course.status === 'In Progress'
              ? 'info'
              : course.status === 'Completed'
              ? 'success'
              : 'neutral'
          }
        />
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
          {seatsLeft > 0 ? `${seatsLeft} seats left` : 'Full'}
        </span>
      </div>

      <div className="flex items-center justify-between border-t border-border pt-3">
        <span className="text-xs font-semibold text-text-muted">{course.credits} Credit Hours</span>
        {onAction && (
          <Button
            size="sm"
            variant={actionState === 'added' ? 'secondary' : isFull ? 'secondary' : 'primary'}
            disabled={actionState === 'added'}
            icon={
              actionState === 'added' ? (
                <Check className="h-3.5 w-3.5" />
              ) : isFull ? (
                <Hourglass className="h-3.5 w-3.5" />
              ) : (
                <Plus className="h-3.5 w-3.5" />
              )
            }
            onClick={() => onAction(course)}
          >
            {actionState === 'added' ? 'Added' : isFull ? 'Join Waitlist' : 'Add Course'}
          </Button>
        )}
      </div>
    </Card>
  )
}
