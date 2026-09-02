import { students, requests } from './mockData'
import type { Student, GradeRow } from '@staff/types'

export { students, requests }

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

export function gradeHistoryFor(student: Student): GradeRow[] {
  return student.courses.map((code, i) => {
    const coursework = 5 + ((student.id.charCodeAt(2) + i) % 6)
    const week7Exam = 15 + ((student.id.charCodeAt(3) + i * 3) % 16)
    const week12Exam = 10 + ((student.id.charCodeAt(4) + i * 2) % 11)
    const finalExam = 20 + ((student.id.charCodeAt(4) + i * 5) % 21)
    const total = coursework + week7Exam + week12Exam + finalExam
    const { grade, gpaPoints } = scoreToGrade(total)
    return {
      studentId: `${student.studentId}-${code.replace(/\s/g, '')}`,
      studentName: code,
      coursework,
      week7Exam,
      week12Exam,
      finalExam,
      total,
      grade,
      gpaPoints,
    }
  })
}
