import { useMemo, useState } from 'react'
import { BookOpen } from 'lucide-react'
import { useStudentAcademics } from '@student/context/StudentAcademicsContext'
import type { Course } from '@student/types'
import PageHeader from '@student/components/layout/PageHeader'
import SearchBar from '@student/components/ui/SearchBar'
import CourseCard from '@student/components/ui/CourseCard'
import EmptyState from '@student/components/ui/EmptyState'
import { CardSkeleton } from '@student/components/ui/LoadingState'

function mapToCourse(course: {
  course_id: string
  course_name: string
  assessments: { assessment_id: string; name: string; assessment_type: string; due_week: number; mark: number | null; max_marks: number }[]
  materials: { material_id: string; title: string; material_type: string }[]
}): Course {
  return {
    id: course.course_id,
    code: course.course_id,
    title: course.course_name,
    credits: 3,
    instructor: '—',
    schedule: [],
    room: '—',
    seatsTotal: 0,
    seatsTaken: 0,
    status: 'In Progress',
    description: '',
    materials: course.materials.map((m) => ({
      name: m.title,
      type: m.material_type === 'slides' ? 'Slides' : m.material_type === 'PDF' ? 'PDF' : 'Link',
    })),
    assignments: course.assessments.map((a) => ({
      name: a.name,
      due: `Week ${a.due_week}`,
      status: a.mark !== null ? 'Graded' : 'Pending',
      grade: a.mark !== null ? `${a.mark.toFixed(1)}/{a.max_marks.toFixed(0)} marks` : undefined,
    })),
  }
}

export default function Courses() {
  const { academics, loading } = useStudentAcademics()
  const [query, setQuery] = useState('')

  const courses = useMemo(() => (academics?.courses ?? []).map(mapToCourse), [academics])

  const filtered = courses.filter(
    (c) =>
      c.title.toLowerCase().includes(query.toLowerCase()) ||
      c.code.toLowerCase().includes(query.toLowerCase())
  )

  return (
    <div>
      <PageHeader
        title="My Courses"
        crumbs={[{ label: 'Courses' }]}
        description={`Your enrolled courses for ${academics?.semester ?? 'Fall 2026'}.`}
        actions={<SearchBar value={query} onChange={setQuery} placeholder="Search courses" className="w-64" />}
      />

      {loading ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
          <CardSkeleton /><CardSkeleton /><CardSkeleton />
        </div>
      ) : filtered.length > 0 ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {filtered.map((c) => (
            <CourseCard key={c.id} course={c} />
          ))}
        </div>
      ) : (
        <EmptyState icon={<BookOpen className="h-5 w-5" />} title="No courses found" description="No courses are registered in the academic database yet." />
      )}
    </div>
  )
}
