import { X } from 'lucide-react'
import Sidebar from './Sidebar'

interface MobileNavigationProps {
  open: boolean
  onClose: () => void
}

export default function MobileNavigation({ open, onClose }: MobileNavigationProps) {
  if (!open) return null
  return (
    <div className="fixed inset-0 z-50 lg:hidden">
      <div className="absolute inset-0 bg-ink-900/50" onClick={onClose} aria-hidden="true" />
      <div className="relative flex h-full w-72 max-w-[80vw] flex-col animate-[slideIn_0.2s_ease-out]">
        <button
          onClick={onClose}
          aria-label="Close menu"
          className="absolute right-3 top-4 z-10 flex h-8 w-8 items-center justify-center rounded-md text-white/70 hover:bg-white/10 hover:text-white"
        >
          <X className="h-5 w-5" />
        </button>
        <Sidebar onNavigate={onClose} />
      </div>
    </div>
  )
}
