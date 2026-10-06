import StatusBadge from './StatusBadge'

interface ProfileCardStudent {
  name: string
  student_id?: string
  major?: string
  year?: number
  status?: string
}

function initials(name: string): string {
  return name
    .split(' ')
    .map((n) => n[0])
    .slice(0, 2)
    .join('')
    .toUpperCase()
}

export default function ProfileCard({ student }: { student: ProfileCardStudent }) {
  return (
    <div className="overflow-hidden rounded-lg border border-border bg-surface shadow-card">
      <div className="bg-ink-900 px-6 py-8 text-center">
        <div className="mx-auto flex h-20 w-20 items-center justify-center rounded-full bg-teal-500 font-display text-2xl font-bold text-white ring-4 ring-white/10">
          {initials(student.name)}
        </div>
        <p className="mt-3 font-display text-lg font-semibold text-white">{student.name}</p>
        <p className="font-mono text-sm text-white/50">{student.student_id ?? ''}</p>
        <div className="mt-2 flex justify-center">
          <StatusBadge label={student.status ?? 'Active'} tone="success" />
        </div>
      </div>
      <dl className="divide-y divide-border">
        {[
          ['Program', student.major ?? '—'],
          ['Level', student.year ? `Year ${student.year}` : '—'],
        ].map(([label, value]) => (
          <div key={label} className="flex justify-between gap-4 px-5 py-3 text-sm">
            <dt className="text-text-secondary">{label}</dt>
            <dd className="text-right font-medium text-text-primary">{value}</dd>
          </div>
        ))}
      </dl>
    </div>
  )
}
