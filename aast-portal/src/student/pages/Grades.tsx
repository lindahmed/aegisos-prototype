import { useEffect, useState } from 'react'
import { GraduationCap, TrendingUp, Award, RefreshCw, AlertTriangle } from 'lucide-react'
import { getPortalStudentGrades, type PortalStudentGradeReport } from '@/lib/portalGrades'
import { useAuth } from '@student/context/AuthContext'
import PageHeader from '@student/components/layout/PageHeader'
import Card from '@student/components/ui/Card'
import GradeTable from '@student/components/ui/GradeTable'
import Dropdown from '@student/components/ui/Dropdown'
import StatCard from '@student/components/ui/StatCard'
import StatusBadge from '@student/components/ui/StatusBadge'
import EmptyState from '@student/components/ui/EmptyState'
import { CardSkeleton, TableSkeleton } from '@student/components/ui/LoadingState'

export default function Grades() {
  const { academicStudentId } = useAuth()
  const [report, setReport] = useState<PortalStudentGradeReport | null>(null)
  const [semester, setSemester] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    if (!academicStudentId) {
      setError('This demo student account is not linked to an academic record.')
      setLoading(false)
      return
    }
    let active = true
    setLoading(true)
    setError('')
    getPortalStudentGrades(academicStudentId)
      .then((nextReport) => {
        if (!active) return
        setReport(nextReport)
        setSemester(nextReport.semesters[0]?.semester ?? '')
      })
      .catch((err: Error) => {
        if (!active) return
        setError(err.message)
      })
      .finally(() => {
        if (active) setLoading(false)
      })
    return () => {
      active = false
    }
  }, [academicStudentId])

  const records = report?.records.filter((record) => record.semester === semester) ?? []
  const summary = report?.semesters.find((item) => item.semester === semester) ?? null
  const scoredRecords = records.filter((record) => record.grade_posted && record.total_score !== null)
  const bestCourse = scoredRecords.reduce(
    (best, record) => ((record.total_score ?? -1) > (best?.total_score ?? -1) ? record : best),
    scoredRecords[0],
  )

  return (
    <div>
      <PageHeader
        title="Grades & Academic Record"
        crumbs={[{ label: 'Grades' }]}
        description="Review your live semester grades from the shared academic database."
        actions={
          <Dropdown
            label="Select semester"
            value={semester}
            onSelect={setSemester}
            options={(report?.semesters ?? []).map((item) => ({ label: item.semester, value: item.semester }))}
          />
        }
      />

      {loading ? (
        <>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <CardSkeleton />
            <CardSkeleton />
            <CardSkeleton />
            <CardSkeleton />
          </div>
          <div className="mt-6">
            <Card padded={false}>
              <TableSkeleton rows={5} cols={7} />
            </Card>
          </div>
        </>
      ) : error ? (
        <EmptyState
          icon={<RefreshCw className="h-5 w-5" />}
          title="Could not load your grades"
          description={error}
        />
      ) : !summary ? (
        <EmptyState
          icon={<AlertTriangle className="h-5 w-5" />}
          title="No semester grades available yet"
          description="Once your professor saves grades in the portal, they will appear here."
        />
      ) : (
        <>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <StatCard label="Semester GPA" value={summary.gpa?.toFixed(2) ?? 'In progress'} icon={<GraduationCap className="h-5 w-5" />} accent="teal" />
            <StatCard
              label="Academic GPA"
              value={report?.student.gpa?.toFixed(2) ?? 'N/A'}
              sublabel={report ? report.student.major : undefined}
              icon={<TrendingUp className="h-5 w-5" />}
              accent="ink"
            />
            <StatCard
              label="Courses Graded"
              value={String(summary.courses_graded)}
              sublabel={bestCourse && bestCourse.total_score !== null ? `Best total: ${bestCourse.total_score.toFixed(2)}` : 'No scores yet'}
              icon={<Award className="h-5 w-5" />}
              accent="teal"
            />
            <Card className="flex flex-col justify-center">
              <p className="text-sm text-text-secondary">Academic Standing</p>
              <div className="mt-2">
                <StatusBadge label={summary.standing} tone={summary.standing === "Dean's List" ? 'success' : 'info'} />
              </div>
            </Card>
          </div>

          <div className="mt-6">
            <h2 className="mb-3 font-display text-lg font-semibold text-text-primary">Course Grades — {semester}</h2>
            <GradeTable records={records} />
          </div>

          <Card className="mt-6">
            <h2 className="font-display text-base font-semibold text-text-primary">GPA Trend</h2>
            <div className="mt-4 flex items-end gap-6">
              {[...(report?.semesters ?? [])].reverse().map((item) => (
                <div key={item.semester} className="flex flex-col items-center gap-2">
                  <div className="flex h-32 w-10 items-end rounded-md bg-surface-sunk">
                    <div
                      className="w-full rounded-md bg-teal-600"
                      style={{ height: `${((item.gpa ?? 0) / 4) * 100}%` }}
                      title={item.gpa === null ? 'In progress' : `${item.gpa.toFixed(2)} GPA`}
                    />
                  </div>
                  <span className="font-mono text-xs font-semibold text-text-primary">{item.gpa?.toFixed(2) ?? '—'}</span>
                  <span className="max-w-[90px] text-center text-[11px] text-text-muted">{item.semester}</span>
                </div>
              ))}
            </div>
          </Card>
        </>
      )}
    </div>
  )
}
