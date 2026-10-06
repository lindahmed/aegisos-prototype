interface StatusBadgeProps {
  label: string
  tone?: 'success' | 'warning' | 'error' | 'info' | 'neutral'
}

const toneStyles: Record<string, string> = {
  success: 'bg-success-100 text-success',
  warning: 'bg-warning-100 text-warning',
  error: 'bg-error-100 text-error',
  info: 'bg-teal-100 text-teal-700',
  neutral: 'bg-surface-sunk text-text-secondary border border-border',
}

export default function StatusBadge({ label, tone = 'neutral' }: StatusBadgeProps) {
  const { t } = useLanguage()

  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold ${toneStyles[tone]}`}
    >
      {t(label)}
    </span>
  )
}
import { useLanguage } from '@/context/LanguageContext'
