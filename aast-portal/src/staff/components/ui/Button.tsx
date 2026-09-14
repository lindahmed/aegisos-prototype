import { type ButtonHTMLAttributes, type ReactNode } from 'react'
import { Loader2 } from 'lucide-react'

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger'
  size?: 'sm' | 'md'
  loading?: boolean
  icon?: ReactNode
  children: ReactNode
}

const variants: Record<string, string> = {
  primary:
    'bg-teal-600 text-white hover:bg-teal-700 active:bg-teal-700 focus-visible:outline-teal-700 disabled:bg-teal-600/40',
  secondary:
    'bg-white text-ink-900 border border-border-strong hover:bg-surface-sunk active:bg-border/40 disabled:text-text-muted',
  ghost:
    'bg-transparent text-ink-900 hover:bg-surface-sunk active:bg-border/40 disabled:text-text-muted',
  danger:
    'bg-error text-white hover:bg-error/90 active:bg-error disabled:bg-error/40',
}

const sizes: Record<string, string> = {
  sm: 'text-sm px-3 py-1.5 gap-1.5',
  md: 'text-sm px-4 py-2.5 gap-2',
}

export default function Button({
  variant = 'primary',
  size = 'md',
  loading = false,
  icon,
  children,
  className = '',
  disabled,
  ...rest
}: ButtonProps) {
  return (
    <button
      className={`inline-flex items-center justify-center rounded-md font-semibold transition-colors duration-150 disabled:cursor-not-allowed ${variants[variant]} ${sizes[size]} ${className}`}
      disabled={disabled || loading}
      {...rest}
    >
      {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : icon}
      {children}
    </button>
  )
}
