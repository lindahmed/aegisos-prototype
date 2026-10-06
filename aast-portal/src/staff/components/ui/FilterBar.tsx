interface FilterBarProps {
  options: string[]
  active: string
  onChange: (value: string) => void
}

export default function FilterBar({ options, active, onChange }: FilterBarProps) {
  const { t } = useLanguage()

  return (
    <div className="flex flex-wrap gap-1.5" role="group" aria-label={t('Filters')}>
      {options.map((opt) => (
        <button
          key={opt}
          onClick={() => onChange(opt)}
          aria-pressed={active === opt}
          className={`rounded-full px-3 py-1.5 text-xs font-semibold transition-colors ${
            active === opt ? 'bg-ink-900 text-white' : 'bg-surface-sunk text-text-secondary hover:bg-border/60'
          }`}
        >
          {t(opt)}
        </button>
      ))}
    </div>
  )
}
import { useLanguage } from '@/context/LanguageContext'
