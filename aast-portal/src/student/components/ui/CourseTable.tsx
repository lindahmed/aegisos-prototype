import { Link } from 'react-router-dom'
import { X } from 'lucide-react'
import type { Course } from '@student/types'
import StatusBadge from './StatusBadge'
import { useLanguage } from '@/context/LanguageContext'

interface CourseTableProps {
  courses: Course[]
  onDrop?: (course: Course) => void
}

export default function CourseTable({ courses, onDrop }: CourseTableProps) {
  const { t } = useLanguage()

  return (
    <div className="overflow-x-auto rounded-lg border border-border bg-surface shadow-card">
      <table className="w-full min-w-[720px] text-left text-sm">
        <thead>
          <tr className="border-b border-border bg-surface-raised text-xs font-semibold uppercase tracking-wide text-text-muted">
            {['Course', 'Instructor', 'Schedule', 'Room', 'Credits', 'Status'].map((label) => (
              <th key={label} className="px-4 py-3">{t(label)}</th>
            ))}
            {onDrop && <th className="px-4 py-3 text-end">{t('Action')}</th>}
          </tr>
        </thead>
        <tbody>
          {courses.map((c) => (
            <tr key={c.id} className="border-b border-border last:border-0 hover:bg-surface-sunk/60">
              <td className="px-4 py-3.5">
                <Link to={`/courses/${c.id}`} className="font-mono text-xs font-semibold text-teal-700">
                  {c.code}
                </Link>
                <p className="font-medium text-text-primary">{c.title}</p>
              </td>
              <td className="px-4 py-3.5 text-text-secondary">{c.instructor}</td>
              <td className="px-4 py-3.5 text-text-secondary">
                {c.schedule.map((s) => `${s.day} ${s.start}–${s.end}`).join(', ')}
              </td>
              <td className="px-4 py-3.5 text-text-secondary">{c.room}</td>
              <td className="px-4 py-3.5 font-mono text-text-secondary">{c.credits}</td>
              <td className="px-4 py-3.5">
                <StatusBadge label={c.status} tone={c.status === 'Waitlisted' ? 'warning' : 'info'} />
              </td>
              {onDrop && (
                <td className="px-4 py-3.5 text-right">
                  <button
                    onClick={() => onDrop(c)}
                    className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-semibold text-error hover:bg-error-100"
                  >
                    <X className="h-3.5 w-3.5" />
                    {t('Drop')}
                  </button>
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
