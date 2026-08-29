import { useMemo, useState } from 'react'
import { AlertTriangle, CheckCircle2, ClipboardList } from 'lucide-react'
import { registeredCourses as initialRegistered, availableCourses as initialAvailable } from '@student/data/mockData'
import type { Course } from '@student/types'
import PageHeader from '@student/components/layout/PageHeader'
import Card from '@student/components/ui/Card'
import CourseCard from '@student/components/ui/CourseCard'
import CourseTable from '@student/components/ui/CourseTable'
import SearchBar from '@student/components/ui/SearchBar'
import FilterBar from '@student/components/ui/FilterBar'
import Modal from '@student/components/ui/Modal'
import Button from '@student/components/ui/Button'
import EmptyState from '@student/components/ui/EmptyState'
import { useToast } from '@student/components/ui/Toast'

const MAX_CREDITS = 18
const filters = ['All', 'Available', 'Waitlisted']

function timesOverlap(a: { day: string; start: string; end: string }, b: { day: string; start: string; end: string }) {
  if (a.day !== b.day) return false
  return a.start < b.end && b.start < a.end
}

function findConflict(course: Course, registered: Course[]): Course | undefined {
  return registered.find((r) => r.schedule.some((rs) => course.schedule.some((cs) => timesOverlap(rs, cs))))
}

export default function Registration() {
  const [registered, setRegistered] = useState<Course[]>(initialRegistered)
  const [available, setAvailable] = useState<Course[]>(initialAvailable)
  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState('All')
  const [conflictCourse, setConflictCourse] = useState<Course | null>(null)
  const [conflictWith, setConflictWith] = useState<Course | null>(null)
  const { showToast } = useToast()

  const totalCredits = registered.reduce((sum, c) => sum + c.credits, 0)
  const creditPct = Math.min(100, Math.round((totalCredits / MAX_CREDITS) * 100))

  const filteredAvailable = useMemo(() => {
    return available.filter((c) => {
      const matchesQuery =
        c.title.toLowerCase().includes(query.toLowerCase()) ||
        c.code.toLowerCase().includes(query.toLowerCase()) ||
        c.instructor.toLowerCase().includes(query.toLowerCase())
      const matchesFilter =
        filter === 'All' || (filter === 'Available' && c.status === 'Available') || (filter === 'Waitlisted' && c.status === 'Waitlisted')
      return matchesQuery && matchesFilter
    })
  }, [available, query, filter])

  const handleAdd = (course: Course) => {
    const conflict = findConflict(course, registered)
    if (conflict) {
      setConflictCourse(course)
      setConflictWith(conflict)
      return
    }
    if (totalCredits + course.credits > MAX_CREDITS) {
      showToast(`Adding this course exceeds the ${MAX_CREDITS} credit-hour limit.`, 'error')
      return
    }
    commitAdd(course)
  }

  const commitAdd = (course: Course) => {
    setRegistered((prev) => [...prev, { ...course, status: course.status === 'Waitlisted' ? 'Waitlisted' : 'Registered' }])
    setAvailable((prev) => prev.filter((c) => c.id !== course.id))
    showToast(`${course.code} added to your schedule.`)
    setConflictCourse(null)
    setConflictWith(null)
  }

  const handleDrop = (course: Course) => {
    setRegistered((prev) => prev.filter((c) => c.id !== course.id))
    setAvailable((prev) => [...prev, { ...course, status: 'Available' }])
    showToast(`${course.code} dropped from your schedule.`, 'warning')
  }

  return (
    <div>
      <PageHeader
        title="Course Registration"
        crumbs={[{ label: 'Registration' }]}
        description="Add or drop courses for Fall 2026. Changes are saved instantly."
      />

      <div className="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
        <Card className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-md bg-teal-50 text-teal-600">
            <ClipboardList className="h-5 w-5" />
          </div>
          <div>
            <p className="text-sm text-text-secondary">Registration Status</p>
            <p className="font-semibold text-success">Open — closes Sep 1</p>
          </div>
        </Card>
        <Card>
          <div className="flex items-center justify-between">
            <p className="text-sm text-text-secondary">Credit Hours</p>
            <p className="font-mono text-sm font-semibold text-text-primary">
              {totalCredits} / {MAX_CREDITS}
            </p>
          </div>
          <div className="mt-2 h-2 w-full overflow-hidden rounded-full bg-surface-sunk">
            <div
              className={`h-full rounded-full ${creditPct >= 90 ? 'bg-coral-500' : 'bg-teal-600'}`}
              style={{ width: `${creditPct}%` }}
            />
          </div>
        </Card>
        <Card className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-md bg-ink-900/5 text-ink-800">
            <CheckCircle2 className="h-5 w-5" />
          </div>
          <div>
            <p className="text-sm text-text-secondary">Registered Courses</p>
            <p className="font-semibold text-text-primary">{registered.length} courses</p>
          </div>
        </Card>
      </div>

      <div className="mb-3 flex items-center justify-between">
        <h2 className="font-display text-lg font-semibold text-text-primary">My Registered Courses</h2>
      </div>
      {registered.length > 0 ? (
        <CourseTable courses={registered} onDrop={handleDrop} />
      ) : (
        <EmptyState
          icon={<ClipboardList className="h-5 w-5" />}
          title="No courses registered yet"
          description="Browse available courses below and add them to your schedule."
        />
      )}

      <div className="mb-3 mt-8 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h2 className="font-display text-lg font-semibold text-text-primary">Available Courses</h2>
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
          <SearchBar value={query} onChange={setQuery} placeholder="Search by course, code, or instructor" className="sm:w-72" />
          <FilterBar options={filters} active={filter} onChange={setFilter} />
        </div>
      </div>

      {filteredAvailable.length > 0 ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {filteredAvailable.map((c) => (
            <CourseCard key={c.id} course={c} onAction={handleAdd} />
          ))}
        </div>
      ) : (
        <EmptyState
          icon={<ClipboardList className="h-5 w-5" />}
          title="No matching courses"
          description="Try a different search term or clear your filters."
        />
      )}

      <Modal
        open={!!conflictCourse}
        onClose={() => setConflictCourse(null)}
        title="Schedule Conflict Detected"
        footer={
          <>
            <Button variant="secondary" onClick={() => setConflictCourse(null)}>
              Cancel
            </Button>
            <Button variant="danger" onClick={() => conflictCourse && commitAdd(conflictCourse)}>
              Add Anyway
            </Button>
          </>
        }
      >
        {conflictCourse && conflictWith && (
          <div className="flex gap-3">
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-error-100 text-error">
              <AlertTriangle className="h-4 w-4" />
            </div>
            <p className="text-sm text-text-secondary">
              <span className="font-semibold text-text-primary">{conflictCourse.code}</span> overlaps with{' '}
              <span className="font-semibold text-text-primary">{conflictWith.code}</span> already on your schedule.
              Adding both may prevent you from attending one of them. Review your schedule before proceeding.
            </p>
          </div>
        )}
      </Modal>
    </div>
  )
}
