import { useState } from 'react'
import { Bell, CheckCheck } from 'lucide-react'
import PageHeader from '@student/components/layout/PageHeader'
import FilterBar from '@student/components/ui/FilterBar'
import NotificationItem from '@student/components/ui/NotificationItem'
import Card from '@student/components/ui/Card'
import Button from '@student/components/ui/Button'
import EmptyState from '@student/components/ui/EmptyState'
import { useNotifications } from '@student/context/NotificationsContext'

const filters = ['All', 'Unread', 'Grades', 'Registration', 'Financial', 'System']

export default function Notifications() {
  const [filter, setFilter] = useState('All')
  const { notifications, loading, error, toggleRead, markAllRead } = useNotifications()

  const filtered = notifications.filter((n) => {
    if (filter === 'All') return true
    if (filter === 'Unread') return !n.read
    return n.category === filter
  })

  return (
    <div>
      <PageHeader
        title="Notifications"
        crumbs={[{ label: 'Notifications' }]}
        description="Grade updates, registration alerts, and system notices."
        actions={
          <Button variant="secondary" size="sm" icon={<CheckCheck className="h-3.5 w-3.5" />} onClick={markAllRead}>
            Mark all as read
          </Button>
        }
      />

      <div className="mb-4">
        <FilterBar options={filters} active={filter} onChange={setFilter} />
      </div>

      {error && <p className="mb-4 rounded-md bg-error-100 px-4 py-3 text-sm text-error">{error}</p>}

      {filtered.length > 0 ? (
        <Card padded={false}>
          <div className="divide-y divide-border">
            {filtered.map((n) => (
              <NotificationItem key={n.id} notification={n} onToggleRead={(id) => void toggleRead(id)} />
            ))}
          </div>
        </Card>
      ) : loading ? (
        <EmptyState icon={<Bell className="h-5 w-5" />} title="Loading notifications" description="Checking the shared academic feed…" />
      ) : (
        <EmptyState icon={<Bell className="h-5 w-5" />} title="You're all caught up" description="No notifications match this filter." />
      )}
    </div>
  )
}
