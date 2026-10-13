import { Link } from 'react-router-dom'
import { ChevronRight, Home } from 'lucide-react'
import { useLanguage } from '@/context/LanguageContext'

interface Crumb {
  label: string
  to?: string
}

export default function Breadcrumbs({ items }: { items: Crumb[] }) {
  const { isRtl, t } = useLanguage()

  return (
    <nav aria-label={t('Breadcrumb')} className="flex items-center gap-1.5 text-sm text-text-muted">
      <Link to="/" className="flex items-center hover:text-text-primary">
        <Home className="h-3.5 w-3.5" />
      </Link>
      {items.map((c, i) => (
        <span key={i} className="flex items-center gap-1.5">
          <ChevronRight className={`h-3.5 w-3.5 ${isRtl ? 'rtl-flip' : ''}`} />
          {c.to ? (
            <Link to={c.to} className="hover:text-text-primary">
              {t(c.label)}
            </Link>
          ) : (
            <span className="font-medium text-text-primary">{t(c.label)}</span>
          )}
        </span>
      ))}
    </nav>
  )
}
