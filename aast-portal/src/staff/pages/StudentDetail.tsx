import { useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { ArrowLeft, Mail, Users as UsersIcon, FileText } from 'lucide-react'
import { students, gradeHistoryFor, requests } from '@staff/data/studentDetailData'
import PageHeader from '@staff/components/layout/PageHeader'
import Card from '@staff/components/ui/Card'
import StatusBadge from '@staff/components/ui/StatusBadge'
import Tabs from '@staff/components/ui/Tabs'
import EmptyState from '@staff/components/ui/EmptyState'

const tabs = ['Profile', 'Academic Record', 'Requests']

const gradeStatusTone: Record<string, 'success' | 'warning' | 'error' | 'info'> = {
  Excellent: 'success',
  'On Track': 'info',
  'At Risk': 'warning',
  Failing: 'error',
}

export default function StudentDetail() {
  const { id } = useParams()
  const [activeTab, setActiveTab] = useState(tabs[0])
  const student = students.find((s) => s.id === id)

  if (!student) {
    return (
      <EmptyState
        icon={<UsersIcon className="h-5 w-5" />}
        title="Student not found"
        action={
          <Link to="/students" className="text-sm font-semibold text-teal-700 hover:underline">
            Back to Student List
          </Link>
        }
      />
    )
  }

  const grades = gradeHistoryFor(student)
  const studentRequests = requests.filter((r) => r.originName === student.fullName)

  return (
    <div>
      <PageHeader
        title={student.fullName}
        crumbs={[{ label: 'Students', to: '/students' }, { label: student.studentId }]}
        description={`${student.department} · ${student.level}`}
        actions={<StatusBadge label={student.gradeStatus} tone={gradeStatusTone[student.gradeStatus]} />}
      />

      <Link to="/students" className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-text-secondary hover:text-teal-700">
        <ArrowLeft className="h-3.5 w-3.5" />
        Back to Student List
      </Link>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div className="lg:col-span-1">
          <Card className="text-center">
            <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-teal-600 font-display text-xl font-bold text-white">
              {student.fullName.split(' ').map((n) => n[0]).slice(0, 2).join('')}
            </div>
            <p className="mt-3 font-display text-base font-semibold text-text-primary">{student.fullName}</p>
            <p className="font-mono text-xs text-text-muted">{student.studentId}</p>
          </Card>
          <Card className="mt-4">
            <dl className="space-y-3 text-sm">
              <div className="flex justify-between gap-3">
                <dt className="text-text-secondary">College</dt>
                <dd className="text-right font-medium text-text-primary">{student.college}</dd>
              </div>
              <div className="flex justify-between gap-3">
                <dt className="text-text-secondary">Department</dt>
                <dd className="text-right font-medium text-text-primary">{student.department}</dd>
              </div>
              <div className="flex justify-between gap-3">
                <dt className="text-text-secondary">Level</dt>
                <dd className="text-right font-medium text-text-primary">{student.level}</dd>
              </div>
              <div className="flex justify-between gap-3">
                <dt className="text-text-secondary">Section</dt>
                <dd className="text-right font-medium text-text-primary">{student.section}</dd>
              </div>
              <div className="flex justify-between gap-3">
                <dt className="text-text-secondary">Attendance</dt>
                <dd className="text-right font-mono font-semibold text-text-primary">{student.attendancePct}%</dd>
              </div>
              <div className="flex items-center gap-2 border-t border-border pt-3">
                <Mail className="h-3.5 w-3.5 text-text-muted" />
                <span className="truncate text-text-secondary">{student.email}</span>
              </div>
            </dl>
          </Card>
        </div>

        <div className="lg:col-span-2">
          <Card padded={false}>
            <div className="px-2 pt-1">
              <Tabs tabs={tabs} active={activeTab} onChange={setActiveTab} />
            </div>
            <div className="p-5">
              {activeTab === 'Profile' && (
                <div>
                  <p className="text-sm leading-relaxed text-text-secondary">
                    {student.fullName} is currently enrolled in {student.courses.length} of your course sections:{' '}
                    {student.courses.join(', ')}. Current attendance rate is {student.attendancePct}%.
                  </p>
                </div>
              )}

              {activeTab === 'Academic Record' && (
                <div className="overflow-x-auto rounded-lg border border-border">
                  <table className="w-full min-w-[560px] text-left text-sm">
                    <thead>
                      <tr className="border-b border-border bg-surface-raised text-xs font-semibold uppercase tracking-wide text-text-muted">
                        <th className="px-4 py-3">Course</th>
                        <th className="px-4 py-3">Assignments</th>
                        <th className="px-4 py-3">Midterm</th>
                        <th className="px-4 py-3">Final</th>
                        <th className="px-4 py-3">Total</th>
                        <th className="px-4 py-3">Grade</th>
                        <th className="px-4 py-3">GPA</th>
                      </tr>
                    </thead>
                    <tbody>
                      {grades.map((g) => (
                        <tr key={g.studentId} className="border-b border-border last:border-0">
                          <td className="px-4 py-3 font-mono text-xs font-semibold text-teal-700">{g.studentName}</td>
                          <td className="px-4 py-3 font-mono text-text-secondary">{g.coursework}</td>
                          <td className="px-4 py-3 font-mono text-text-secondary">{g.week7Exam}</td>
                          <td className="px-4 py-3 font-mono text-text-secondary">{g.finalExam}</td>
                          <td className="px-4 py-3 font-mono font-semibold text-text-primary">{g.total}</td>
                          <td className="px-4 py-3 font-mono text-base font-bold text-text-primary">{g.grade}</td>
                          <td className="px-4 py-3 font-mono text-text-secondary">{g.gpaPoints.toFixed(1)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}

              {activeTab === 'Requests' && (
                studentRequests.length > 0 ? (
                  <div className="divide-y divide-border">
                    {studentRequests.map((r) => (
                      <div key={r.id} className="flex items-center justify-between py-3 first:pt-0">
                        <div>
                          <p className="text-sm font-medium text-text-primary">{r.type}</p>
                          <p className="text-xs text-text-muted">{new Date(r.date).toLocaleDateString()}</p>
                        </div>
                        <StatusBadge label={r.status} tone={r.status === 'Approved' || r.status === 'Completed' ? 'success' : r.status === 'Rejected' ? 'error' : 'warning'} />
                      </div>
                    ))}
                  </div>
                ) : (
                  <EmptyState icon={<FileText className="h-5 w-5" />} title="No requests from this student" />
                )
              )}
            </div>
          </Card>
        </div>
      </div>
    </div>
  )
}
