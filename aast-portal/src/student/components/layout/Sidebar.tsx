import { NavLink } from 'react-router-dom'
import {
  LayoutDashboard,
  UserRound,
  ClipboardList,
  BookOpen,
  CalendarDays,
  GraduationCap,
  FileClock,
  Wallet,
  Megaphone,
  FileText,
  LayoutGrid,
  GraduationCap as Crest,
} from 'lucide-react'
import { useAuth } from '@student/context/AuthContext'

const navGroups = [
  {
    label: 'Overview',
    items: [
      { to: '/', label: 'Dashboard', icon: LayoutDashboard },
      { to: '/services', label: 'All Services', icon: LayoutGrid },
    ],
  },
  {
    label: 'Academics',
    items: [
      { to: '/registration', label: 'Registration', icon: ClipboardList },
      { to: '/courses', label: 'Courses', icon: BookOpen },
      { to: '/schedule', label: 'Calendar', icon: CalendarDays },
      { to: '/grades', label: 'Grades', icon: GraduationCap },
      { to: '/exams', label: 'Exams', icon: FileClock },
    ],
  },
  {
    label: 'Campus',
    items: [
      { to: '/fees', label: 'Fees', icon: Wallet },
      { to: '/announcements', label: 'Announcements', icon: Megaphone },
      { to: '/documents', label: 'Documents', icon: FileText },
    ],
  },
  {
    label: 'Account',
    items: [{ to: '/profile', label: 'Profile', icon: UserRound }],
  },
]

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

export default function Sidebar({ onNavigate }: { onNavigate?: () => void }) {
  const { student, portalId } = useAuth()

  const displayName = student?.name ?? 'Student'
  const displayId = student?.student_id ?? portalId ?? ''

  return (
    <div className="flex h-full flex-col bg-ink-900 text-text-onDark">
      <div className="flex items-center gap-2.5 px-5 py-5">
        <div className="flex h-9 w-9 items-center justify-center rounded-md bg-teal-600 text-white">
          <Crest className="h-5 w-5" />
        </div>
        <div>
          <p className="font-display text-sm font-bold leading-tight text-white">AAST</p>
          <p className="text-xs text-white/50">Student Portal</p>
        </div>
      </div>

      <div className="mx-4 mb-4 rounded-md bg-white/5 p-3.5">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-teal-500 font-display text-sm font-bold text-white">
            {initials(displayName)}
          </div>
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold text-white">{firstName(displayName)}</p>
            <p className="truncate font-mono text-xs text-white/50">{displayId}</p>
          </div>
        </div>
      </div>

      <nav className="flex-1 space-y-5 overflow-y-auto px-3 pb-6 scrollbar-thin">
        {navGroups.map((group) => (
          <div key={group.label}>
            <p className="px-3 pb-1.5 text-xs font-semibold uppercase tracking-wider text-white/35">{group.label}</p>
            <div className="space-y-0.5">
              {group.items.map((item) => (
                <NavLink
                  key={item.to}
                  to={item.to}
                  end={item.to === '/'}
                  onClick={onNavigate}
                  className={({ isActive }) =>
                    `flex items-center gap-2.5 rounded-md px-3 py-2 text-sm font-medium transition-colors ${
                      isActive
                        ? 'bg-teal-600 text-white'
                        : 'text-white/70 hover:bg-white/5 hover:text-white'
                    }`
                  }
                >
                  <item.icon className="h-4 w-4 shrink-0" />
                  {item.label}
                </NavLink>
              ))}
            </div>
          </div>
        ))}
      </nav>

      <div className="border-t border-white/10 px-5 py-4">
        <p className="text-xs text-white/35">{student?.major ?? ''}</p>
        <p className="text-xs text-white/35">v2.1.0</p>
      </div>
    </div>
  )
}
