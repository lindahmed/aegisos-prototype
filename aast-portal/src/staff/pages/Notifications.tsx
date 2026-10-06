import { useState } from 'react'
import { Bell, CheckCheck } from 'lucide-react'
import { notifications as initialNotifications } from '@staff/data/mockData'
import PageHeader from '@staff/components/layout/PageHeader'
import FilterBar from '@staff/components/ui/FilterBar'
import NotificationItem from '@staff/components/ui/NotificationItem'
import Card from '@staff/components/ui/Card'
import Button from '@staff/components/ui/Button'
import EmptyState from '@staff/components/ui/EmptyState'

const filters = ['All', 'Unread', 'University', 'Academic', 'Department', 'Requests', 'System']

export default function Notifications() {
  const [list, setList] = useState(initialNotifications)
  const [filter, setFilter] = useState('All')

  const filtered = list.filter((n) => {
    if (filter === 'All') return true
    if (filter === 'Unread') return !n.read
    return n.category === filter
  })

  const toggleRead = (id: string) => setList((prev) => prev.map((n) => (n.id === id ? { ...n, read: !n.read } : n)))
  const markAllRead = () => setList((prev) => prev.map((n) => ({ ...n, read: true })))

  return (
    <div>
      <PageHeader
        title="Notifications"
        crumbs={[{ label: 'Notifications' }]}
        description="Requests, academic updates, and department notices."
        actions={
          <Button variant="secondary" size="sm" icon={<CheckCheck className="h-3.5 w-3.5" />} onClick={markAllRead}>
            Mark all as read
          </Button>
        }
      />

      <div className="mb-4">
        <FilterBar options={filters} active={filter} onChange={setFilter} />
      </div>

      {filtered.length > 0 ? (
        <Card padded={false}>
          <div className="divide-y divide-border">
            {filtered.map((n) => (
              <NotificationItem key={n.id} notification={n} onToggleRead={toggleRead} />
            ))}
          </div>
        </Card>
      ) : (
        <EmptyState icon={<Bell className="h-5 w-5" />} title="You're all caught up" description="No notifications match this filter." />
      )}
    </div>
  )
}
