import { useState } from 'react'
import { Megaphone } from 'lucide-react'
import { announcements as initialAnnouncements } from '@student/data/mockData'
import type { Announcement } from '@student/types'
import PageHeader from '@student/components/layout/PageHeader'
import FilterBar from '@student/components/ui/FilterBar'
import AnnouncementCard from '@student/components/ui/AnnouncementCard'
import Modal from '@student/components/ui/Modal'
import StatusBadge from '@student/components/ui/StatusBadge'
import EmptyState from '@student/components/ui/EmptyState'

const filters = ['All', 'Cancelled', 'Rescheduled', 'Location Changed', 'General']

const announcementTone = {
  Cancelled: 'error',
  Rescheduled: 'info',
  'Location Changed': 'warning',
  General: 'neutral',
} as const

function formatSchedule(date?: string, time?: string) {
  if (!date) return 'Not specified'

  return new Date(date + 'T' + (time ?? '00:00') + ':00').toLocaleString(undefined, {
    weekday: 'long',
    month: 'short',
    day: 'numeric',
    ...(time ? { hour: 'numeric', minute: '2-digit' } : {}),
  })
}

export default function Announcements() {
  const [list, setList] = useState<Announcement[]>(initialAnnouncements)
  const [filter, setFilter] = useState('All')
  const [selected, setSelected] = useState<Announcement | null>(null)

  const filtered = list
    .filter((announcement) => filter === 'All' || announcement.type === filter)
    .sort((a, b) => new Date(b.publishedAt).getTime() - new Date(a.publishedAt).getTime())

  const open = (announcement: Announcement) => {
    setSelected(announcement)
    setList((previous) => previous.map((item) => (
      item.id === announcement.id ? { ...item, read: true } : item
    )))
  }

  return (
    <div>
      <PageHeader
        title="Announcements"
        crumbs={[{ label: 'Announcements' }]}
        description="Important lecture changes and academic updates."
        actions={<FilterBar options={filters} active={filter} onChange={setFilter} />}
      />

      {filtered.length > 0 ? (
        <div className="grid grid-cols-1 items-start gap-4 lg:grid-cols-2">
          {filtered.map((announcement) => (
            <AnnouncementCard
              key={announcement.id}
              announcement={announcement}
              onOpen={() => open(announcement)}
            />
          ))}
        </div>
      ) : (
        <EmptyState
          icon={<Megaphone className="h-5 w-5" />}
          title="No new announcements."
          description="There are no academic updates in this category."
        />
      )}

      <Modal open={!!selected} onClose={() => setSelected(null)} title={selected?.title ?? ''}>
        {selected && (
          <div>
            <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
              <StatusBadge label={selected.type} tone={announcementTone[selected.type]} />
              <span className="text-xs text-text-muted">
                {new Date(selected.publishedAt).toLocaleString(undefined, {
                  dateStyle: 'medium',
                  timeStyle: 'short',
                })}
              </span>
            </div>

            {(selected.courseName || selected.instructor) && (
              <p className="mb-2 text-sm font-semibold text-text-primary">
                {[selected.courseName, selected.instructor].filter(Boolean).join(' · ')}
              </p>
            )}
            <p className="text-sm leading-relaxed text-text-secondary">{selected.body}</p>

            {(selected.originalDate || selected.originalLocation) && (
              <dl className="mt-5 divide-y divide-border rounded-md bg-surface-sunk px-4 text-sm">
                {selected.originalDate && (
                  <div className="flex flex-col gap-0.5 py-3 sm:flex-row sm:justify-between sm:gap-4">
                    <dt className="text-text-muted">
                      {selected.type === 'Rescheduled' ? 'Previous schedule' : 'Original schedule'}
                    </dt>
                    <dd className="font-medium text-text-primary">
                      {formatSchedule(selected.originalDate, selected.originalTime)}
                    </dd>
                  </div>
                )}
                {selected.newDate && (
                  <div className="flex flex-col gap-0.5 py-3 sm:flex-row sm:justify-between sm:gap-4">
                    <dt className="text-text-muted">New schedule</dt>
                    <dd className="font-medium text-teal-700">
                      {formatSchedule(selected.newDate, selected.newTime)}
                    </dd>
                  </div>
                )}
                {selected.originalLocation && (
                  <div className="flex flex-col gap-0.5 py-3 sm:flex-row sm:justify-between sm:gap-4">
                    <dt className="text-text-muted">Location change</dt>
                    <dd className="font-medium text-text-primary">
                      {selected.originalLocation} → {selected.newLocation}
                    </dd>
                  </div>
                )}
              </dl>
            )}
          </div>
        )}
      </Modal>
    </div>
  )
}
