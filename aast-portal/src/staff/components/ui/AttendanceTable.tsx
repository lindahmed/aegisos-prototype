import type { AttendanceRecord, AttendanceStatus } from '@staff/types'

const statusStyles: Record<AttendanceStatus, string> = {
  Present: 'bg-success-100 text-success',
  Absent: 'bg-error-100 text-error',
  Excused: 'bg-teal-100 text-teal-700',
  Late: 'bg-warning-100 text-warning',
}

const statuses: AttendanceStatus[] = ['Present', 'Absent', 'Excused', 'Late']

interface AttendanceTableProps {
  records: AttendanceRecord[]
  onChange: (studentId: string, status: AttendanceStatus) => void
}

export default function AttendanceTable({ records, onChange }: AttendanceTableProps) {
  return (
    <div className="overflow-x-auto rounded-lg border border-border bg-surface shadow-card">
      <table className="w-full min-w-[560px] text-left text-sm">
        <thead>
          <tr className="border-b border-border bg-surface-raised text-xs font-semibold uppercase tracking-wide text-text-muted">
            <th className="px-4 py-3">Student</th>
            <th className="px-4 py-3">Course absences</th>
            <th className="px-4 py-3">Attendance Status</th>
          </tr>
        </thead>
        <tbody>
          {records.map((r) => (
            <tr key={r.studentId} className="border-b border-border last:border-0 hover:bg-surface-sunk/60">
              <td className="px-4 py-3.5">
                <p className="font-medium text-text-primary">{r.studentName}</p>
                <p className="font-mono text-xs text-text-muted">{r.studentId}</p>
              </td>
              <td className="px-4 py-3.5">
                <span className={r.absenceCount && r.absenceCount >= 3 ? 'font-semibold text-error' : 'text-text-secondary'}>
                  {r.absenceCount ?? 0}
                </span>
                {r.enrollmentStatus === 'Withdrawn' && (
                  <p className="mt-1 text-xs font-semibold text-error">Automatically dropped</p>
                )}
              </td>
              <td className="px-4 py-3.5">
                <div className="flex flex-wrap gap-1.5">
                  {statuses.map((s) => (
                    <button
                      key={s}
                      onClick={() => onChange(r.studentId, s)}
                      className={`rounded-full px-3 py-1.5 text-xs font-semibold transition-colors ${
                        r.status === s ? statusStyles[s] : 'bg-surface-sunk text-text-muted hover:bg-border/60'
                      }`}
                    >
                      {s}
                    </button>
                  ))}
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
