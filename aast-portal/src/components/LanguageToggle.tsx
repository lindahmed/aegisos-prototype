import { Globe2 } from 'lucide-react'
import { useLanguage } from '@/context/LanguageContext'

export default function LanguageToggle({ compact = false }: { compact?: boolean }) {
  const { language, toggleLanguage, t } = useLanguage()
  const label = language === 'en' ? t('Switch to Arabic') : t('Switch to English')

  return (
    <button
      type="button"
      onClick={toggleLanguage}
      aria-label={label}
      title={label}
      className={`language-toggle ${compact ? 'language-toggle-compact' : ''}`}
    >
      <Globe2 className="h-5 w-5" strokeWidth={1.9} />
      {!compact && <span>{language === 'en' ? 'العربية' : 'English'}</span>}
    </button>
  )
}
