import { useMemo, useState } from 'react'
import { ClipboardCheck, Save, BarChart3 } from 'lucide-react'
import { courseSections, students } from '@staff/data/mockData'
import type { AttendanceRecord, AttendanceStatus } from '@staff/types'
import PageHeader from '@staff/components/layout/PageHeader'
import Card from '@staff/components/ui/Card'
import Dropdown from '@staff/components/ui/Dropdown'
import AttendanceTable from '@staff/components/ui/AttendanceTable'
import Button from '@staff/components/ui/Button'
import { useToast } from '@staff/components/ui/Toast'

const activeCourses = courseSections.filter((c) => c.status === 'Active')

export default function Attendance() {
  const [courseId, setCourseId] = useState(activeCourses[0]?.id ?? '')
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10))
  const { showToast } = useToast()

  const course = activeCourses.find((c) => c.id === courseId)
  const roster = students.slice(0, course?.studentsCount && course.studentsCount < 12 ? course.studentsCount : 10)

  const [records, setRecords] = useState<AttendanceRecord[]>(() =>
    roster.map((s) => ({ studentId: s.studentId, studentName: s.fullName, status: 'Present' as AttendanceStatus }))
  )

  const handleCourseChange = (id: string) => {
    setCourseId(id)
    const c = activeCourses.find((x) => x.id === id)
    const newRoster = students.slice(0, c?.studentsCount && c.studentsCount < 12 ? c.studentsCount : 10)
    setRecords(newRoster.map((s) => ({ studentId: s.studentId, studentName: s.fullName, status: 'Present' })))
  }

  const updateStatus = (studentId: string, status: AttendanceStatus) => {
    setRecords((prev) => prev.map((r) => (r.studentId === studentId ? { ...r, status } : r)))
  }

  const counts = useMemo(() => {
    const c = { Present: 0, Absent: 0, Excused: 0, Late: 0 }
    records.forEach((r) => c[r.status]++)
    return c
  }, [records])

  const handleSave = () => {
    showToast(`Attendance saved for ${records.length} students.`)
  }

  return (
    <div>
      <PageHeader
        title="Attendance"
        crumbs={[{ label: 'Attendance' }]}
        description="Take or edit attendance for a course section."
        actions={
          <Button icon={<Save className="h-4 w-4" />} onClick={handleSave}>
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
              onSelect={handleCourseChange}
              options={activeCourses.map((c) => ({ label: `${c.code} · ${c.section}`, value: c.id }))}
            />
          </div>
          <div>
            <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wide text-text-muted">Date</label>
            <input
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
              className="rounded-md border border-border-strong px-3 py-2 text-sm focus-visible:outline-2 focus-visible:outline-teal-600"
            />
          </div>
        </div>
        <div className="flex items-center gap-2 text-xs text-text-secondary">
          <BarChart3 className="h-4 w-4 text-teal-600" />
          <span>
            <strong className="text-success">{counts.Present}</strong> Present ·{' '}
            <strong className="text-error">{counts.Absent}</strong> Absent ·{' '}
            <strong className="text-teal-700">{counts.Excused}</strong> Excused ·{' '}
            <strong className="text-warning">{counts.Late}</strong> Late
          </span>
        </div>
      </Card>

      {course ? (
        <AttendanceTable records={records} onChange={updateStatus} />
      ) : (
        <Card className="flex flex-col items-center py-12 text-center">
          <ClipboardCheck className="h-8 w-8 text-text-muted" />
          <p className="mt-3 font-display font-semibold text-text-primary">Select a course to begin</p>
        </Card>
      )}
    </div>
  )
}
