import { useEffect, useMemo, useState, type FormEvent } from 'react'
import {
  BrainCircuit,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  Clock3,
  Plus,
  Trash2,
} from 'lucide-react'
import { useAuth } from '@student/context/AuthContext'
import { useStudentAcademics } from '@student/context/StudentAcademicsContext'
import { useToast } from '@student/components/ui/Toast'
import PageHeader from '@student/components/layout/PageHeader'
import Card from '@student/components/ui/Card'
import Button from '@student/components/ui/Button'
import Modal from '@student/components/ui/Modal'
import { CardSkeleton } from '@student/components/ui/LoadingState'
import {
  academicCalendarEvents,
  addUrgentAiStudySessions,
  loadCustomCalendarEvents,
  newStudentCalendarEvent,
  saveCustomCalendarEvents,
  type CalendarEvent,
} from '@student/lib/calendar'

const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const monthTitle = new Intl.DateTimeFormat('en', { month: 'long', year: 'numeric' })
const fullDate = new Intl.DateTimeFormat('en', { weekday: 'long', month: 'long', day: 'numeric' })
const eventTime = new Intl.DateTimeFormat('en', { hour: 'numeric', minute: '2-digit' })

const eventStyles: Record<CalendarEvent['type'], string> = {
  exam: 'border-coral-500 bg-coral-50 text-coral-600',
  assignment: 'border-warning bg-warning-100 text-ink-800',
  study_session: 'border-teal-500 bg-teal-50 text-teal-700',
  personal: 'border-ink-600 bg-ink-900/5 text-ink-800',
}

function dateKey(value: Date | string) {
  const date = value instanceof Date ? value : new Date(value)
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

function monthGrid(month: Date) {
  const first = new Date(month.getFullYear(), month.getMonth(), 1)
  first.setDate(first.getDate() - first.getDay())
  return Array.from({ length: 42 }, (_, index) => {
    const day = new Date(first)
    day.setDate(first.getDate() + index)
    return day
  })
}

export default function Schedule() {
  const { academics, loading } = useStudentAcademics()
  const { academicStudentId } = useAuth()
  const { showToast } = useToast()
  const [month, setMonth] = useState(() => new Date())
  const [selectedDate, setSelectedDate] = useState(() => new Date())
  const [customEvents, setCustomEvents] = useState<CalendarEvent[]>([])
  const [storageReady, setStorageReady] = useState(false)
  const [addOpen, setAddOpen] = useState(false)
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [eventDate, setEventDate] = useState(() => dateKey(new Date()))
  const [eventStart, setEventStart] = useState('18:00')
  const [duration, setDuration] = useState('60')
  const [eventType, setEventType] = useState<'personal' | 'study_session'>('study_session')

  useEffect(() => {
    if (!academicStudentId) return
    setCustomEvents(loadCustomCalendarEvents(academicStudentId))
    setStorageReady(true)
  }, [academicStudentId])

  useEffect(() => {
    if (!academics || !academicStudentId || !storageReady) return
    setCustomEvents((current) => {
      const result = addUrgentAiStudySessions(academics, current)
      if (result.added.length === 0) return current
      saveCustomCalendarEvents(academicStudentId, result.events)
      return result.events
    })
  }, [academics, academicStudentId, storageReady])

  const academicEvents = useMemo(() => academicCalendarEvents(academics), [academics])
  const events = useMemo(
    () => [...academicEvents, ...customEvents].sort((a, b) => a.startAt.localeCompare(b.startAt)),
    [academicEvents, customEvents],
  )
  const eventsByDate = useMemo(() => {
    const grouped = new Map<string, CalendarEvent[]>()
    for (const event of events) {
      const key = dateKey(event.startAt)
      grouped.set(key, [...(grouped.get(key) ?? []), event])
    }
    return grouped
  }, [events])
  const selectedEvents = eventsByDate.get(dateKey(selectedDate)) ?? []
  const days = monthGrid(month)

  const changeMonth = (difference: number) => {
    setMonth((current) => new Date(current.getFullYear(), current.getMonth() + difference, 1))
  }

  const selectToday = () => {
    const today = new Date()
    setMonth(new Date(today.getFullYear(), today.getMonth(), 1))
    setSelectedDate(today)
  }

  const openAddEvent = (date = selectedDate) => {
    setEventDate(dateKey(date))
    setTitle('')
    setDescription('')
    setEventStart('18:00')
    setDuration('60')
    setEventType('study_session')
    setAddOpen(true)
  }

  const saveEvent = (event: FormEvent) => {
    event.preventDefault()
    if (!academicStudentId || !title.trim()) return
    const start = new Date(`${eventDate}T${eventStart}:00`)
    const minutes = Number(duration)
    if (Number.isNaN(start.getTime()) || !Number.isFinite(minutes) || minutes < 15) {
      showToast('Choose a valid date, time, and duration.', 'error')
      return
    }
    const next = [
      ...customEvents,
      newStudentCalendarEvent({ title, description, start, durationMinutes: minutes, type: eventType }),
    ]
    setCustomEvents(next)
    saveCustomCalendarEvents(academicStudentId, next)
    setSelectedDate(start)
    setMonth(new Date(start.getFullYear(), start.getMonth(), 1))
    setAddOpen(false)
    showToast('Calendar event added.')
  }

  const removeEvent = (id: string) => {
    if (!academicStudentId) return
    const next = customEvents.filter((event) => event.id !== id)
    setCustomEvents(next)
    saveCustomCalendarEvents(academicStudentId, next)
    showToast('Calendar event removed.', 'info')
  }

  const runAiPlanner = () => {
    if (!academics || !academicStudentId) return
    const result = addUrgentAiStudySessions(academics, customEvents)
    setCustomEvents(result.events)
    saveCustomCalendarEvents(academicStudentId, result.events)
    showToast(
      result.added.length > 0
        ? `AI scheduled ${result.added.length} urgent study session${result.added.length === 1 ? '' : 's'}.`
        : 'No new urgent study sessions are needed right now.',
      result.added.length > 0 ? 'success' : 'info',
    )
  }

  return (
    <div>
      <PageHeader
        title="My Calendar"
        crumbs={[{ label: 'Calendar' }]}
        description="Exams and deadlines are built in. Add personal events, or let AI reserve urgent study time when your progress needs attention."
        actions={
          <>
            <Button variant="secondary" size="sm" icon={<BrainCircuit className="h-4 w-4" />} onClick={runAiPlanner}>
              Plan with AI
            </Button>
            <Button size="sm" icon={<Plus className="h-4 w-4" />} onClick={() => openAddEvent()}>
              Add event
            </Button>
          </>
        }
      />

      {loading ? (
        <div className="space-y-4"><CardSkeleton /><CardSkeleton /></div>
      ) : (
        <>
          <p className="mb-4 rounded-md border border-teal-100 bg-teal-50 px-4 py-3 text-xs text-teal-700">
            Academic records currently provide week numbers. Exams are placed on Monday morning and coursework deadlines on Sunday evening of their recorded academic week.
          </p>
          <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_320px]">
          <Card padded={false}>
            <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3 sm:px-5">
              <div className="flex items-center gap-1">
                <button aria-label="Previous month" onClick={() => changeMonth(-1)} className="rounded-md p-2 text-text-secondary hover:bg-surface-sunk">
                  <ChevronLeft className="h-4 w-4" />
                </button>
                <button aria-label="Next month" onClick={() => changeMonth(1)} className="rounded-md p-2 text-text-secondary hover:bg-surface-sunk">
                  <ChevronRight className="h-4 w-4" />
                </button>
                <Button variant="ghost" size="sm" onClick={selectToday}>Today</Button>
              </div>
              <h2 className="font-display text-lg font-semibold text-text-primary">{monthTitle.format(month)}</h2>
              <div className="hidden text-xs text-text-muted sm:block">{academics?.semester} · Week {academics?.current_week}</div>
            </div>

            <div className="grid grid-cols-7 border-b border-border bg-surface-raised">
              {weekdays.map((day) => <div key={day} className="px-1 py-2 text-center text-xs font-semibold text-text-muted">{day}</div>)}
            </div>
            <div className="grid grid-cols-7">
              {days.map((day) => {
                const key = dateKey(day)
                const dayEvents = eventsByDate.get(key) ?? []
                const outside = day.getMonth() !== month.getMonth()
                const selected = key === dateKey(selectedDate)
                const today = key === dateKey(new Date())
                return (
                  <button
                    key={key}
                    onClick={() => setSelectedDate(day)}
                    onDoubleClick={() => openAddEvent(day)}
                    className={`min-h-24 border-b border-r border-border p-1.5 text-left align-top transition-colors hover:bg-surface-sunk sm:min-h-28 sm:p-2 ${outside ? 'bg-surface-raised/60 text-text-muted' : 'bg-white'} ${selected ? 'ring-2 ring-inset ring-teal-500' : ''}`}
                  >
                    <span className={`inline-flex h-6 w-6 items-center justify-center rounded-full text-xs font-semibold ${today ? 'bg-teal-600 text-white' : ''}`}>
                      {day.getDate()}
                    </span>
                    <div className="mt-1 space-y-1">
                      {dayEvents.slice(0, 3).map((event) => (
                        <div key={event.id} className={`truncate rounded border-l-2 px-1.5 py-0.5 text-[10px] font-semibold sm:text-xs ${eventStyles[event.type]}`}>
                          {event.title}
                        </div>
                      ))}
                      {dayEvents.length > 3 && <p className="pl-1 text-[10px] text-text-muted">+{dayEvents.length - 3} more</p>}
                    </div>
                  </button>
                )
              })}
            </div>
            <div className="flex flex-wrap gap-4 border-t border-border px-5 py-3 text-xs text-text-secondary">
              {[
                ['bg-coral-500', 'Exam'], ['bg-warning', 'Deadline'], ['bg-teal-500', 'Study session'], ['bg-ink-600', 'Personal'],
              ].map(([color, label]) => <span key={label} className="flex items-center gap-1.5"><span className={`h-2.5 w-2.5 rounded-full ${color}`} />{label}</span>)}
            </div>
          </Card>

          <Card>
            <div className="mb-4 flex items-start justify-between gap-3">
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-teal-700">Selected day</p>
                <h2 className="mt-1 font-display text-base font-semibold text-text-primary">{fullDate.format(selectedDate)}</h2>
              </div>
              <button aria-label="Add event on selected day" onClick={() => openAddEvent()} className="rounded-md p-2 text-teal-700 hover:bg-teal-50">
                <Plus className="h-4 w-4" />
              </button>
            </div>
            {selectedEvents.length === 0 ? (
              <div className="rounded-md bg-surface-sunk px-4 py-6 text-center">
                <CalendarDays className="mx-auto h-5 w-5 text-text-muted" />
                <p className="mt-2 text-sm text-text-secondary">No events on this day.</p>
              </div>
            ) : (
              <div className="space-y-3">
                {selectedEvents.map((event) => (
                  <article key={event.id} className={`rounded-md border-l-4 p-3 ${eventStyles[event.type]}`}>
                    <div className="flex items-start justify-between gap-2">
                      <div>
                        <p className="text-sm font-semibold">{event.title}</p>
                        <p className="mt-1 flex items-center gap-1 text-xs opacity-75"><Clock3 className="h-3 w-3" />{eventTime.format(new Date(event.startAt))}–{eventTime.format(new Date(event.endAt))}</p>
                      </div>
                      {event.source !== 'academic' && (
                        <button aria-label={`Delete ${event.title}`} onClick={() => removeEvent(event.id)} className="rounded p-1 opacity-60 hover:bg-white/60 hover:opacity-100">
                          <Trash2 className="h-3.5 w-3.5" />
                        </button>
                      )}
                    </div>
                    {event.description && <p className="mt-2 text-xs leading-relaxed opacity-80">{event.description}</p>}
                    <p className="mt-2 text-[10px] font-bold uppercase tracking-wide opacity-60">{event.source === 'ai' ? 'AI scheduled · urgent' : event.source === 'academic' ? 'Academic calendar' : 'My event'}</p>
                  </article>
                ))}
              </div>
            )}
          </Card>
          </div>
        </>
      )}

      <Modal
        open={addOpen}
        onClose={() => setAddOpen(false)}
        title="Add calendar event"
        footer={
          <>
            <Button variant="ghost" onClick={() => setAddOpen(false)}>Cancel</Button>
            <Button type="submit" form="calendar-event-form">Add to calendar</Button>
          </>
        }
      >
        <form id="calendar-event-form" onSubmit={saveEvent} className="space-y-4">
          <label className="block text-sm font-semibold text-text-primary">
            Event title
            <input required maxLength={160} value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Study algorithms, club meeting…" className="mt-1.5 w-full rounded-md border border-border-strong px-3 py-2.5 font-normal outline-none focus:border-teal-500 focus:ring-2 focus:ring-teal-100" />
          </label>
          <label className="block text-sm font-semibold text-text-primary">
            Notes <span className="font-normal text-text-muted">(optional)</span>
            <textarea maxLength={1000} value={description} onChange={(event) => setDescription(event.target.value)} rows={3} className="mt-1.5 w-full resize-none rounded-md border border-border-strong px-3 py-2.5 font-normal outline-none focus:border-teal-500 focus:ring-2 focus:ring-teal-100" />
          </label>
          <div className="grid gap-4 sm:grid-cols-2">
            <label className="block text-sm font-semibold text-text-primary">Date<input required type="date" value={eventDate} onChange={(event) => setEventDate(event.target.value)} className="mt-1.5 w-full rounded-md border border-border-strong px-3 py-2.5 font-normal" /></label>
            <label className="block text-sm font-semibold text-text-primary">Start time<input required type="time" value={eventStart} onChange={(event) => setEventStart(event.target.value)} className="mt-1.5 w-full rounded-md border border-border-strong px-3 py-2.5 font-normal" /></label>
            <label className="block text-sm font-semibold text-text-primary">Duration<select value={duration} onChange={(event) => setDuration(event.target.value)} className="mt-1.5 w-full rounded-md border border-border-strong px-3 py-2.5 font-normal"><option value="30">30 minutes</option><option value="60">1 hour</option><option value="90">1.5 hours</option><option value="120">2 hours</option></select></label>
            <label className="block text-sm font-semibold text-text-primary">Type<select value={eventType} onChange={(event) => setEventType(event.target.value as 'personal' | 'study_session')} className="mt-1.5 w-full rounded-md border border-border-strong px-3 py-2.5 font-normal"><option value="study_session">Study session</option><option value="personal">Personal event</option></select></label>
          </div>
        </form>
      </Modal>
    </div>
  )
}
