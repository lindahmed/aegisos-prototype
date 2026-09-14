import type { ExamRecord } from '@staff/types'
import StatusBadge from './StatusBadge'
import { useLanguage } from '@/context/LanguageContext'

export default function ExamTable({ exams }: { exams: ExamRecord[] }) {
  const { language, t } = useLanguage()

  return (
    <div className="overflow-x-auto rounded-lg border border-border bg-surface shadow-card">
      <table className="w-full min-w-[720px] text-left text-sm">
        <thead>
          <tr className="border-b border-border bg-surface-raised text-xs font-semibold uppercase tracking-wide text-text-muted">
            {['Course', 'Section', 'Date', 'Time', 'Room', 'Type', 'Status'].map((label) => (
              <th key={label} className="px-4 py-3">{t(label)}</th>
            ))}
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
              <td className="px-4 py-3.5 text-text-secondary">{new Date(e.date).toLocaleDateString(language === 'ar' ? 'ar-EG' : 'en-GB')}</td>
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
