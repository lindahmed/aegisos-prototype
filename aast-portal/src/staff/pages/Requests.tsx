import { useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Inbox } from 'lucide-react'
import { requests as initialRequests } from '@staff/data/mockData'
import type { RequestStatus } from '@staff/types'
import PageHeader from '@staff/components/layout/PageHeader'
import Tabs from '@staff/components/ui/Tabs'
import Card from '@staff/components/ui/Card'
import FilterBar from '@staff/components/ui/FilterBar'
import StatusBadge from '@staff/components/ui/StatusBadge'
import EmptyState from '@staff/components/ui/EmptyState'
import { useToast } from '@staff/components/ui/Toast'

const originTabs = ['My Requests', 'Student Requests']
const statusFilters = ['All', 'Pending', 'In Progress', 'Approved', 'Rejected', 'Completed']

const statusTone: Record<RequestStatus, 'success' | 'warning' | 'error' | 'info' | 'neutral'> = {
  Pending: 'warning',
  'In Progress': 'info',
  Approved: 'success',
  Rejected: 'error',
  Completed: 'neutral',
}

const priorityTone: Record<string, 'error' | 'warning' | 'info' | 'neutral'> = {
  Urgent: 'error',
  High: 'warning',
  Normal: 'info',
  Low: 'neutral',
}

export default function Requests() {
  const [searchParams] = useSearchParams()
  const originParam = searchParams.get('origin')
  const [list, setList] = useState(initialRequests)
  const [activeTab, setActiveTab] = useState(originParam === 'student' || originParam === 'Exam' ? 'Student Requests' : originTabs[0])
  const [statusFilter, setStatusFilter] = useState('All')

  useEffect(() => {
    if (originParam === 'student') setActiveTab('Student Requests')
  }, [originParam])

  const origin = activeTab === 'My Requests' ? 'staff' : 'student'
  const filtered = list.filter((r) => {
    const matchesOrigin = r.origin === origin
    const matchesStatus = statusFilter === 'All' || r.status === statusFilter
    const matchesExamFilter = originParam !== 'Exam' || r.type.toLowerCase().includes('exam')
    return matchesOrigin && matchesStatus && matchesExamFilter
  })

  const { showToast } = useToast()

  const updateStatus = (id: string, status: RequestStatus) => {
    setList((prev) => prev.map((r) => (r.id === id ? { ...r, status } : r)))
    showToast(`Request marked as ${status}.`)
  }

  return (
    <div>
      <PageHeader title="Requests" crumbs={[{ label: 'Requests' }]} description="Track requests you've submitted and requests awaiting your review." />

      <Card padded={false}>
        <div className="px-2 pt-1">
          <Tabs tabs={originTabs} active={activeTab} onChange={setActiveTab} />
        </div>
        <div className="border-b border-border px-5 py-3">
          <FilterBar options={statusFilters} active={statusFilter} onChange={setStatusFilter} />
        </div>
        <div className="p-5">
          {filtered.length > 0 ? (
            <div className="space-y-3">
              {filtered.map((r) => (
                <div key={r.id} className="rounded-md border border-border p-4">
                  <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
                    <div>
                      <div className="flex items-center gap-2">
                        <p className="font-medium text-text-primary">{r.type}</p>
                        <StatusBadge label={r.priority} tone={priorityTone[r.priority]} />
                      </div>
                      {r.originName && <p className="text-xs text-text-muted">From {r.originName}</p>}
                      <p className="mt-1 text-sm text-text-secondary">{r.details}</p>
                      <p className="mt-1 text-xs text-text-muted">{new Date(r.date).toLocaleDateString()}</p>
                    </div>
                    <div className="flex shrink-0 items-center gap-2">
                      <StatusBadge label={r.status} tone={statusTone[r.status]} />
                    </div>
                  </div>
                  {activeTab === 'Student Requests' && r.status === 'Pending' && (
                    <div className="mt-3 flex gap-2 border-t border-border pt-3">
                      <button
                        onClick={() => updateStatus(r.id, 'Approved')}
                        className="rounded-md bg-success-100 px-3 py-1.5 text-xs font-semibold text-success hover:bg-success/20"
                      >
                        Approve
                      </button>
                      <button
                        onClick={() => updateStatus(r.id, 'Rejected')}
                        className="rounded-md bg-error-100 px-3 py-1.5 text-xs font-semibold text-error hover:bg-error/20"
                      >
                        Reject
                      </button>
                      <button
                        onClick={() => updateStatus(r.id, 'In Progress')}
                        className="rounded-md bg-teal-100 px-3 py-1.5 text-xs font-semibold text-teal-700 hover:bg-teal-100/70"
                      >
                        Mark In Progress
                      </button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          ) : (
            <EmptyState icon={<Inbox className="h-5 w-5" />} title="No requests found" description="Nothing matches this filter yet." />
          )}
        </div>
      </Card>
    </div>
  )
}
