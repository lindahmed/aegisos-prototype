export function TableSkeleton({ rows = 5, cols = 4 }: { rows?: number; cols?: number }) {
  return (
    <div className="animate-pulse">
      {Array.from({ length: rows }).map((_, r) => (
        <div key={r} className="flex gap-4 border-b border-border px-4 py-3.5 last:border-0">
          {Array.from({ length: cols }).map((_, c) => (
            <div key={c} className="h-3.5 flex-1 rounded bg-surface-sunk" />
          ))}
        </div>
      ))}
    </div>
  )
}

export function CardSkeleton() {
  return (
    <div className="animate-pulse rounded-lg border border-border bg-surface p-5">
      <div className="h-3.5 w-1/3 rounded bg-surface-sunk" />
      <div className="mt-3 h-6 w-1/2 rounded bg-surface-sunk" />
      <div className="mt-2 h-3 w-2/3 rounded bg-surface-sunk" />
    </div>
  )
}

export function Spinner({ className = 'h-5 w-5' }: { className?: string }) {
  return (
    <div
      className={`${className} animate-spin rounded-full border-2 border-border-strong border-t-teal-600`}
      role="status"
      aria-label="Loading"
    />
  )
}
