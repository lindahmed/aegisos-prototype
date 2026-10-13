import { Search, X } from 'lucide-react'
import { useLanguage } from '@/context/LanguageContext'

interface SearchBarProps {
  value: string
  onChange: (value: string) => void
  placeholder?: string
  className?: string
}

export default function SearchBar({ value, onChange, placeholder = 'Search…', className = '' }: SearchBarProps) {
  const { t } = useLanguage()
  const translatedPlaceholder = t(placeholder)

  return (
    <div className={`relative ${className}`}>
      <Search className="pointer-events-none absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted" />
      <input
        type="text"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={translatedPlaceholder}
        aria-label={translatedPlaceholder}
        className="w-full rounded-md border border-border-strong bg-white py-2.5 pe-9 ps-9 text-sm text-text-primary placeholder:text-text-muted focus-visible:outline-2 focus-visible:outline-teal-600"
      />
      {value && (
        <button
          onClick={() => onChange('')}
          aria-label={t('Clear search')}
          className="absolute end-2.5 top-1/2 -translate-y-1/2 text-text-muted hover:text-text-primary"
        >
          <X className="h-4 w-4" />
        </button>
      )}
    </div>
  )
}
