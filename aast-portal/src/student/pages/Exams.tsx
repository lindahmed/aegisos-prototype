import { useMemo, useState } from 'react'
import { FileClock, MapPin, Armchair, CalendarDays } from 'lucide-react'
import { useStudentAcademics } from '@student/context/StudentAcademicsContext'
import PageHeader from '@student/components/layout/PageHeader'
import FilterBar from '@student/components/ui/FilterBar'
import Card from '@student/components/ui/Card'
import StatusBadge from '@student/components/ui/StatusBadge'
import EmptyState from '@student/components/ui/EmptyState'
import { CardSkeleton } from '@student/components/ui/LoadingState'

const filters = ['All', 'Upcoming', 'Completed']

interface ExamRecord {
  id: string
  courseCode: string
  courseTitle: string
  name: string
  dueWeek: number
  mark: number | null
  maxMarks: number
  status: 'Upcoming' | 'Completed'
}

export default function Exams() {
  const [filter, setFilter] = useState('Upcoming')
  const { academics, loading } = useStudentAcademics()

  const exams = useMemo<ExamRecord[]>(() => {
    const result: ExamRecord[] = []
    for (const course of academics?.courses ?? []) {
      for (const assessment of course.assessments) {
        if (['midterm', 'final', 'exam'].includes(assessment.assessment_type)) {
          result.push({
            id: assessment.assessment_id,
            courseCode: course.course_id,
            courseTitle: course.course_name,
            name: assessment.name,
            dueWeek: assessment.due_week,
            mark: assessment.mark,
            maxMarks: assessment.max_marks,
            status: assessment.mark !== null ? 'Completed' : 'Upcoming',
          })
        }
      }
    }
    return result.sort((a, b) => a.dueWeek - b.dueWeek)
  }, [academics])

  const filtered = exams.filter((e) => filter === 'All' || e.status === filter)

  return (
    <div>
      <PageHeader
        title="Exam Schedule"
        crumbs={[{ label: 'Exams' }]}
        description={`Assessments for ${academics?.semester ?? 'Fall 2026'}. Exact dates, rooms, and seats are not stored in the academic database yet.`}
        actions={<FilterBar options={filters} active={filter} onChange={setFilter} />}
      />

      {loading ? (
        <div className="space-y-3">
          <CardSkeleton /><CardSkeleton /><CardSkeleton />
        </div>
      ) : filtered.length > 0 ? (
        <div className="space-y-3">
          {filtered.map((e) => (
            <Card key={e.id} accent={e.status === 'Upcoming' ? 'coral' : 'none'} className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div className="flex items-center gap-4">
                <div className="flex h-14 w-14 shrink-0 flex-col items-center justify-center rounded-md bg-ink-900 text-white">
                  <span className="text-[10px] font-semibold uppercase leading-tight">Week</span>
                  <span className="font-display text-lg font-bold leading-tight">{e.dueWeek}</span>
                </div>
                <div>
                  <p className="font-mono text-xs font-semibold text-teal-700">{e.courseCode}</p>
                  <p className="font-display text-base font-semibold text-text-primary">{e.name}</p>
                  <p className="text-sm text-text-secondary">{e.courseTitle}</p>
                  <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-xs text-text-secondary">
                    <span className="flex items-center gap-1">
                      <CalendarDays className="h-3 w-3" /> Due week {e.dueWeek}
                    </span>
                    <span className="flex items-center gap-1">
                      <MapPin className="h-3 w-3" /> Room TBD
                    </span>
                    <span className="flex items-center gap-1">
                      <Armchair className="h-3 w-3" /> Seat TBD
                    </span>
                  </div>
                </div>
              </div>
              <div className="flex items-center gap-3">
                {e.mark !== null && (
                  <span className="font-mono text-sm font-semibold text-success">{e.mark.toFixed(1)}/{e.maxMarks.toFixed(0)} marks</span>
                )}
                <StatusBadge label={e.status} tone={e.status === 'Upcoming' ? 'warning' : e.status === 'Completed' ? 'success' : 'error'} />
              </div>
            </Card>
          ))}
        </div>
      ) : (
        <EmptyState icon={<FileClock className="h-5 w-5" />} title="No exams found" description="Nothing matches this filter yet." />
      )}
    </div>
  )
}
