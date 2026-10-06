import { type ReactNode } from 'react'

interface CardProps {
  children: ReactNode
  className?: string
  padded?: boolean
  accent?: 'teal' | 'coral' | 'ink' | 'none'
}

const accentBorder: Record<string, string> = {
  teal: 'border-l-4 border-l-teal-500',
  coral: 'border-l-4 border-l-coral-500',
  ink: 'border-l-4 border-l-ink-800',
  none: '',
}

export default function Card({ children, className = '', padded = true, accent = 'none' }: CardProps) {
  return (
    <div
      className={`portal-card bg-surface rounded-lg border border-border shadow-card ${accentBorder[accent]} ${
        padded ? 'p-5' : ''
      } ${className}`}
    >
      {children}
    </div>
  )
}
