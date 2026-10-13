import { Link } from 'react-router-dom'
import {
  BookOpenCheck,
  Users,
  CalendarClock,
  Inbox,
  FileClock,
  Bell,
  ArrowRight,
  MapPin,
  ClipboardCheck,
  GraduationCap,
  CalendarDays,
  Users2,
  Send,
} from 'lucide-react'
import { staff, courseSections, scheduleSlots, requests, exams, notifications, announcements } from '@staff/data/mockData'
import PageHeader from '@staff/components/layout/PageHeader'
import StatCard from '@staff/components/ui/StatCard'
import Card from '@staff/components/ui/Card'
import StatusBadge from '@staff/components/ui/StatusBadge'
import { useLanguage } from '@/context/LanguageContext'

export default function Dashboard() {
  const { isRtl, language, t } = useLanguage()
  const activeCourses = courseSections.filter((c) => c.status === 'Active')
  const totalStudents = activeCourses.reduce((sum, c) => sum + c.studentsCount, 0)
  const pendingRequests = requests.filter((r) => r.status === 'Pending').length
  const upcomingExams = exams.filter((e) => e.status === 'Upcoming')
  const unreadNotifs = notifications.filter((n) => !n.read).length

  const today = new Date()
  const todayLabel = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][today.getDay()]
  const todaysClasses = scheduleSlots.filter((s) => s.day === todayLabel)

  return (
    <div>
      <PageHeader
        title={`Welcome back, ${staff.firstName}`}
        description={`${staff.position} · ${staff.department}`}
        actions={
          <Link to="/attendance">
            <span className="inline-flex items-center gap-2 rounded-md bg-coral-500 px-4 py-2.5 text-sm font-semibold text-white hover:bg-coral-600">
              <ClipboardCheck className="h-4 w-4" />
              {t('Take Attendance')}
            </span>
          </Link>
        }
      />

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
        <StatCard label="Assigned Courses" value={String(activeCourses.length)} sublabel="Fall 2026" icon={<BookOpenCheck className="h-5 w-5" />} accent="teal" />
        <StatCard label="Total Students" value={String(totalStudents)} sublabel="Across all sections" icon={<Users className="h-5 w-5" />} accent="ink" />
        <StatCard label="Today's Classes" value={String(todaysClasses.length)} icon={<CalendarClock className="h-5 w-5" />} accent="teal" />
        <StatCard label="Pending Requests" value={String(pendingRequests)} icon={<Inbox className="h-5 w-5" />} accent="coral" />
        <StatCard label="Upcoming Exams" value={String(upcomingExams.length)} icon={<FileClock className="h-5 w-5" />} accent="ink" />
        <StatCard label="Unread Notifications" value={String(unreadNotifs)} icon={<Bell className="h-5 w-5" />} accent="coral" />
      </div>

      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-2">
          <Card padded={false}>
            <div className="flex items-center justify-between border-b border-border px-5 py-4">
              <h2 className="font-display text-base font-semibold text-text-primary">{t("Today's Schedule")}</h2>
              <Link to="/schedule" className="flex items-center gap-1 text-xs font-semibold text-teal-700 hover:underline">
                {t('Full schedule')} <ArrowRight className={`h-3 w-3 ${isRtl ? 'rtl-flip' : ''}`} />
              </Link>
            </div>
            {todaysClasses.length === 0 ? (
              <p className="px-5 py-8 text-center text-sm text-text-secondary">{t('No classes scheduled for today.')}</p>
            ) : (
              <div className="divide-y divide-border">
                {todaysClasses.map((s, i) => (
                  <div key={i} className="flex items-center gap-4 px-5 py-3.5">
                    <div className="w-16 shrink-0 font-mono text-sm font-semibold text-ink-900">{s.start}</div>
                    <div className="flex-1">
                      <p className="text-sm font-medium text-text-primary">{s.courseTitle}</p>
                      <p className="flex items-center gap-1 text-xs text-text-muted">
                        <MapPin className="h-3 w-3" /> {s.room} · {s.section}
                      </p>
                    </div>
                    <StatusBadge label={s.type} tone="info" />
                  </div>
                ))}
              </div>
            )}
          </Card>

          <Card padded={false}>
            <div className="flex items-center justify-between border-b border-border px-5 py-4">
              <h2 className="font-display text-base font-semibold text-text-primary">{t('My Courses')}</h2>
              <Link to="/courses" className="flex items-center gap-1 text-xs font-semibold text-teal-700 hover:underline">
                {t('View all')} <ArrowRight className={`h-3 w-3 ${isRtl ? 'rtl-flip' : ''}`} />
              </Link>
            </div>
            <div className="divide-y divide-border">
              {activeCourses.map((c) => (
                <Link key={c.id} to={`/courses/${c.id}`} className="flex items-center justify-between gap-3 px-5 py-3.5 hover:bg-surface-sunk/60">
                  <div>
                    <p className="font-mono text-xs font-semibold text-teal-700">{c.code} · {c.section}</p>
                    <p className="text-sm font-medium text-text-primary">{c.title}</p>
                  </div>
                  <span className="shrink-0 font-mono text-xs text-text-muted">{c.studentsCount} {t('students')}</span>
                </Link>
              ))}
            </div>
          </Card>
        </div>

        <div className="space-y-6">
          <Card padded={false}>
            <div className="flex items-center justify-between border-b border-border px-5 py-4">
              <h2 className="font-display text-base font-semibold text-text-primary">{t('Notifications')}</h2>
              <Link to="/notifications" className="flex items-center gap-1 text-xs font-semibold text-teal-700 hover:underline">
                {t('All')} <ArrowRight className={`h-3 w-3 ${isRtl ? 'rtl-flip' : ''}`} />
              </Link>
            </div>
            <div className="divide-y divide-border">
              {notifications.slice(0, 4).map((n) => (
                <div key={n.id} className="px-5 py-3.5">
                  <div className="flex items-center gap-2">
                    {!n.read && <span className="h-1.5 w-1.5 rounded-full bg-coral-500" />}
                    <p className="text-sm font-medium text-text-primary">{n.title}</p>
                  </div>
                  <p className="mt-0.5 text-xs text-text-muted">{n.timestamp}</p>
                </div>
              ))}
            </div>
          </Card>

          <Card padded={false}>
            <div className="flex items-center justify-between border-b border-border px-5 py-4">
              <h2 className="font-display text-base font-semibold text-text-primary">{t('Announcements')}</h2>
              <Link to="/announcements" className="flex items-center gap-1 text-xs font-semibold text-teal-700 hover:underline">
                {t('All')} <ArrowRight className={`h-3 w-3 ${isRtl ? 'rtl-flip' : ''}`} />
              </Link>
            </div>
            <div className="divide-y divide-border">
              {announcements.slice(0, 3).map((a) => (
                <div key={a.id} className="px-5 py-3.5">
                  <div className="flex items-center gap-2">
                    {!a.read && <span className="h-1.5 w-1.5 rounded-full bg-coral-500" />}
                    <p className="text-sm font-medium text-text-primary">{a.title}</p>
                  </div>
                  <p className="mt-0.5 text-xs text-text-muted">
                    {new Date(a.date).toLocaleDateString(language === 'ar' ? 'ar-EG' : 'en-GB', { month: 'short', day: 'numeric' })}
                  </p>
                </div>
              ))}
            </div>
          </Card>

          <Card>
            <h2 className="font-display text-base font-semibold text-text-primary">{t('Quick Actions')}</h2>
            <div className="mt-3 grid grid-cols-2 gap-2">
              {[
                { label: 'Enter Grades', to: '/grades', icon: GraduationCap },
                { label: 'Take Attendance', to: '/attendance', icon: ClipboardCheck },
                { label: 'View Schedule', to: '/schedule', icon: CalendarDays },
                { label: 'View Students', to: '/students', icon: Users2 },
                { label: 'Exam Schedule', to: '/exams', icon: FileClock },
                { label: 'Submit Request', to: '/services', icon: Send },
              ].map((a) => (
                <Link
                  key={a.label}
                  to={a.to}
                  className="flex flex-col items-center gap-1.5 rounded-md border border-border-strong px-3 py-3 text-center text-xs font-semibold text-text-primary hover:border-teal-500 hover:bg-teal-50 hover:text-teal-700"
                >
                  <a.icon className="h-4 w-4" />
                  {t(a.label)}
                </Link>
              ))}
            </div>
          </Card>
        </div>
      </div>
    </div>
  )
}
