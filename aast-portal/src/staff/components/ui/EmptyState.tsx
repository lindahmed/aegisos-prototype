import { type ReactNode } from 'react'
import { useLanguage } from '@/context/LanguageContext'

interface EmptyStateProps {
  icon: ReactNode
  title: string
  description?: string
  action?: ReactNode
}

export default function EmptyState({ icon, title, description, action }: EmptyStateProps) {
  const { t } = useLanguage()

  return (
    <div className="flex flex-col items-center justify-center rounded-lg border border-dashed border-border-strong bg-surface-raised px-6 py-14 text-center">
      <div className="flex h-12 w-12 items-center justify-center rounded-full bg-surface-sunk text-text-muted">
        {icon}
      </div>
      <p className="mt-4 font-display text-base font-semibold text-text-primary">{t(title)}</p>
      {description && <p className="mt-1 max-w-sm text-sm text-text-secondary">{t(description)}</p>}
      {action && <div className="mt-4">{action}</div>}
    </div>
  )
}
