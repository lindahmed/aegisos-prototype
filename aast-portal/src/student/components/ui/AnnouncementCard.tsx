import type { Announcement } from '@student/types'
import Card from './Card'
import StatusBadge from './StatusBadge'

const categoryTone: Record<Announcement['category'], 'info' | 'warning' | 'success' | 'neutral'> = {
  Academic: 'info',
  Financial: 'warning',
  Events: 'success',
  General: 'neutral',
}

export default function AnnouncementCard({ announcement, onOpen }: { announcement: Announcement; onOpen?: () => void }) {
  return (
    <Card
      accent={announcement.read ? 'none' : 'coral'}
      className="cursor-pointer transition-shadow hover:shadow-raised"
      padded={true}
    >
      <button onClick={onOpen} className="w-full text-left">
        <div className="flex items-start justify-between gap-3">
          <StatusBadge label={announcement.category} tone={categoryTone[announcement.category]} />
          <span className="shrink-0 text-xs text-text-muted">
            {new Date(announcement.date).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}
          </span>
        </div>
        <p className="mt-2 font-display text-base font-semibold text-text-primary">{announcement.title}</p>
        <p className="mt-1 line-clamp-2 text-sm text-text-secondary">{announcement.body}</p>
      </button>
    </Card>
  )
}
