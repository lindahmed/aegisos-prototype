import { useEffect, useState } from 'react'
import { Save, GraduationCap, RefreshCw } from 'lucide-react'
import {
  getPortalCourseGradebook,
  listPortalCourses,
  savePortalCourseGradebook,
  type PortalCourse,
} from '@/lib/portalGrades'
import type { GradeRow } from '@staff/types'
import PageHeader from '@staff/components/layout/PageHeader'
import Card from '@staff/components/ui/Card'
import Dropdown from '@staff/components/ui/Dropdown'
import SearchBar from '@staff/components/ui/SearchBar'
import GradeTable from '@staff/components/ui/GradeTable'
import Button from '@staff/components/ui/Button'
import { useToast } from '@staff/components/ui/Toast'
import EmptyState from '@staff/components/ui/EmptyState'
import { TableSkeleton } from '@staff/components/ui/LoadingState'

const gradeScale = [
  { grade: 'A', gpaPoints: 4.0, min: 93 },
  { grade: 'A-', gpaPoints: 3.7, min: 90 },
  { grade: 'B+', gpaPoints: 3.3, min: 87 },
  { grade: 'B', gpaPoints: 3.0, min: 83 },
  { grade: 'B-', gpaPoints: 2.7, min: 80 },
  { grade: 'C+', gpaPoints: 2.3, min: 77 },
  { grade: 'C', gpaPoints: 2.0, min: 73 },
  { grade: 'D', gpaPoints: 1.0, min: 60 },
  { grade: 'F', gpaPoints: 0.0, min: 0 },
]

function scoreToGrade(total: number) {
  return gradeScale.find((g) => total >= g.min) ?? gradeScale[gradeScale.length - 1]
}

function weightedTotal(assignments: number, midterm: number, final: number) {
  return Number(((assignments * 0.3) + (midterm * 0.3) + (final * 0.4)).toFixed(2))
}

function normalizeRow(row: {
  student_id: string
  student_name: string
  assignment_score: number
  midterm_score: number
  final_score: number
}): GradeRow {
  const total = weightedTotal(row.assignment_score, row.midterm_score, row.final_score)
  const { grade, gpaPoints } = scoreToGrade(total)
  return {
    studentId: row.student_id,
    studentName: row.student_name,
    assignments: row.assignment_score,
    midterm: row.midterm_score,
    final: row.final_score,
    total,
    grade,
    gpaPoints,
  }
}

export default function Grades() {
  const [courses, setCourses] = useState<PortalCourse[]>([])
  const [courseId, setCourseId] = useState('')
  const [query, setQuery] = useState('')
  const [semester, setSemester] = useState('')
  const [rows, setRows] = useState<GradeRow[]>([])
  const [loadingCourses, setLoadingCourses] = useState(true)
  const [loadingRows, setLoadingRows] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const { showToast } = useToast()

  useEffect(() => {
    let active = true
    setLoadingCourses(true)
    setError('')
    listPortalCourses()
      .then(({ courses: nextCourses }) => {
        if (!active) return
        setCourses(nextCourses)
        setCourseId((current) => current || nextCourses[0]?.course_id || '')
      })
      .catch((err: Error) => {
        if (!active) return
        setError(err.message)
      })
      .finally(() => {
        if (active) setLoadingCourses(false)
      })
    return () => {
      active = false
    }
  }, [])

  useEffect(() => {
    if (!courseId) {
      setRows([])
      return
    }
    let active = true
    setLoadingRows(true)
    setError('')
    getPortalCourseGradebook(courseId)
      .then((gradebook) => {
        if (!active) return
        setSemester(gradebook.course.semester)
        setRows(gradebook.rows.map(normalizeRow))
      })
      .catch((err: Error) => {
        if (!active) return
        setError(err.message)
      })
      .finally(() => {
        if (active) setLoadingRows(false)
      })
    return () => {
      active = false
    }
  }, [courseId])

  const handleCourseChange = (id: string) => {
    setCourseId(id)
  }

  const updateCell = (studentId: string, field: 'assignments' | 'midterm' | 'final', value: number) => {
    setRows((prev) =>
      prev.map((r) => {
        if (r.studentId !== studentId) return r
        const sanitizedValue = Number.isFinite(value) ? Math.max(0, Math.min(100, value)) : 0
        const updated = { ...r, [field]: sanitizedValue }
        const total = weightedTotal(updated.assignments, updated.midterm, updated.final)
        const { grade, gpaPoints } = scoreToGrade(total)
        return { ...updated, total, grade, gpaPoints }
      })
    )
  }

  const handleSave = async () => {
    if (!courseId || !semester || rows.length === 0) return
    setSaving(true)
    setError('')
    try {
      const saved = await savePortalCourseGradebook(
        courseId,
        semester,
        rows.map((row) => ({
          student_id: row.studentId,
          assignment_score: row.assignments,
          midterm_score: row.midterm,
          final_score: row.final,
        }))
      )
      setRows(saved.rows.map(normalizeRow))
      showToast('Grades saved to the shared academic database.')
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Could not save grades.'
      setError(message)
      showToast(message)
    } finally {
      setSaving(false)
    }
  }

  const filteredRows = rows.filter((r) => r.studentName.toLowerCase().includes(query.toLowerCase()))
  const course = courses.find((item) => item.course_id === courseId)

  return (
    <div>
      <PageHeader
        title="Grades"
        crumbs={[{ label: 'Grades' }]}
        description="Enter and review grades for a course from the shared academic database."
        actions={
          <Button icon={<Save className="h-4 w-4" />} loading={saving} disabled={!courseId || loadingRows} onClick={handleSave}>
            Save Grades
          </Button>
        }
      />

      <Card className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wide text-text-muted">Course</label>
          <Dropdown
            label="Select course"
            value={courseId}
            onSelect={handleCourseChange}
            options={courses.map((item) => ({
              label: `${item.course_name} · ${item.student_count} students`,
              value: item.course_id,
            }))}
          />
        </div>
        <SearchBar value={query} onChange={setQuery} placeholder="Search students" className="w-full sm:w-64" />
      </Card>

      {course && (
        <Card className="mb-4">
          <div className="flex flex-col gap-1 text-sm text-text-secondary sm:flex-row sm:items-center sm:justify-between">
            <span className="font-medium text-text-primary">{course.course_name}</span>
            <span>{semester} · Assignments 30% · Midterm 30% · Final 40%</span>
          </div>
        </Card>
      )}

      {loadingCourses || loadingRows ? (
        <Card padded={false}>
          <TableSkeleton rows={6} cols={7} />
        </Card>
      ) : error ? (
        <EmptyState
          icon={<RefreshCw className="h-5 w-5" />}
          title="Could not load gradebook"
          description={error}
          action={
            <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={() => window.location.reload()}>
              Reload
            </Button>
          }
        />
      ) : course ? (
        <GradeTable rows={filteredRows} editable onChange={updateCell} />
      ) : (
        <Card className="flex flex-col items-center py-12 text-center">
          <GraduationCap className="h-8 w-8 text-text-muted" />
          <p className="mt-3 font-display font-semibold text-text-primary">No courses available for grading</p>
        </Card>
      )}
    </div>
  )
}
