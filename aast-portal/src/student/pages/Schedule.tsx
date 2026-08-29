import { useMemo } from 'react'
import { BookOpen, CalendarDays } from 'lucide-react'
import { useStudentAcademics } from '@student/context/StudentAcademicsContext'
import PageHeader from '@student/components/layout/PageHeader'
import Card from '@student/components/ui/Card'
import StatusBadge from '@student/components/ui/StatusBadge'
import EmptyState from '@student/components/ui/EmptyState'
import { CardSkeleton } from '@student/components/ui/LoadingState'

export default function Schedule() {
  const { academics, loading } = useStudentAcademics()

  const lecturesByWeek = useMemo(() => {
    const grouped = new Map<number, { courseName: string; title: string; completed: boolean; lectureId: string }[]>()
    for (const course of academics?.courses ?? []) {
      for (const lecture of course.lectures) {
        const list = grouped.get(lecture.available_week) ?? []
        list.push({
          courseName: course.course_name,
          title: lecture.title,
          completed: lecture.completed,
          lectureId: lecture.lecture_id,
        })
        grouped.set(lecture.available_week, list)
      }
    }
    return new Map([...grouped.entries()].sort((a, b) => a[0] - b[0]))
  }, [academics])

  return (
    <div>
      <PageHeader
        title="Study Schedule"
        crumbs={[{ label: 'Schedule' }]}
        description={`Lecture plan for ${academics?.semester ?? 'Fall 2026'}. Specific class times are not stored in the academic database yet.`}
      />

      {loading ? (
        <div className="space-y-4">
          <CardSkeleton /><CardSkeleton /><CardSkeleton />
        </div>
      ) : lecturesByWeek.size === 0 ? (
        <EmptyState
          icon={<CalendarDays className="h-6 w-6" />}
          title="No lectures scheduled"
          description="Lecture schedules are not available in the academic database yet."
        />
      ) : (
        <div className="space-y-6">
          {[...lecturesByWeek.entries()].map(([week, lectures]) => (
            <Card key={week}>
              <h2 className="mb-3 font-display text-base font-semibold text-text-primary">Week {week}</h2>
              <div className="divide-y divide-border">
                {lectures.map((lecture) => (
                  <div key={lecture.lectureId} className="flex items-center justify-between py-3 first:pt-0 last:pb-0">
                    <div className="flex items-center gap-3">
                      <BookOpen className="h-4 w-4 text-text-muted" />
                      <div>
                        <p className="text-sm font-medium text-text-primary">{lecture.title}</p>
                        <p className="text-xs text-text-muted">{lecture.courseName}</p>
                      </div>
                    </div>
                    <StatusBadge
                      label={lecture.completed ? 'Completed' : 'Not studied'}
                      tone={lecture.completed ? 'success' : 'warning'}
                    />
                  </div>
                ))}
              </div>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
