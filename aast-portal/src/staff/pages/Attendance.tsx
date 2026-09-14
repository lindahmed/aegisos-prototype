import { useEffect, useMemo, useState } from 'react'
import { BarChart3, ClipboardCheck, RefreshCw, Save } from 'lucide-react'
import {
  getPortalCourseAttendance,
  listPortalCourses,
  savePortalCourseAttendance,
  type PortalAttendanceRow,
  type PortalCourse,
} from '@/lib/portalGrades'
import type { AttendanceRecord, AttendanceStatus } from '@staff/types'
import PageHeader from '@staff/components/layout/PageHeader'
import Card from '@staff/components/ui/Card'
import Dropdown from '@staff/components/ui/Dropdown'
import AttendanceTable from '@staff/components/ui/AttendanceTable'
import Button from '@staff/components/ui/Button'
import EmptyState from '@staff/components/ui/EmptyState'
import { TableSkeleton } from '@staff/components/ui/LoadingState'
import { useToast } from '@staff/components/ui/Toast'

function today() {
  const now = new Date()
  const offset = now.getTimezoneOffset() * 60_000
  return new Date(now.getTime() - offset).toISOString().slice(0, 10)
}

function normalizeRow(row: PortalAttendanceRow): AttendanceRecord {
  return {
    studentId: row.student_id,
    studentName: row.student_name,
    status: row.status,
    absenceCount: row.absence_count,
    enrollmentStatus: row.enrollment_status,
  }
}

export default function Attendance() {
  const [courses, setCourses] = useState<PortalCourse[]>([])
  const [courseId, setCourseId] = useState('')
  const [date, setDate] = useState(today)
  const [semester, setSemester] = useState('')
  const [weekNumber, setWeekNumber] = useState<number | null>(null)
  const [records, setRecords] = useState<AttendanceRecord[]>([])
  const [loadingCourses, setLoadingCourses] = useState(true)
  const [loadingRecords, setLoadingRecords] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const { showToast } = useToast()

  useEffect(() => {
    let active = true
    setLoadingCourses(true)
    setError('')
    listPortalCourses()
      .then(({ courses: availableCourses }) => {
        if (!active) return
        const activeCourses = availableCourses.filter((course) => course.student_count > 0)
        setCourses(activeCourses)
        setCourseId((current) => current || activeCourses[0]?.course_id || '')
      })
      .catch((err: Error) => {
        if (active) setError(err.message)
      })
      .finally(() => {
        if (active) setLoadingCourses(false)
      })
    return () => {
      active = false
    }
  }, [])

  useEffect(() => {
    if (!courseId || !date) {
      setRecords([])
      return
    }
    let active = true
    setLoadingRecords(true)
    setError('')
    getPortalCourseAttendance(courseId, date)
      .then((attendance) => {
        if (!active) return
        setSemester(attendance.course.semester)
        setWeekNumber(attendance.week_number)
        setRecords(attendance.rows.map(normalizeRow))
      })
      .catch((err: Error) => {
        if (!active) return
        setRecords([])
        setWeekNumber(null)
        setError(err.message)
      })
      .finally(() => {
        if (active) setLoadingRecords(false)
      })
    return () => {
      active = false
    }
  }, [courseId, date])

  const updateStatus = (studentId: string, status: AttendanceStatus) => {
    setRecords((current) =>
      current.map((record) =>
        record.studentId === studentId ? { ...record, status } : record,
      ),
    )
  }

  const counts = useMemo(() => {
    const next = { Present: 0, Absent: 0, Excused: 0, Late: 0 }
    records.forEach((record) => next[record.status]++)
    return next
  }, [records])

  const handleSave = async () => {
    if (!courseId || !date || records.length === 0) return
    setSaving(true)
    setError('')
    try {
      const saved = await savePortalCourseAttendance(
        courseId,
        date,
        records.map((record) => ({
          student_id: record.studentId,
          status: record.status,
        })),
      )
      setRecords(saved.rows.map(normalizeRow))
      const dropped = saved.dropped_student_ids?.length ?? 0
      const restored = saved.restored_student_ids?.length ?? 0
      const warnings = saved.rows.filter((row) => row.absence_count === 3).length
      if (dropped > 0) {
        showToast(`Attendance saved. ${dropped} course enrollment${dropped === 1 ? ' was' : 's were'} automatically dropped.`)
      } else if (restored > 0) {
        showToast(`Attendance corrected. ${restored} course enrollment${restored === 1 ? ' was' : 's were'} restored.`)
      } else if (warnings > 0) {
        showToast(`Attendance saved. ${warnings} third-absence warning${warnings === 1 ? ' was' : 's were'} sent.`)
      } else {
        showToast(`Attendance saved for ${saved.rows.length} students.`)
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Could not save attendance.'
      setError(message)
      showToast(message)
    } finally {
      setSaving(false)
    }
  }

  const course = courses.find((item) => item.course_id === courseId)

  return (
    <div>
      <PageHeader
        title="Attendance"
        crumbs={[{ label: 'Attendance' }]}
        description="Take or edit attendance. A third absence sends a warning; a fourth drops the course automatically."
        actions={
          <Button
            icon={<Save className="h-4 w-4" />}
            loading={saving}
            disabled={!courseId || loadingRecords || records.length === 0}
            onClick={handleSave}
          >
            Save Attendance
          </Button>
        }
      />

      <Card className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
          <div>
            <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wide text-text-muted">Course</label>
            <Dropdown
              label="Select course"
              value={courseId}
              onSelect={setCourseId}
              options={courses.map((item) => ({
                label: `${item.course_name} · ${item.student_count} students`,
                value: item.course_id,
              }))}
            />
          </div>
          <div>
            <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wide text-text-muted">Date</label>
            <input
              type="date"
              value={date}
              onChange={(event) => setDate(event.target.value)}
              className="rounded-md border border-border-strong px-3 py-2 text-sm focus-visible:outline-2 focus-visible:outline-teal-600"
            />
          </div>
        </div>
        <div className="flex flex-col items-end gap-1 text-xs text-text-secondary">
          {course && weekNumber && <span>{semester} · Week {weekNumber}</span>}
          <span className="flex items-center gap-2">
            <BarChart3 className="h-4 w-4 text-teal-600" />
            <span>
              <strong className="text-success">{counts.Present}</strong> Present ·{' '}
              <strong className="text-error">{counts.Absent}</strong> Absent ·{' '}
              <strong className="text-teal-700">{counts.Excused}</strong> Excused ·{' '}
              <strong className="text-warning">{counts.Late}</strong> Late
            </span>
          </span>
        </div>
      </Card>

      {loadingCourses || loadingRecords ? (
        <Card padded={false}>
          <TableSkeleton rows={8} cols={3} />
        </Card>
      ) : error ? (
        <EmptyState
          icon={<RefreshCw className="h-5 w-5" />}
          title="Could not load attendance"
          description={error}
          action={
            <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={() => window.location.reload()}>
              Reload
            </Button>
          }
        />
      ) : course ? (
        records.length > 0 ? (
          <AttendanceTable records={records} onChange={updateStatus} />
        ) : (
          <Card className="flex flex-col items-center py-12 text-center">
            <ClipboardCheck className="h-8 w-8 text-text-muted" />
            <p className="mt-3 font-display font-semibold text-text-primary">No enrolled students for this course</p>
          </Card>
        )
      ) : (
        <Card className="flex flex-col items-center py-12 text-center">
          <ClipboardCheck className="h-8 w-8 text-text-muted" />
          <p className="mt-3 font-display font-semibold text-text-primary">No active courses available</p>
        </Card>
      )}
    </div>
  )
}
