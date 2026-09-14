import { CalendarClock, CircleX, MapPin, Megaphone } from 'lucide-react'
import type { Announcement } from '@student/types'
import Card from './Card'
import StatusBadge from './StatusBadge'

const typeTone: Record<Announcement['type'], 'info' | 'warning' | 'error' | 'neutral'> = {
  Cancelled: 'error',
  Rescheduled: 'info',
  'Location Changed': 'warning',
  General: 'neutral',
}

const typeAccent: Record<Announcement['type'], 'coral' | 'teal' | 'ink' | 'none'> = {
  Cancelled: 'coral',
  Rescheduled: 'teal',
  'Location Changed': 'ink',
  General: 'none',
}

const typeIcon = {
  Cancelled: CircleX,
  Rescheduled: CalendarClock,
  'Location Changed': MapPin,
  General: Megaphone,
}

function formatSchedule(date?: string, time?: string) {
  if (!date) return 'Not specified'

  const value = new Date(date + 'T' + (time ?? '00:00') + ':00')
  return value.toLocaleString(undefined, {
    weekday: 'long',
    month: 'short',
    day: 'numeric',
    ...(time ? { hour: 'numeric', minute: '2-digit' } : {}),
  })
}

export default function AnnouncementCard({
  announcement,
  onOpen,
}: {
  announcement: Announcement
  onOpen?: () => void
}) {
  const Icon = typeIcon[announcement.type]

  return (
    <Card
      accent={typeAccent[announcement.type]}
      className="transition-shadow hover:shadow-raised"
      padded
    >
      <button
        type="button"
        onClick={onOpen}
        className="w-full text-left"
        aria-label={'Open ' + announcement.title + ' announcement'}
      >
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-center gap-2">
            <span className="flex h-8 w-8 items-center justify-center rounded-full bg-surface-sunk text-text-secondary">
              <Icon className="h-4 w-4" />
            </span>
            <StatusBadge label={announcement.type} tone={typeTone[announcement.type]} />
          </div>
          {!announcement.read && (
            <span className="mt-2 h-2 w-2 shrink-0 rounded-full bg-coral-500" aria-label="Unread" />
          )}
        </div>

        <p className="mt-3 font-display text-base font-semibold text-text-primary">{announcement.title}</p>
        {(announcement.courseName || announcement.instructor) && (
          <p className="mt-1 text-xs font-semibold text-teal-700">
            {[announcement.courseName, announcement.instructor].filter(Boolean).join(' · ')}
          </p>
        )}
        <p className="mt-2 text-sm leading-relaxed text-text-secondary">{announcement.body}</p>

        {announcement.type === 'Location Changed' ? (
          <div className="mt-4 rounded-md bg-surface-sunk p-3 text-xs">
            <p className="text-text-muted">Date &amp; time</p>
            <p className="font-medium text-text-primary">
              {formatSchedule(announcement.originalDate, announcement.originalTime)}
            </p>
            <div className="mt-2 grid grid-cols-[1fr_auto_1fr] items-center gap-2">
              <div>
                <p className="text-text-muted">From</p>
                <p className="font-medium text-text-primary">{announcement.originalLocation}</p>
              </div>
              <span className="text-text-muted" aria-hidden="true">→</span>
              <div>
                <p className="text-text-muted">To</p>
                <p className="font-medium text-text-primary">{announcement.newLocation}</p>
              </div>
            </div>
          </div>
        ) : announcement.originalDate ? (
          <div className="mt-4 grid gap-2 rounded-md bg-surface-sunk p-3 text-xs sm:grid-cols-2">
            <div>
              <p className="text-text-muted">
                {announcement.type === 'Cancelled' ? 'Original lecture' : 'Previous schedule'}
              </p>
              <p className="font-medium text-text-primary">
                {formatSchedule(announcement.originalDate, announcement.originalTime)}
              </p>
            </div>
            {announcement.newDate && (
              <div>
                <p className="text-text-muted">New lecture</p>
                <p className="font-medium text-teal-700">
                  {formatSchedule(announcement.newDate, announcement.newTime)}
                </p>
              </div>
            )}
          </div>
        ) : null}

        <p className="mt-3 text-xs text-text-muted">
          Announced {new Date(announcement.publishedAt).toLocaleString(undefined, {
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit',
          })}
        </p>
      </button>
    </Card>
  )
}
