import { useEffect, useRef, useState, type ReactNode } from 'react'
import { ChevronDown } from 'lucide-react'
import { useLanguage } from '@/context/LanguageContext'

interface DropdownOption {
  label: string
  value: string
  icon?: ReactNode
}

interface DropdownProps {
  label: string
  options: DropdownOption[]
  value?: string
  onSelect: (value: string) => void
  align?: 'left' | 'right'
}

export default function Dropdown({ label, options, value, onSelect, align = 'left' }: DropdownProps) {
  const { isRtl, t } = useLanguage()
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', onClick)
    return () => document.removeEventListener('mousedown', onClick)
  }, [])

  const current = options.find((o) => o.value === value)

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="listbox"
        aria-expanded={open}
        className="flex items-center gap-2 rounded-md border border-border-strong bg-white px-3 py-2 text-sm font-medium text-text-primary hover:bg-surface-sunk"
      >
        {current?.icon}
        {t(current?.label ?? label)}
        <ChevronDown className={`h-3.5 w-3.5 text-text-muted transition-transform ${open ? 'rotate-180' : ''}`} />
      </button>
      {open && (
        <div
          role="listbox"
          className={`absolute z-20 mt-1.5 min-w-[180px] rounded-md border border-border bg-surface py-1 shadow-raised ${
            (align === 'right') !== isRtl ? 'end-0' : 'start-0'
          }`}
        >
          {options.map((opt) => (
            <button
              key={opt.value}
              role="option"
              aria-selected={opt.value === value}
              onClick={() => {
                onSelect(opt.value)
                setOpen(false)
              }}
              className={`flex w-full items-center gap-2 px-3 py-2 text-left text-sm hover:bg-surface-sunk ${
                opt.value === value ? 'font-semibold text-teal-700' : 'text-text-primary'
              }`}
            >
              {opt.icon}
              {t(opt.label)}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
