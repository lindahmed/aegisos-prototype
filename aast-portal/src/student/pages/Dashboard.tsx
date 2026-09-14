import { Link } from 'react-router-dom'
import {
  Clock,
  MapPin,
  ClipboardList,
  CalendarDays,
  FileText,
  ArrowRight,
  LayoutGrid,
  AlertTriangle,
} from 'lucide-react'
import { useAuth } from '@student/context/AuthContext'
import { useStudentAcademics } from '@student/context/StudentAcademicsContext'
import { exams, announcements, scheduleSlots } from '@student/data/mockData'
import PageHeader from '@student/components/layout/PageHeader'
import Card from '@student/components/ui/Card'
import StatusBadge from '@student/components/ui/StatusBadge'
import EmptyState from '@student/components/ui/EmptyState'
import { CardSkeleton, TableSkeleton } from '@student/components/ui/LoadingState'
import { useLanguage } from '@/context/LanguageContext'

function firstName(name: string): string {
  return name.split(' ')[0] ?? name
}

function courseStatus(health: number | null): { label: string; tone: 'success' | 'warning' | 'error' | 'info' } {
  if (health === null) return { label: 'No data', tone: 'info' }
  if (health >= 70) return { label: 'On Track', tone: 'success' }
  if (health >= 60) return { label: 'At Risk', tone: 'warning' }
  return { label: 'Critical', tone: 'error' }
}

export default function Dashboard() {
  const { student } = useAuth()
  const { academics, loading, error } = useStudentAcademics()
  const { isRtl, language, t } = useLanguage()

  const upcomingExams = exams.filter((e) => e.status === 'Upcoming').slice(0, 3)

  const today = new Date()
  const todayLabel = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][today.getDay()]
  const todaysClasses = scheduleSlots.filter((s) => s.day === todayLabel)

  const displayName = student?.name ?? 'Student'
  const displayProgram = student?.major ?? 'Program'
  const registeredCourses = academics?.courses ?? []
  const recentAnnouncements = [...announcements]
    .sort((a, b) => new Date(b.publishedAt).getTime() - new Date(a.publishedAt).getTime())
    .slice(0, 3)

  if (loading) {
    return (
      <div>
        <PageHeader title="Welcome back" description="Loading your academic data…" />
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
          <div className="lg:col-span-2 space-y-6">
            <Card padded={false}><TableSkeleton rows={3} cols={3} /></Card>
            <Card padded={false}><TableSkeleton rows={3} cols={3} /></Card>
          </div>
          <div className="space-y-6">
            <CardSkeleton /><CardSkeleton /><CardSkeleton />
          </div>
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <div>
        <PageHeader title="Dashboard" description="Could not load your academic data." />
        <EmptyState
          icon={<AlertTriangle className="h-6 w-6" />}
          title="Error loading data"
          description={error}
        />
      </div>
    )
  }

  return (
    <div>
      <PageHeader
        title={`Welcome back, ${firstName(displayName)}`}
        description={`${displayProgram} · ${academics?.semester ?? 'Fall 2026'}`}
        actions={
          <Link to="/registration">
            <span className="inline-flex items-center gap-2 rounded-md bg-coral-500 px-4 py-2.5 text-sm font-semibold text-white hover:bg-coral-600">
              <ClipboardList className="h-4 w-4" />
              {t('Open Registration')}
            </span>
          </Link>
        }
      />

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-2">
          <Card padded={false}>
            <div className="flex items-center justify-between border-b border-border px-5 py-4">
              <h2 className="font-display text-base font-semibold text-text-primary">{t('Registered Courses')}</h2>
              <Link to="/courses" className="flex items-center gap-1 text-xs font-semibold text-teal-700 hover:underline">
                {t('View all')} <ArrowRight className={`h-3 w-3 ${isRtl ? 'rtl-flip' : ''}`} />
              </Link>
            </div>
            {registeredCourses.length === 0 ? (
              <p className="px-5 py-8 text-center text-sm text-text-secondary">{t('No registered courses found in the academic database.')}</p>
            ) : (
              <div className="divide-y divide-border">
                {registeredCourses.map((course) => {
                  const status = courseStatus(course.metrics.course_health)
                  return (
                    <Link
                      key={course.course_id}
                      to={`/courses/${course.course_id}`}
                      className="flex items-center justify-between gap-3 px-5 py-3.5 hover:bg-surface-sunk/60"
                    >
                      <div className="min-w-0">
                        <p className="font-mono text-xs font-semibold text-teal-700">{course.course_id}</p>
                        <p className="text-sm font-medium text-text-primary">{course.course_name}</p>
                        <p className="text-xs text-text-muted">
                          {t('Health')}: {course.metrics.course_health?.toFixed(0) ?? '—'}/100
                        </p>
                      </div>
                      <StatusBadge label={status.label} tone={status.tone} />
                    </Link>
                  )
                })}
              </div>
            )}
          </Card>

          <Card padded={false}>
            <div className="flex items-center justify-between border-b border-border px-5 py-4">
              <h2 className="font-display text-base font-semibold text-text-primary">{t("Today's Classes")}</h2>
              <Link to="/schedule" className="flex items-center gap-1 text-xs font-semibold text-teal-700 hover:underline">
                {t('Full calendar')} <ArrowRight className={`h-3 w-3 ${isRtl ? 'rtl-flip' : ''}`} />
              </Link>
            </div>
            {todaysClasses.length === 0 ? (
              <p className="px-5 py-8 text-center text-sm text-text-secondary">{t('No classes scheduled for today. Enjoy the break.')}</p>
            ) : (
              <div className="divide-y divide-border">
                {todaysClasses.map((s, i) => (
                  <div key={i} className="flex items-center gap-4 px-5 py-3.5">
                    <div className="w-16 shrink-0 font-mono text-sm font-semibold text-ink-900">{s.start}</div>
                    <div className="flex-1">
                      <p className="text-sm font-medium text-text-primary">{s.courseTitle}</p>
                      <p className="flex items-center gap-1 text-xs text-text-muted">
                        <MapPin className="h-3 w-3" /> {s.room}
                      </p>
                    </div>
                    <StatusBadge label={s.type} tone="info" />
                  </div>
                ))}
              </div>
            )}
          </Card>
        </div>

        <div className="space-y-6">
          <Card padded={false}>
            <div className="flex items-center justify-between border-b border-border px-5 py-4">
              <h2 className="font-display text-base font-semibold text-text-primary">{t('Upcoming Exams')}</h2>
              <Link to="/exams" className="flex items-center gap-1 text-xs font-semibold text-teal-700 hover:underline">
                {t('All')} <ArrowRight className={`h-3 w-3 ${isRtl ? 'rtl-flip' : ''}`} />
              </Link>
            </div>
            <div className="divide-y divide-border">
              {upcomingExams.map((e) => (
                <div key={e.id} className="flex items-start gap-3 px-5 py-3.5">
                  <div className="flex h-9 w-9 shrink-0 flex-col items-center justify-center rounded-md bg-coral-50 text-coral-600">
                    <CalendarDays className="h-4 w-4" />
                  </div>
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-text-primary">{e.courseTitle}</p>
                    <p className="flex items-center gap-1 text-xs text-text-muted">
                      <Clock className="h-3 w-3" /> {new Date(e.date).toLocaleDateString(language === 'ar' ? 'ar-EG' : 'en-GB', { month: 'short', day: 'numeric' })} · {e.start}
                    </p>
                  </div>
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
            {recentAnnouncements.length > 0 ? (
              <div className="divide-y divide-border">
                {recentAnnouncements.map((announcement) => (
                  <div key={announcement.id} className="px-5 py-3.5">
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <div className="flex items-center gap-2">
                          {!announcement.read && (
                            <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-coral-500" />
                          )}
                          <p className="text-sm font-medium text-text-primary">{announcement.title}</p>
                        </div>
                        {announcement.courseName && (
                          <p className="mt-0.5 truncate text-xs text-text-secondary">
                            {announcement.courseName}
                          </p>
                        )}
                      </div>
                      <StatusBadge
                        label={announcement.type}
                        tone={
                          announcement.type === 'Cancelled'
                            ? 'error'
                            : announcement.type === 'Location Changed'
                              ? 'warning'
                              : announcement.type === 'Rescheduled'
                                ? 'info'
                                : 'neutral'
                        }
                      />
                    </div>
                    <p className="mt-1 text-xs text-text-muted">
                      {new Date(announcement.publishedAt).toLocaleString(language === 'ar' ? 'ar-EG' : 'en-GB', {
                        month: 'short',
                        day: 'numeric',
                        hour: 'numeric',
                        minute: '2-digit',
                      })}
                    </p>
                  </div>
                ))}
              </div>
            ) : (
              <p className="px-5 py-8 text-center text-sm text-text-secondary">
                {t('No new announcements.')}
              </p>
            )}
          </Card>

          <Card>
            <div className="flex items-center gap-2.5">
              <FileText className="h-4 w-4 text-teal-600" />
              <h2 className="font-display text-base font-semibold text-text-primary">{t('Quick Actions')}</h2>
            </div>
            <div className="mt-3 grid grid-cols-2 gap-2">
              {[
                { label: 'Transcript', to: '/documents' },
                { label: 'Pay Fees', to: '/fees' },
                { label: 'GPA Calculator', to: '/services/gpa-calculator' },
                { label: 'My Calendar', to: '/schedule' },
                { label: 'All Services', to: '/services' },
                { label: 'Clinic Booking', to: '/services/clinic-reservation' },
              ].map((a) => (
                <Link
                  key={a.label}
                  to={a.to}
                  className="rounded-md border border-border-strong px-3 py-2.5 text-center text-xs font-semibold text-text-primary hover:border-teal-500 hover:bg-teal-50 hover:text-teal-700"
                >
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
