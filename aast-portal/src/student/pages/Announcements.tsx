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

const filters = ['All', 'Academic', 'Financial', 'Events', 'General']

export default function Announcements() {
  const [list, setList] = useState<Announcement[]>(initialAnnouncements)
  const [filter, setFilter] = useState('All')
  const [selected, setSelected] = useState<Announcement | null>(null)

  const filtered = list.filter((a) => filter === 'All' || a.category === filter)

  const open = (a: Announcement) => {
    setSelected(a)
    setList((prev) => prev.map((x) => (x.id === a.id ? { ...x, read: true } : x)))
  }

  return (
    <div>
      <PageHeader
        title="Announcements"
        crumbs={[{ label: 'Announcements' }]}
        description="University-wide updates and department notices."
        actions={<FilterBar options={filters} active={filter} onChange={setFilter} />}
      />

      {filtered.length > 0 ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {filtered.map((a) => (
            <AnnouncementCard key={a.id} announcement={a} onOpen={() => open(a)} />
          ))}
        </div>
      ) : (
        <EmptyState icon={<Megaphone className="h-5 w-5" />} title="No announcements" description="Nothing in this category yet." />
      )}

      <Modal open={!!selected} onClose={() => setSelected(null)} title={selected?.title ?? ''}>
        {selected && (
          <div>
            <div className="mb-3 flex items-center justify-between">
              <StatusBadge label={selected.category} tone="info" />
              <span className="text-xs text-text-muted">{new Date(selected.date).toLocaleDateString()}</span>
            </div>
            <p className="text-sm leading-relaxed text-text-secondary">{selected.body}</p>
          </div>
        )}
      </Modal>
    </div>
  )
}
