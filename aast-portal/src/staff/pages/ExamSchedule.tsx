import { useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { FileClock } from 'lucide-react'
import { exams, examCommittees } from '@staff/data/mockData'
import PageHeader from '@staff/components/layout/PageHeader'
import Tabs from '@staff/components/ui/Tabs'
import Card from '@staff/components/ui/Card'
import ExamTable from '@staff/components/ui/ExamTable'
import StatusBadge from '@staff/components/ui/StatusBadge'
import EmptyState from '@staff/components/ui/EmptyState'

const tabs = ['Schedule', 'Results', 'Committees']

export default function ExamSchedule() {
  const [searchParams] = useSearchParams()
  const tabParam = searchParams.get('tab')
  const [activeTab, setActiveTab] = useState(tabs.includes(tabParam ?? '') ? (tabParam as string) : tabs[0])

  useEffect(() => {
    if (tabParam && tabs.includes(tabParam)) setActiveTab(tabParam)
  }, [tabParam])

  const upcoming = exams.filter((e) => e.status === 'Upcoming')
  const completed = exams.filter((e) => e.status === 'Completed')

  return (
    <div>
      <PageHeader title="Exams" crumbs={[{ label: 'Exams' }]} description="Exam schedule, results, and committee assignments." />

      <Card padded={false}>
        <div className="px-2 pt-1">
          <Tabs tabs={tabs} active={activeTab} onChange={setActiveTab} />
        </div>
        <div className="p-5">
          {activeTab === 'Schedule' && (
            <div className="space-y-6">
              <div>
                <h3 className="mb-2 text-sm font-semibold text-text-primary">Upcoming</h3>
                <ExamTable exams={upcoming} />
              </div>
              {completed.length > 0 && (
                <div>
                  <h3 className="mb-2 text-sm font-semibold text-text-primary">Completed</h3>
                  <ExamTable exams={completed} />
                </div>
              )}
            </div>
          )}

          {activeTab === 'Results' && (
            completed.length > 0 ? (
              <div className="divide-y divide-border">
                {completed.map((e) => (
                  <div key={e.id} className="flex items-center justify-between py-3 first:pt-0">
                    <div>
                      <p className="font-mono text-xs font-semibold text-teal-700">{e.courseCode}</p>
                      <p className="text-sm font-medium text-text-primary">{e.courseTitle} — {e.section}</p>
                    </div>
                    <StatusBadge label="Results Published" tone="success" />
                  </div>
                ))}
              </div>
            ) : (
              <EmptyState icon={<FileClock className="h-5 w-5" />} title="No results available yet" description="Results appear here once exams are completed and graded." />
            )
          )}

          {activeTab === 'Committees' && (
            examCommittees.length > 0 ? (
              <div className="divide-y divide-border">
                {examCommittees.map((c) => (
                  <div key={c.id} className="flex items-center justify-between py-3 first:pt-0">
                    <div>
                      <p className="text-sm font-medium text-text-primary">{c.examCourse}</p>
                      <p className="text-xs text-text-muted">
                        {new Date(c.date).toLocaleDateString()} · {c.room}
                      </p>
                    </div>
                    <StatusBadge label={c.role} tone="info" />
                  </div>
                ))}
              </div>
            ) : (
              <EmptyState icon={<FileClock className="h-5 w-5" />} title="No committee assignments" />
            )
          )}
        </div>
      </Card>
    </div>
  )
}
