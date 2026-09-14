import { type ReactNode } from 'react'
import Card from './Card'

interface StatCardProps {
  label: string
  value: string
  sublabel?: string
  icon: ReactNode
  accent?: 'teal' | 'coral' | 'ink'
}

export default function StatCard({ label, value, sublabel, icon, accent = 'teal' }: StatCardProps) {
  const iconBg =
    accent === 'teal' ? 'bg-teal-50 text-teal-600' : accent === 'coral' ? 'bg-coral-50 text-coral-600' : 'bg-ink-900/5 text-ink-900'

  return (
    <Card accent={accent} className="flex items-start justify-between">
      <div>
        <p className="text-sm text-text-secondary font-medium">{label}</p>
        <p className="mt-1.5 font-mono text-2xl font-semibold text-text-primary tracking-tight">{value}</p>
        {sublabel && <p className="mt-1 text-xs text-text-muted">{sublabel}</p>}
      </div>
      <div className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-md ${iconBg}`}>{icon}</div>
    </Card>
  )
}
