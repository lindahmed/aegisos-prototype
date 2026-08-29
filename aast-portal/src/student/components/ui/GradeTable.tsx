import type { PortalStudentGradeRecord } from '@/lib/portalGrades'

const gradeTone = (grade: string) => {
  if (grade.startsWith('A')) return 'text-success'
  if (grade.startsWith('B')) return 'text-teal-700'
  if (grade.startsWith('C')) return 'text-warning'
  return 'text-error'
}

export default function GradeTable({ records }: { records: PortalStudentGradeRecord[] }) {
  return (
    <div className="overflow-x-auto rounded-lg border border-border bg-surface shadow-card">
      <table className="w-full min-w-[860px] text-left text-sm">
        <thead>
          <tr className="border-b border-border bg-surface-raised text-xs font-semibold uppercase tracking-wide text-text-muted">
            <th className="px-4 py-3">Course</th>
            <th className="px-4 py-3">Assignments %</th>
            <th className="px-4 py-3">Midterm %</th>
            <th className="px-4 py-3">Final %</th>
            <th className="px-4 py-3">Weighted Total</th>
            <th className="px-4 py-3">Grade</th>
            <th className="px-4 py-3">GPA</th>
          </tr>
        </thead>
        <tbody>
          {records.map((r) => (
            <tr key={`${r.semester}-${r.course_id}`} className="border-b border-border last:border-0 hover:bg-surface-sunk/60">
              <td className="px-4 py-3.5">
                <p className="font-mono text-xs font-semibold text-teal-700">{r.course_id.toUpperCase()}</p>
                <p className="font-medium text-text-primary">{r.course_name}</p>
              </td>
              <td className="px-4 py-3.5 font-mono text-text-secondary">{r.assignment_score.toFixed(2)}</td>
              <td className="px-4 py-3.5 font-mono text-text-secondary">{r.midterm_score.toFixed(2)}</td>
              <td className="px-4 py-3.5 font-mono text-text-secondary">{r.final_score.toFixed(2)}</td>
              <td className="px-4 py-3.5 font-mono font-semibold text-text-primary">{r.total_score.toFixed(2)}</td>
              <td className={`px-4 py-3.5 font-mono text-base font-bold ${gradeTone(r.letter_grade)}`}>{r.letter_grade}</td>
              <td className="px-4 py-3.5 font-mono text-text-secondary">{r.gpa_points.toFixed(1)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
