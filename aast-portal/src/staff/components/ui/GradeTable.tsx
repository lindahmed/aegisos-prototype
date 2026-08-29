import type { GradeRow } from '@staff/types'

const gradeTone = (grade: string) => {
  if (grade.startsWith('A')) return 'text-success'
  if (grade.startsWith('B')) return 'text-teal-700'
  if (grade.startsWith('C')) return 'text-warning'
  return 'text-error'
}

interface GradeTableProps {
  rows: GradeRow[]
  editable?: boolean
  onChange?: (studentId: string, field: 'assignments' | 'midterm' | 'final', value: number) => void
}

export default function GradeTable({ rows, editable, onChange }: GradeTableProps) {
  return (
    <div className="overflow-x-auto rounded-lg border border-border bg-surface shadow-card">
      <table className="w-full min-w-[720px] text-left text-sm">
        <thead>
          <tr className="border-b border-border bg-surface-raised text-xs font-semibold uppercase tracking-wide text-text-muted">
            <th className="px-4 py-3">Student</th>
            <th className="px-4 py-3">Assignments %</th>
            <th className="px-4 py-3">Midterm %</th>
            <th className="px-4 py-3">Final %</th>
            <th className="px-4 py-3">Weighted Total</th>
            <th className="px-4 py-3">Grade</th>
            <th className="px-4 py-3">GPA</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.studentId} className="border-b border-border last:border-0 hover:bg-surface-sunk/60">
              <td className="px-4 py-3">
                <p className="font-medium text-text-primary">{r.studentName}</p>
                <p className="font-mono text-xs text-text-muted">{r.studentId}</p>
              </td>
              {(['assignments', 'midterm', 'final'] as const).map((field) => (
                <td key={field} className="px-4 py-3">
                  {editable ? (
                    <input
                      type="number"
                      min={0}
                      max={100}
                      step="0.01"
                      value={r[field]}
                      onChange={(e) => onChange?.(r.studentId, field, Number(e.target.value))}
                      className="w-16 rounded-md border border-border-strong px-2 py-1.5 text-sm font-mono focus-visible:outline-2 focus-visible:outline-teal-600"
                    />
                  ) : (
                    <span className="font-mono text-text-secondary">{r[field]}</span>
                  )}
                </td>
              ))}
              <td className="px-4 py-3 font-mono font-semibold text-text-primary">{r.total}</td>
              <td className={`px-4 py-3 font-mono text-base font-bold ${gradeTone(r.grade)}`}>{r.grade}</td>
              <td className="px-4 py-3 font-mono text-text-secondary">{r.gpaPoints.toFixed(1)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
