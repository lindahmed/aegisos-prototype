import { Link } from 'react-router-dom'
import type { Student } from '@staff/types'
import StatusBadge from './StatusBadge'

const gradeStatusTone: Record<Student['gradeStatus'], 'success' | 'warning' | 'error' | 'info'> = {
  Excellent: 'success',
  'On Track': 'info',
  'At Risk': 'warning',
  Failing: 'error',
}

export default function StudentTable({ students }: { students: Student[] }) {
  return (
    <div className="overflow-x-auto rounded-lg border border-border bg-surface shadow-card">
      <table className="w-full min-w-[720px] text-left text-sm">
        <thead>
          <tr className="border-b border-border bg-surface-raised text-xs font-semibold uppercase tracking-wide text-text-muted">
            <th className="px-4 py-3">Student</th>
            <th className="px-4 py-3">ID</th>
            <th className="px-4 py-3">Level</th>
            <th className="px-4 py-3">Section</th>
            <th className="px-4 py-3">Attendance</th>
            <th className="px-4 py-3">Status</th>
          </tr>
        </thead>
        <tbody>
          {students.map((s) => (
            <tr key={s.id} className="border-b border-border last:border-0 hover:bg-surface-sunk/60">
              <td className="px-4 py-3.5">
                <Link to={`/students/${s.id}`} className="font-medium text-text-primary hover:text-teal-700">
                  {s.fullName}
                </Link>
              </td>
              <td className="px-4 py-3.5 font-mono text-xs text-text-muted">{s.studentId}</td>
              <td className="px-4 py-3.5 text-text-secondary">{s.level}</td>
              <td className="px-4 py-3.5 text-text-secondary">{s.section}</td>
              <td className="px-4 py-3.5 font-mono text-text-secondary">{s.attendancePct}%</td>
              <td className="px-4 py-3.5">
                <StatusBadge label={s.gradeStatus} tone={gradeStatusTone[s.gradeStatus]} />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
