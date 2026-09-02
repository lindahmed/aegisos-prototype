import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Menu, Bell, Globe, MessageSquareText, ChevronDown, LogOut, UserRound, Settings } from 'lucide-react'
import { useAuth } from '@student/context/AuthContext'
import { useNotifications } from '@student/context/NotificationsContext'

function initials(name: string): string {
  return name
    .split(' ')
    .map((n) => n[0])
    .slice(0, 2)
    .join('')
    .toUpperCase()
}

function firstName(name: string): string {
  return name.split(' ')[0] ?? name
}

export default function Header({ onMenuClick }: { onMenuClick: () => void }) {
  const [notifOpen, setNotifOpen] = useState(false)
  const [profileOpen, setProfileOpen] = useState(false)
  const notifRef = useRef<HTMLDivElement>(null)
  const { notifications, loading: notificationsLoading } = useNotifications()
  const unread = notifications.filter((n) => !n.read).length
  const { logout, student, portalId } = useAuth()
  const navigate = useNavigate()

  const displayName = student?.name ?? 'Student'
  const displayId = student?.student_id ?? portalId ?? ''

  useEffect(() => {
    if (!notifOpen) return
    const closeOnOutsideClick = (event: PointerEvent) => {
      if (event.target instanceof Node && !notifRef.current?.contains(event.target)) {
        setNotifOpen(false)
      }
    }
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setNotifOpen(false)
    }
    document.addEventListener('pointerdown', closeOnOutsideClick)
    document.addEventListener('keydown', closeOnEscape)
    return () => {
      document.removeEventListener('pointerdown', closeOnOutsideClick)
      document.removeEventListener('keydown', closeOnEscape)
    }
  }, [notifOpen])

  return (
    <header className="sticky top-0 z-30 flex h-16 items-center justify-between border-b border-border bg-surface/95 px-4 backdrop-blur sm:px-6">
      <div className="flex items-center gap-3">
        <button
          onClick={onMenuClick}
          aria-label="Open menu"
          className="flex h-9 w-9 items-center justify-center rounded-md text-text-secondary hover:bg-surface-sunk lg:hidden"
        >
          <Menu className="h-5 w-5" />
        </button>
        <Link to="/announcements" className="hidden items-center gap-1.5 text-sm font-medium text-text-secondary hover:text-teal-700 sm:flex">
          <MessageSquareText className="h-4 w-4" />
          News
        </Link>
      </div>

      <div className="flex items-center gap-1 sm:gap-2">
        <button className="hidden items-center gap-1.5 rounded-md px-2.5 py-2 text-sm font-medium text-text-secondary hover:bg-surface-sunk hover:text-teal-700 md:flex">
          <Globe className="h-4 w-4" />
          EN
          <ChevronDown className="h-3 w-3" />
        </button>

        <div ref={notifRef} className="relative">
          <button
            onClick={() => {
              const opening = !notifOpen
              setNotifOpen(opening)
              setProfileOpen(false)
            }}
            aria-label="Notifications"
            aria-expanded={notifOpen}
            aria-controls="student-notifications-menu"
            className="relative flex h-9 w-9 items-center justify-center rounded-md text-text-secondary hover:bg-surface-sunk"
          >
            <Bell className="h-4.5 w-4.5" />
            {unread > 0 && (
              <span className="absolute right-1 top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-coral-500 px-1 text-[10px] font-bold text-white">
                {unread}
              </span>
            )}
          </button>
          {notifOpen && (
            <div id="student-notifications-menu" className="absolute right-0 mt-2 w-80 rounded-lg border border-border bg-surface py-2 shadow-raised">
              <div className="flex items-center justify-between px-3.5 pb-2">
                <p className="text-sm font-semibold text-text-primary">Notifications</p>
                <Link to="/notifications" onClick={() => setNotifOpen(false)} className="text-xs font-semibold text-teal-700 hover:underline">
                  View all
                </Link>
              </div>
              <div className="max-h-72 overflow-y-auto scrollbar-thin">
                {notificationsLoading && notifications.length === 0 && (
                  <p className="border-t border-border px-3.5 py-5 text-center text-xs text-text-muted">Loading notifications…</p>
                )}
                {notifications.slice(0, 4).map((n) => (
                  <div key={n.id} className="flex gap-2.5 border-t border-border px-3.5 py-2.5">
                    <span className={`mt-1 h-1.5 w-1.5 shrink-0 rounded-full ${n.read ? 'bg-transparent' : 'bg-coral-500'}`} />
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium text-text-primary">{n.title}</p>
                      <p className="text-xs text-text-muted">{n.timestamp}</p>
                    </div>
                  </div>
                ))}
                {!notificationsLoading && notifications.length === 0 && (
                  <p className="border-t border-border px-3.5 py-5 text-center text-xs text-text-muted">You are all caught up.</p>
                )}
              </div>
            </div>
          )}
        </div>

        <div className="relative">
          <button
            onClick={() => {
              setProfileOpen((o) => !o)
              setNotifOpen(false)
            }}
            className="flex items-center gap-2 rounded-md py-1.5 pl-1.5 pr-2 hover:bg-surface-sunk"
          >
            <div className="flex h-8 w-8 items-center justify-center rounded-full bg-teal-600 font-display text-xs font-bold text-white">
              {initials(displayName)}
            </div>
            <span className="hidden text-sm font-medium text-text-primary md:inline">{firstName(displayName)}</span>
            <ChevronDown className="hidden h-3.5 w-3.5 text-text-muted md:inline" />
          </button>
          {profileOpen && (
            <div className="absolute right-0 mt-2 w-56 rounded-lg border border-border bg-surface py-1.5 shadow-raised">
              <div className="border-b border-border px-3.5 py-2.5">
                <p className="truncate text-sm font-semibold text-text-primary">{displayName}</p>
                <p className="font-mono text-xs text-text-muted">{displayId}</p>
              </div>
              <Link
                to="/profile"
                onClick={() => setProfileOpen(false)}
                className="flex items-center gap-2.5 px-3.5 py-2 text-sm text-text-primary hover:bg-surface-sunk"
              >
                <UserRound className="h-4 w-4 text-text-muted" />
                My Profile
              </Link>
              <button className="flex w-full items-center gap-2.5 px-3.5 py-2 text-left text-sm text-text-primary hover:bg-surface-sunk">
                <Settings className="h-4 w-4 text-text-muted" />
                Settings
              </button>
              <button
                onClick={() => {
                  logout()
                  navigate('/login')
                }}
                className="flex w-full items-center gap-2.5 border-t border-border px-3.5 py-2 text-left text-sm text-error hover:bg-error-100"
              >
                <LogOut className="h-4 w-4" />
                Sign out
              </button>
            </div>
          )}
        </div>
      </div>
    </header>
  )
}
