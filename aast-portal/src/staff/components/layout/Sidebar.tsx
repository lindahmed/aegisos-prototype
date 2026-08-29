import { NavLink } from 'react-router-dom'
import {
  LayoutDashboard,
  BookOpen,
  Layers,
  Users,
  ClipboardCheck,
  GraduationCap,
  FolderOpen,
  CalendarDays,
  CalendarRange,
  FileClock,
  FileCheck2,
  Users2,
  ClipboardList,
  Search,
  UserSearch,
  FileText,
  MessageSquareWarning,
  BarChart3,
  ClipboardEdit,
  Award,
  PieChart,
  LayoutGrid,
  Inbox,
  LifeBuoy,
  Megaphone,
  UserRound,
  UserCog,
  KeyRound,
  Settings,
  GraduationCap as Crest,
} from 'lucide-react'
import { staff } from '@staff/data/mockData'

const navGroups = [
  {
    label: 'Dashboard',
    items: [{ to: '/', label: 'Dashboard', icon: LayoutDashboard }],
  },
  {
    label: 'Academic',
    items: [
      { to: '/courses', label: 'My Courses', icon: BookOpen },
      { to: '/courses', label: 'Course Sections', icon: Layers },
      { to: '/students', label: 'Student List', icon: Users },
      { to: '/attendance', label: 'Attendance', icon: ClipboardCheck },
      { to: '/grades', label: 'Grades', icon: GraduationCap },
      { to: '/courses', label: 'Course Materials', icon: FolderOpen },
    ],
  },
  {
    label: 'Schedule',
    items: [
      { to: '/schedule', label: 'My Schedule', icon: CalendarDays },
      { to: '/schedule?view=college', label: 'College Schedule', icon: CalendarRange },
      { to: '/exams', label: 'Exam Schedule', icon: FileClock },
    ],
  },
  {
    label: 'Exams',
    items: [
      { to: '/exams', label: 'Exam Schedule', icon: FileClock },
      { to: '/exams?tab=Results', label: 'Exam Results', icon: FileCheck2 },
      { to: '/exams?tab=Committees', label: 'Exam Committees', icon: Users2 },
      { to: '/requests?origin=Exam', label: 'Exam Requests', icon: ClipboardList },
    ],
  },
  {
    label: 'Students',
    items: [
      { to: '/students', label: 'Student Search', icon: Search },
      { to: '/students', label: 'Student Information', icon: UserSearch },
      { to: '/students', label: 'Academic Record', icon: FileText },
      { to: '/requests?origin=student', label: 'Student Requests', icon: MessageSquareWarning },
    ],
  },
  {
    label: 'Reports',
    items: [
      { to: '/reports?tab=Academic', label: 'Academic Reports', icon: BarChart3 },
      { to: '/reports?tab=Attendance', label: 'Attendance Reports', icon: ClipboardEdit },
      { to: '/reports?tab=Grades', label: 'Grade Reports', icon: Award },
      { to: '/reports?tab=Statistics', label: 'Statistics', icon: PieChart },
    ],
  },
  {
    label: 'Services',
    items: [
      { to: '/services', label: 'Staff Services', icon: LayoutGrid },
      { to: '/requests', label: 'Requests', icon: Inbox },
      { to: '/support', label: 'Support and inquiries', icon: LifeBuoy },
      { to: '/announcements', label: 'Announcements', icon: Megaphone },
    ],
  },
  {
    label: 'Profile',
    items: [
      { to: '/profile', label: 'My Profile', icon: UserRound },
      { to: '/profile/update', label: 'Update Data', icon: UserCog },
      { to: '/profile/password', label: 'Change Password', icon: KeyRound },
      { to: '/settings', label: 'Settings', icon: Settings },
    ],
  },
]

export default function Sidebar({ onNavigate }: { onNavigate?: () => void }) {
  return (
    <div className="flex h-full flex-col bg-ink-900 text-text-onDark">
      <div className="flex items-center gap-2.5 px-5 py-5">
        <div className="flex h-9 w-9 items-center justify-center rounded-md bg-teal-600 text-white">
          <Crest className="h-5 w-5" />
        </div>
        <div>
          <p className="font-display text-sm font-bold leading-tight text-white">AAST</p>
          <p className="text-xs text-white/50">Staff Portal</p>
        </div>
      </div>

      <div className="mx-4 mb-4 rounded-md bg-white/5 p-3.5">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-teal-500 font-display text-sm font-bold text-white">
            {staff.avatarInitials}
          </div>
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold text-white">{staff.firstName}</p>
            <p className="truncate font-mono text-xs text-white/50">{staff.staffId}</p>
          </div>
        </div>
      </div>

      <nav className="flex-1 space-y-5 overflow-y-auto px-3 pb-6 scrollbar-thin">
        {navGroups.map((group) => (
          <div key={group.label}>
            <p className="px-3 pb-1.5 text-xs font-semibold uppercase tracking-wider text-white/35">{group.label}</p>
            <div className="space-y-0.5">
              {group.items.map((item, i) => (
                <NavLink
                  key={`${item.to}-${i}`}
                  to={item.to}
                  end={item.to === '/'}
                  onClick={onNavigate}
                  className={({ isActive }) =>
                    `flex items-center gap-2.5 rounded-md px-3 py-2 text-sm font-medium transition-colors ${
                      isActive ? 'bg-teal-600 text-white' : 'text-white/70 hover:bg-white/5 hover:text-white'
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
        <p className="text-xs text-white/35">{staff.department}</p>
        <p className="text-xs text-white/35">v2.1.0</p>
      </div>
    </div>
  )
}
