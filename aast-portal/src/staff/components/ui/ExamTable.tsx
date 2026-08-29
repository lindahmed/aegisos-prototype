import type { ExamRecord } from '@staff/types'
import StatusBadge from './StatusBadge'

export default function ExamTable({ exams }: { exams: ExamRecord[] }) {
  return (
    <div className="overflow-x-auto rounded-lg border border-border bg-surface shadow-card">
      <table className="w-full min-w-[720px] text-left text-sm">
        <thead>
          <tr className="border-b border-border bg-surface-raised text-xs font-semibold uppercase tracking-wide text-text-muted">
            <th className="px-4 py-3">Course</th>
            <th className="px-4 py-3">Section</th>
            <th className="px-4 py-3">Date</th>
            <th className="px-4 py-3">Time</th>
            <th className="px-4 py-3">Room</th>
            <th className="px-4 py-3">Type</th>
            <th className="px-4 py-3">Status</th>
          </tr>
        </thead>
        <tbody>
          {exams.map((e) => (
            <tr key={e.id} className="border-b border-border last:border-0 hover:bg-surface-sunk/60">
              <td className="px-4 py-3.5">
                <p className="font-mono text-xs font-semibold text-teal-700">{e.courseCode}</p>
                <p className="font-medium text-text-primary">{e.courseTitle}</p>
              </td>
              <td className="px-4 py-3.5 text-text-secondary">{e.section}</td>
              <td className="px-4 py-3.5 text-text-secondary">{new Date(e.date).toLocaleDateString()}</td>
              <td className="px-4 py-3.5 font-mono text-text-secondary">{e.start}–{e.end}</td>
              <td className="px-4 py-3.5 text-text-secondary">{e.room}</td>
              <td className="px-4 py-3.5 text-text-secondary">{e.type}</td>
              <td className="px-4 py-3.5">
                <StatusBadge label={e.status} tone={e.status === 'Upcoming' ? 'warning' : 'success'} />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
