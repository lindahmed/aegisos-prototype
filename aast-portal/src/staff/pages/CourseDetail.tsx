import { useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { FileText, Presentation, Link2, Clock, MapPin, Users, ArrowLeft, Megaphone, Upload } from 'lucide-react'
import { courseSections, students } from '@staff/data/mockData'
import PageHeader from '@staff/components/layout/PageHeader'
import Card from '@staff/components/ui/Card'
import StatusBadge from '@staff/components/ui/StatusBadge'
import Tabs from '@staff/components/ui/Tabs'
import StudentTable from '@staff/components/ui/StudentTable'
import EmptyState from '@staff/components/ui/EmptyState'

const materialIcon = { PDF: FileText, Slides: Presentation, Link: Link2 }

const tabs = ['Overview', 'Students', 'Materials', 'Assignments', 'Announcements']

export default function CourseDetail() {
  const { id } = useParams()
  const [activeTab, setActiveTab] = useState(tabs[0])
  const course = courseSections.find((c) => c.id === id)

  if (!course) {
    return (
      <EmptyState
        icon={<FileText className="h-5 w-5" />}
        title="Course not found"
        action={
          <Link to="/courses" className="text-sm font-semibold text-teal-700 hover:underline">
            Back to My Courses
          </Link>
        }
      />
    )
  }

  const enrolledStudents = students.slice(0, course.studentsCount > students.length ? students.length : Math.min(course.studentsCount, 12))

  return (
    <div>
      <PageHeader
        title={course.title}
        crumbs={[{ label: 'My Courses', to: '/courses' }, { label: `${course.code} · ${course.section}` }]}
        description={`${course.code} · ${course.section} · ${course.semester}`}
        actions={<StatusBadge label={course.status} tone={course.status === 'Active' ? 'info' : 'success'} />}
      />

      <Link to="/courses" className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-text-secondary hover:text-teal-700">
        <ArrowLeft className="h-3.5 w-3.5" />
        Back to My Courses
      </Link>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <Card padded={false}>
            <div className="px-2 pt-1">
              <Tabs tabs={tabs} active={activeTab} onChange={setActiveTab} />
            </div>
            <div className="p-5">
              {activeTab === 'Overview' && (
                <p className="text-sm leading-relaxed text-text-secondary">
                  {course.code} — {course.title} runs on {course.schedule.map((s) => `${s.day} ${s.start}–${s.end}`).join(' and ')} in{' '}
                  {course.room}. This section currently has {course.studentsCount} enrolled students for {course.semester}.
                </p>
              )}

              {activeTab === 'Students' && (
                enrolledStudents.length > 0 ? (
                  <StudentTable students={enrolledStudents} />
                ) : (
                  <EmptyState icon={<Users className="h-5 w-5" />} title="No students enrolled yet" />
                )
              )}

              {activeTab === 'Materials' && (
                <div>
                  <div className="mb-4 flex flex-col gap-3 rounded-lg border border-teal-100 bg-teal-50 p-4 sm:flex-row sm:items-center sm:justify-between">
                    <div>
                      <p className="text-sm font-semibold text-text-primary">Share a PDF with students</p>
                      <p className="mt-1 text-xs text-text-secondary">Choose an assigned course on the upload page to make it available to enrolled students.</p>
                    </div>
                    <Link to="/materials" className="inline-flex shrink-0 items-center justify-center gap-2 rounded-md bg-teal-600 px-4 py-2 text-sm font-semibold text-white hover:bg-teal-700">
                      <Upload className="h-4 w-4" /> Upload PDF
                    </Link>
                  </div>
                  {course.materials.length > 0 ? (
                    <div className="divide-y divide-border">
                      {course.materials.map((m, i) => {
                        const Icon = materialIcon[m.type]
                        return (
                          <div key={i} className="flex items-center gap-3 py-3 first:pt-0">
                            <div className="flex h-9 w-9 items-center justify-center rounded-md bg-teal-50 text-teal-600">
                              <Icon className="h-4 w-4" />
                            </div>
                            <p className="text-sm font-medium text-text-primary">{m.name}</p>
                          </div>
                        )
                      })}
                    </div>
                  ) : (
                    <EmptyState icon={<FileText className="h-5 w-5" />} title="No materials posted yet" />
                  )}
                </div>
              )}

              {activeTab === 'Assignments' && (
                course.assignments.length > 0 ? (
                  <div className="divide-y divide-border">
                    {course.assignments.map((a, i) => (
                      <div key={i} className="flex items-center justify-between py-3 first:pt-0">
                        <div>
                          <p className="text-sm font-medium text-text-primary">{a.name}</p>
                          <p className="text-xs text-text-muted">Due {a.due}</p>
                        </div>
                        <span className="font-mono text-xs text-text-secondary">
                          {a.submitted}/{a.total} submitted
                        </span>
                      </div>
                    ))}
                  </div>
                ) : (
                  <EmptyState icon={<FileText className="h-5 w-5" />} title="No assignments posted yet" />
                )
              )}

              {activeTab === 'Announcements' && (
                course.announcements.length > 0 ? (
                  <div className="divide-y divide-border">
                    {course.announcements.map((a, i) => (
                      <div key={i} className="py-3 first:pt-0">
                        <p className="text-sm font-medium text-text-primary">{a.title}</p>
                        <p className="text-xs text-text-muted">{new Date(a.date).toLocaleDateString()}</p>
                        <p className="mt-1 text-sm text-text-secondary">{a.body}</p>
                      </div>
                    ))}
                  </div>
                ) : (
                  <EmptyState icon={<Megaphone className="h-5 w-5" />} title="No announcements posted for this course" />
                )
              )}
            </div>
          </Card>
        </div>

        <div className="space-y-4">
          <Card>
            <h3 className="font-display text-sm font-semibold text-text-primary">Course Details</h3>
            <dl className="mt-3 space-y-3 text-sm">
              <div className="flex items-center gap-2.5">
                <Clock className="h-4 w-4 text-text-muted" />
                <span className="text-text-secondary">{course.schedule.map((s) => `${s.day} ${s.start}–${s.end}`).join(', ')}</span>
              </div>
              <div className="flex items-center gap-2.5">
                <MapPin className="h-4 w-4 text-text-muted" />
                <span className="text-text-secondary">{course.room}</span>
              </div>
              <div className="flex items-center gap-2.5">
                <Users className="h-4 w-4 text-text-muted" />
                <span className="text-text-secondary">{course.studentsCount} students</span>
              </div>
            </dl>
            <div className="mt-4 flex items-center justify-between border-t border-border pt-3">
              <span className="text-xs font-semibold text-text-muted">Credit Hours</span>
              <span className="font-mono text-sm font-semibold text-text-primary">{course.credits}</span>
            </div>
          </Card>

          <Card className="flex flex-col gap-2">
            <Link to="/attendance" className="rounded-md border border-border-strong px-3 py-2.5 text-center text-sm font-semibold text-text-primary hover:border-teal-500 hover:bg-teal-50 hover:text-teal-700">
              Take Attendance
            </Link>
            <Link to="/grades" className="rounded-md border border-border-strong px-3 py-2.5 text-center text-sm font-semibold text-text-primary hover:border-teal-500 hover:bg-teal-50 hover:text-teal-700">
              Enter Grades
            </Link>
          </Card>
        </div>
      </div>
    </div>
  )
}
