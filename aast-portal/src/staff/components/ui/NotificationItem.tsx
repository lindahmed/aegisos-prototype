import { Landmark, GraduationCap, Building2, Inbox, Settings2 } from 'lucide-react'
import type { Notification } from '@staff/types'

const categoryIcon: Record<Notification['category'], typeof Landmark> = {
  University: Landmark,
  Academic: GraduationCap,
  Department: Building2,
  Requests: Inbox,
  System: Settings2,
}

const categoryColor: Record<Notification['category'], string> = {
  University: 'bg-ink-900/5 text-ink-800',
  Academic: 'bg-teal-50 text-teal-600',
  Department: 'bg-coral-50 text-coral-600',
  Requests: 'bg-warning-100 text-warning',
  System: 'bg-surface-sunk text-text-muted',
}

interface NotificationItemProps {
  notification: Notification
  onToggleRead?: (id: string) => void
}

export default function NotificationItem({ notification, onToggleRead }: NotificationItemProps) {
  const Icon = categoryIcon[notification.category]
  return (
    <div className={`flex gap-3 border-b border-border px-4 py-3.5 last:border-0 ${notification.read ? '' : 'bg-teal-50/40'}`}>
      <div className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-full ${categoryColor[notification.category]}`}>
        <Icon className="h-4 w-4" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-start justify-between gap-2">
          <p className={`text-sm ${notification.read ? 'font-medium text-text-primary' : 'font-semibold text-text-primary'}`}>
            {notification.title}
          </p>
          <span className="shrink-0 text-xs text-text-muted">{notification.timestamp}</span>
        </div>
        <p className="mt-0.5 text-sm text-text-secondary">{notification.body}</p>
        {onToggleRead && (
          <button onClick={() => onToggleRead(notification.id)} className="mt-1.5 text-xs font-semibold text-teal-700 hover:underline">
            {notification.read ? 'Mark as unread' : 'Mark as read'}
          </button>
        )}
      </div>
      {!notification.read && <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-coral-500" />}
    </div>
  )
}
