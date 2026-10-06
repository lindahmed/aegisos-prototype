import { useSearchParams } from 'react-router-dom'
import { CalendarRange } from 'lucide-react'
import { scheduleSlots } from '@staff/data/mockData'
import PageHeader from '@staff/components/layout/PageHeader'
import ScheduleGrid from '@staff/components/ui/ScheduleGrid'
import Card from '@staff/components/ui/Card'
import { Link } from 'react-router-dom'

const collegeSchedules = [
  { department: 'Computer Engineering', status: 'Published — Fall 2026' },
  { department: 'Electrical Engineering', status: 'Published — Fall 2026' },
  { department: 'Mechanical Engineering', status: 'Published — Fall 2026' },
  { department: 'Architecture', status: 'Pending final review' },
]

export default function Schedule() {
  const [searchParams] = useSearchParams()
  const view = searchParams.get('view')

  if (view === 'college') {
    return (
      <div>
        <PageHeader
          title="College Schedule"
          crumbs={[{ label: 'Schedule' }, { label: 'College Schedule' }]}
          description="Master timetables published across departments in the college."
          actions={
            <Link to="/schedule" className="text-sm font-semibold text-teal-700 hover:underline">
              View My Schedule
            </Link>
          }
        />
        <div className="space-y-3">
          {collegeSchedules.map((d) => (
            <Card key={d.department} className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-md bg-teal-50 text-teal-600">
                  <CalendarRange className="h-5 w-5" />
                </div>
                <p className="font-medium text-text-primary">{d.department}</p>
              </div>
              <span className="text-sm text-text-secondary">{d.status}</span>
            </Card>
          ))}
        </div>
      </div>
    )
  }

  return (
    <div>
      <PageHeader
        title="My Schedule"
        crumbs={[{ label: 'Schedule' }]}
        description="Your weekly teaching schedule for Fall 2026."
        actions={
          <Link to="/schedule?view=college" className="text-sm font-semibold text-teal-700 hover:underline">
            View College Schedule
          </Link>
        }
      />
      <ScheduleGrid slots={scheduleSlots} />
    </div>
  )
}
