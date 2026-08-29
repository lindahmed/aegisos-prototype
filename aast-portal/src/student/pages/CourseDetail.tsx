import { useMemo, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { FileText, Link2, Presentation, Clock, MapPin, Users, ArrowLeft, BookOpen } from 'lucide-react'
import { useStudentAcademics } from '@student/context/StudentAcademicsContext'
import PageHeader from '@student/components/layout/PageHeader'
import Card from '@student/components/ui/Card'
import StatusBadge from '@student/components/ui/StatusBadge'
import Tabs from '@student/components/ui/Tabs'
import EmptyState from '@student/components/ui/EmptyState'
import { CardSkeleton } from '@student/components/ui/LoadingState'

const materialIcon: Record<string, React.ElementType> = { PDF: FileText, Slides: Presentation, Link: Link2 }

const tabs = ['Overview', 'Materials', 'Assignments', 'Lectures']

export default function CourseDetail() {
  const { id } = useParams()
  const [activeTab, setActiveTab] = useState(tabs[0])
  const { academics, loading } = useStudentAcademics()

  const course = useMemo(() => academics?.courses.find((c) => c.course_id === id), [academics, id])

  if (loading) {
    return (
      <div>
        <PageHeader title="Course" description="Loading…" />
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
          <div className="lg:col-span-2"><CardSkeleton /></div>
          <div><CardSkeleton /></div>
        </div>
      </div>
    )
  }

  if (!course) {
    return (
      <EmptyState
        icon={<FileText className="h-5 w-5" />}
        title="Course not found"
        description="This course is not registered in your academic record."
        action={
          <Link to="/courses" className="text-sm font-semibold text-teal-700 hover:underline">
            Back to Courses
          </Link>
        }
      />
    )
  }

  return (
    <div>
      <PageHeader
        title={course.course_name}
        crumbs={[{ label: 'Courses', to: '/courses' }, { label: course.course_id }]}
        description={course.course_id}
        actions={<StatusBadge label="In Progress" tone="info" />}
      />

      <Link to="/courses" className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-text-secondary hover:text-teal-700">
        <ArrowLeft className="h-3.5 w-3.5" />
        Back to courses
      </Link>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <Card padded={false}>
            <div className="px-2 pt-1">
              <Tabs tabs={tabs} active={activeTab} onChange={setActiveTab} />
            </div>
            <div className="p-5">
              {activeTab === 'Overview' && (
                <div>
                  <p className="text-sm leading-relaxed text-text-secondary">
                    Course health: <span className="font-mono font-semibold">{course.metrics.course_health?.toFixed(0) ?? '—'}</span>/100.
                    Lecture completion: <span className="font-mono font-semibold">{course.metrics.lecture_completion.toFixed(0)}%</span>.
                    Assessment completion: <span className="font-mono font-semibold">{course.metrics.assessment_completion.toFixed(0)}%</span>.
                  </p>
                  {course.risks.length > 0 && (
                    <div className="mt-4">
                      <p className="text-xs font-semibold uppercase tracking-wide text-text-muted">Active Risks</p>
                      <div className="mt-1.5 space-y-2">
                        {course.risks.map((r) => (
                          <div key={r.code} className="rounded-md bg-surface-sunk px-3 py-2 text-sm text-text-secondary">
                            {r.message}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              )}

              {activeTab === 'Materials' && (
                <>
                  {course.materials.length > 0 ? (
                    <div className="divide-y divide-border">
                      {course.materials.map((m) => {
                        const Icon = materialIcon[m.material_type] ?? FileText
                        return (
                          <div key={m.material_id} className="flex items-center gap-3 py-3 first:pt-0">
                            <div className="flex h-9 w-9 items-center justify-center rounded-md bg-teal-50 text-teal-600">
                              <Icon className="h-4 w-4" />
                            </div>
                            <p className="text-sm font-medium text-text-primary">{m.title}</p>
                          </div>
                        )
                      })}
                    </div>
                  ) : (
                    <EmptyState icon={<FileText className="h-5 w-5" />} title="No materials posted yet" />
                  )}
                </>
              )}

              {activeTab === 'Assignments' && (
                <>
                  {course.assessments.length > 0 ? (
                    <div className="divide-y divide-border">
                      {course.assessments.map((a) => (
                        <div key={a.assessment_id} className="flex items-center justify-between py-3 first:pt-0">
                          <div>
                            <p className="text-sm font-medium text-text-primary">{a.name}</p>
                            <p className="text-xs text-text-muted">Due week {a.due_week}</p>
                          </div>
                          <div className="flex items-center gap-2">
                            {a.percentage !== null && <span className="font-mono text-sm font-semibold text-success">{a.percentage.toFixed(0)}%</span>}
                            <StatusBadge
                              label={a.percentage !== null ? 'Graded' : 'Pending'}
                              tone={a.percentage !== null ? 'success' : 'warning'}
                            />
                          </div>
                        </div>
                      ))}
                    </div>
                  ) : (
                    <EmptyState icon={<FileText className="h-5 w-5" />} title="No assignments posted yet" />
                  )}
                </>
              )}

              {activeTab === 'Lectures' && (
                <>
                  {course.lectures.length > 0 ? (
                    <div className="divide-y divide-border">
                      {course.lectures.map((l) => (
                        <div key={l.lecture_id} className="flex items-center justify-between py-3 first:pt-0">
                          <div className="flex items-center gap-3">
                            <BookOpen className="h-4 w-4 text-text-muted" />
                            <div>
                              <p className="text-sm font-medium text-text-primary">{l.title}</p>
                              <p className="text-xs text-text-muted">Available week {l.available_week}</p>
                            </div>
                          </div>
                          <StatusBadge
                            label={l.completed ? 'Completed' : 'Not studied'}
                            tone={l.completed ? 'success' : 'warning'}
                          />
                        </div>
                      ))}
                    </div>
                  ) : (
                    <EmptyState icon={<FileText className="h-5 w-5" />} title="No lectures posted yet" />
                  )}
                </>
              )}
            </div>
          </Card>
        </div>

        <div className="space-y-4">
          <Card>
            <h3 className="font-display text-sm font-semibold text-text-primary">Course Details</h3>
            <dl className="mt-3 space-y-3 text-sm">
              <div className="flex items-center gap-2.5">
                <Users className="h-4 w-4 text-text-muted" />
                <span className="text-text-secondary">—</span>
              </div>
              <div className="flex items-center gap-2.5">
                <Clock className="h-4 w-4 text-text-muted" />
                <span className="text-text-secondary">Semester {course.semester}</span>
              </div>
              <div className="flex items-center gap-2.5">
                <MapPin className="h-4 w-4 text-text-muted" />
                <span className="text-text-secondary">—</span>
              </div>
            </dl>
            <div className="mt-4 flex items-center justify-between border-t border-border pt-3">
              <span className="text-xs font-semibold text-text-muted">Credit Hours</span>
              <span className="font-mono text-sm font-semibold text-text-primary">3</span>
            </div>
            <div className="flex items-center justify-between pt-1.5">
              <span className="text-xs font-semibold text-text-muted">Current Week</span>
              <span className="font-mono text-sm font-semibold text-text-primary">{course.current_week}</span>
            </div>
          </Card>
        </div>
      </div>
    </div>
  )
}
