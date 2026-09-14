import { type ReactNode } from 'react'
import Breadcrumbs from './Breadcrumbs'
import { useLanguage } from '@/context/LanguageContext'

interface PageHeaderProps {
  title: string
  description?: string
  crumbs?: { label: string; to?: string }[]
  actions?: ReactNode
}

export default function PageHeader({ title, description, crumbs, actions }: PageHeaderProps) {
  const { t } = useLanguage()

  return (
    <div className="mb-6">
      {crumbs && <Breadcrumbs items={crumbs} />}
      <div className="mt-2 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-text-primary">{t(title)}</h1>
          {description && <p className="mt-1 text-sm text-text-secondary">{t(description)}</p>}
        </div>
        {actions && <div className="flex shrink-0 items-center gap-2">{actions}</div>}
      </div>
    </div>
  )
}
