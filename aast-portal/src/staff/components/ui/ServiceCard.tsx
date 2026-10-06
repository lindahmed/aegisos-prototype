import { Link } from 'react-router-dom'
import type { StaffService } from '@staff/types'

export default function ServiceCard({ service }: { service: StaffService }) {
  const Icon = service.icon

  return (
    <Link
      to={'/services/' + service.slug}
      title={service.description}
      aria-label={service.name + ': ' + service.description}
      className="group flex min-w-0 flex-col items-center gap-2.5 rounded-lg px-2 py-3 text-center transition-colors hover:bg-surface focus-visible:bg-surface"
    >
      <span className="flex h-16 w-16 items-center justify-center rounded-xl border border-border bg-surface text-teal-600 shadow-card transition-all group-hover:-translate-y-0.5 group-hover:border-teal-500 group-hover:bg-teal-600 group-hover:text-white group-hover:shadow-raised">
        <Icon className="h-7 w-7" />
      </span>
      <span className="line-clamp-2 text-xs font-semibold leading-tight text-text-primary">
        {service.name}
      </span>
    </Link>
  )
}
