import { useState } from 'react'
import { Link, NavLink, useNavigate } from 'react-router-dom'
import {
  Bell,
  BarChart3,
  BookOpen,
  CalendarDays,
  ClipboardCheck,
  FileClock,
  GraduationCap,
  ChevronDown,
  ClipboardList,
  Home,
  LayoutGrid,
  LifeBuoy,
  LogOut,
  Megaphone,
  MessageCircle,
  Settings,
  UserRound,
  Users,
  ShieldAlert,
} from 'lucide-react'
import { staff, notifications } from '@staff/data/mockData'
import { useAuth } from '@staff/context/AuthContext'
import LanguageToggle from '@/components/LanguageToggle'
import { useLanguage } from '@/context/LanguageContext'

const primaryNav = [
  { to: '/', label: 'Dashboard', icon: Home },
  { to: '/courses', label: 'Courses', icon: BookOpen },
  { to: '/attendance', label: 'Attendance', icon: ClipboardCheck },
  { to: '/grades', label: 'Grades', icon: GraduationCap },
  { to: '/exams', label: 'Exams', icon: FileClock },
  { to: '/reports', label: 'Reports', icon: BarChart3 },
  { to: '/support', label: 'Support', icon: LifeBuoy },
  { to: '/schedule', label: 'Schedule', icon: CalendarDays },
  { to: '/students', label: 'Students', icon: Users },
  { to: '/case-management', label: 'Case Management', icon: ShieldAlert },
  { to: '/requests', label: 'Requests', icon: ClipboardList },
  { to: '/services', label: 'Services', icon: LayoutGrid },
  { to: '/announcements', label: 'Announcements', icon: Megaphone },
]

function NavigationLinks({ mobile = false }: { mobile?: boolean }) {
  const { t } = useLanguage()

  return (
    <nav
      aria-label={t('Staff navigation')}
      className={mobile
        ? 'flex min-w-max items-center gap-1.5 px-3 py-2.5'
        : 'hidden items-center gap-0.5 lg:flex'}
    >
      {primaryNav.map((item) => (
        <NavLink
          key={item.to}
          to={item.to}
          end={item.to === '/'}
          title={t(item.label)}
          aria-label={t(item.label)}
          data-tooltip={mobile ? undefined : t(item.label)}
          className={({ isActive }) =>
            (mobile
              ? 'flex min-w-[4.5rem] flex-col items-center gap-1 rounded-lg border px-2 py-1.5 text-[11px] font-semibold '
              : 'nav-icon-link ') +
            (isActive
              ? (mobile ? 'border-teal-600 bg-teal-600 text-white' : 'nav-icon-link-active')
              : (mobile ? 'border-border bg-white text-text-secondary hover:border-teal-500 hover:bg-teal-50 hover:text-teal-700' : ''))
          }
        >
          <item.icon className="h-5 w-5 shrink-0" strokeWidth={1.9} />
          <span className={mobile ? '' : 'sr-only'}>{t(item.label)}</span>
        </NavLink>
      ))}
    </nav>
  )
}

export default function Header() {
  const [notifOpen, setNotifOpen] = useState(false)
  const [profileOpen, setProfileOpen] = useState(false)
  const unread = notifications.filter((notification) => !notification.read).length
  const { logout } = useAuth()
  const { t } = useLanguage()
  const navigate = useNavigate()

  return (
    <header className="sticky top-0 z-30 shrink-0 border-b-2 border-ink-800 bg-white/95 shadow-[0_6px_24px_rgba(11,36,66,0.08)] backdrop-blur">
      <div className="mx-auto flex h-[4.5rem] max-w-screen-2xl items-center justify-between gap-3 px-4 sm:px-6 lg:px-8">
        <Link to="/" className="flex shrink-0 items-center gap-2.5" aria-label={t('AAST Portal home')}>
          <span className="flex h-11 w-11 items-center justify-center rounded-lg bg-gradient-to-br from-teal-500 to-ink-800 text-white shadow-card">
            <GraduationCap className="h-6 w-6" strokeWidth={1.9} />
          </span>
          <span className="hidden font-display text-base font-bold text-ink-900 xl:inline">{t('AAST Portal')}</span>
        </Link>

        <NavigationLinks />

        <div className="flex items-center gap-1 sm:gap-2">
          <div className="hidden md:block"><LanguageToggle /></div>

          <Link
            to="/messages"
            aria-label={t('Inbox')}
            title={t('Inbox')}
            className="relative flex h-10 w-10 items-center justify-center rounded-lg border border-border bg-white text-text-secondary shadow-card transition-all hover:border-teal-500 hover:bg-teal-50 hover:text-teal-700"
          >
            <MessageCircle className="h-5 w-5" strokeWidth={1.9} />
          </Link>

          <div className="relative">
            <button
              type="button"
              onClick={() => {
                setNotifOpen((open) => !open)
                setProfileOpen(false)
              }}
              aria-label={t('Notifications')}
              title={t('Notifications')}
              aria-expanded={notifOpen}
              className="relative flex h-10 w-10 items-center justify-center rounded-lg border border-border bg-white text-text-secondary shadow-card transition-all hover:border-teal-500 hover:bg-teal-50 hover:text-teal-700"
            >
              <Bell className="h-5 w-5" strokeWidth={1.9} />
              {unread > 0 && (
                <span className="absolute right-1 top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-coral-500 px-1 text-[10px] font-bold text-white">
                  {unread}
                </span>
              )}
            </button>
            {notifOpen && (
              <div className="absolute end-0 mt-2 w-[min(20rem,calc(100vw-2rem))] rounded-lg border border-border bg-surface py-2 shadow-raised">
                <div className="flex items-center justify-between px-3.5 pb-2">
                  <p className="text-sm font-semibold text-text-primary">{t('Notifications')}</p>
                  <Link
                    to="/notifications"
                    onClick={() => setNotifOpen(false)}
                    className="text-xs font-semibold text-teal-700 hover:underline"
                  >
                    {t('View all')}
                  </Link>
                </div>
                <div className="max-h-72 overflow-y-auto scrollbar-thin">
                  {notifications.slice(0, 4).map((notification) => (
                    <div key={notification.id} className="flex gap-2.5 border-t border-border px-3.5 py-2.5">
                      <span
                        className={
                          'mt-1 h-1.5 w-1.5 shrink-0 rounded-full ' +
                          (notification.read ? 'bg-transparent' : 'bg-coral-500')
                        }
                      />
                      <div className="min-w-0">
                        <p className="truncate text-sm font-medium text-text-primary">{notification.title}</p>
                        <p className="text-xs text-text-muted">{notification.timestamp}</p>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>

          <div className="relative">
            <button
              type="button"
              onClick={() => {
                setProfileOpen((open) => !open)
                setNotifOpen(false)
              }}
              className="flex items-center gap-2 rounded-md py-1.5 pe-2 ps-1.5 hover:bg-surface-sunk"
            >
              <div className="flex h-8 w-8 items-center justify-center rounded-full bg-teal-600 font-display text-xs font-bold text-white">
                {staff.avatarInitials}
              </div>
              <span className="hidden text-sm font-medium text-text-primary md:inline">{staff.firstName}</span>
              <ChevronDown className="hidden h-3.5 w-3.5 text-text-muted md:inline" />
            </button>
            {profileOpen && (
              <div className="absolute end-0 mt-2 w-56 rounded-lg border border-border bg-surface py-1.5 shadow-raised">
                <div className="border-b border-border px-3.5 py-2.5">
                  <p className="truncate text-sm font-semibold text-text-primary">{staff.fullName}</p>
                  <p className="font-mono text-xs text-text-muted">{staff.staffId}</p>
                </div>
                <Link
                  to="/profile"
                  onClick={() => setProfileOpen(false)}
                  className="flex items-center gap-2.5 px-3.5 py-2 text-sm text-text-primary hover:bg-surface-sunk"
                >
                  <UserRound className="h-4 w-4 text-text-muted" />
                  {t('My Profile')}
                </Link>
                <Link
                  to="/settings"
                  onClick={() => setProfileOpen(false)}
                  className="flex items-center gap-2.5 px-3.5 py-2 text-sm text-text-primary hover:bg-surface-sunk"
                >
                  <Settings className="h-4 w-4 text-text-muted" />
                  {t('Settings')}
                </Link>
                <button
                  type="button"
                  onClick={() => {
                    logout()
                    navigate('/login')
                  }}
                  className="flex w-full items-center gap-2.5 border-t border-border px-3.5 py-2 text-left text-sm text-error hover:bg-error-100"
                >
                  <LogOut className="h-4 w-4" />
                  {t('Sign out')}
                </button>
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="flex items-center border-t border-border bg-surface-raised lg:hidden">
        <div className="overflow-x-auto scrollbar-thin"><NavigationLinks mobile /></div>
        <div className="shrink-0 border-s border-border px-2 md:hidden"><LanguageToggle compact /></div>
      </div>
    </header>
  )
}
