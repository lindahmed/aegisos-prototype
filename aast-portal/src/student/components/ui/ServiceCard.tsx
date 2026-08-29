import { Link } from 'react-router-dom'
import { ArrowUpRight, ExternalLink } from 'lucide-react'
import type { Service } from '@student/types'

const kindIndicator: Record<Service['kind'], { label: string; icon?: typeof ExternalLink }> = {
  redirect: { label: 'External', icon: ExternalLink },
  form: { label: 'Request Form' },
  viewer: { label: 'View' },
  tool: { label: 'Interactive' },
  info: { label: 'Guide' },
}

export default function ServiceCard({ service }: { service: Service }) {
  const Icon = service.icon
  const indicator = kindIndicator[service.kind]

  return (
    <Link
      to={`/services/${service.slug}`}
      className="group flex flex-col gap-3 rounded-lg border border-border bg-surface p-4 shadow-card transition-all hover:-translate-y-0.5 hover:border-teal-500 hover:shadow-raised focus-visible:-translate-y-0.5 focus-visible:border-teal-500"
    >
      <div className="flex items-start justify-between">
        <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-md bg-teal-50 text-teal-600 transition-colors group-hover:bg-teal-600 group-hover:text-white">
          <Icon className="h-5 w-5" />
        </div>
        <ArrowUpRight className="h-4 w-4 shrink-0 text-text-muted opacity-0 transition-opacity group-hover:opacity-100" />
      </div>
      <div>
        <p className="font-display text-sm font-semibold leading-tight text-text-primary">{service.name}</p>
        <p className="mt-1 line-clamp-2 text-xs text-text-secondary">{service.description}</p>
      </div>
      <div className="mt-auto flex items-center gap-1 pt-1 text-[11px] font-semibold uppercase tracking-wide text-text-muted">
        {indicator.icon && <indicator.icon className="h-3 w-3" />}
        {indicator.label}
      </div>
    </Link>
  )
}
