import type { GradeRow } from '@staff/types'
import { useLanguage } from '@/context/LanguageContext'

const gradeTone = (grade: string) => {
  if (grade === 'U') return 'text-text-muted'
  if (grade.startsWith('A')) return 'text-success'
  if (grade.startsWith('B')) return 'text-teal-700'
  if (grade.startsWith('C')) return 'text-warning'
  return 'text-error'
}

interface GradeTableProps {
  rows: GradeRow[]
  editable?: boolean
  onChange?: (studentId: string, field: 'coursework' | 'week7Exam' | 'week12Exam' | 'finalExam', value: number) => void
}

export default function GradeTable({ rows, editable, onChange }: GradeTableProps) {
  const { t } = useLanguage()

  return (
    <div className="overflow-x-auto rounded-lg border border-border bg-surface shadow-card">
      <table className="w-full min-w-[720px] text-left text-sm">
        <thead>
          <tr className="border-b border-border bg-surface-raised text-xs font-semibold uppercase tracking-wide text-text-muted">
            {['Student', 'Coursework (/10)', 'Week 7 exam (/30)', 'Week 12 exam (/20)', 'Final exam (/40)', 'Total (/100)', 'Grade', 'GPA'].map((label) => (
              <th key={label} className="px-4 py-3">{t(label)}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.studentId} className="border-b border-border last:border-0 hover:bg-surface-sunk/60">
              <td className="px-4 py-3">
                <p className="font-medium text-text-primary">{r.studentName}</p>
                <p className="font-mono text-xs text-text-muted">{r.studentId}</p>
              </td>
              {(['coursework', 'week7Exam', 'week12Exam', 'finalExam'] as const).map((field) => (
                <td key={field} className="px-4 py-3">
                  {editable ? (
                    <input
                      type="number"
                      min={0}
                      max={({ coursework: 10, week7Exam: 30, week12Exam: 20, finalExam: 40 })[field]}
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
              <td className="px-4 py-3 font-mono text-text-secondary">{r.grade === 'U' ? '—' : r.gpaPoints.toFixed(1)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
