import type { ScheduleSlot } from '@student/types'

const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu']
const hours = Array.from({ length: 9 }, (_, i) => 9 + i) // 9 -> 17

const typeStyles: Record<ScheduleSlot['type'], string> = {
  Lecture: 'bg-teal-50 border-teal-500 text-teal-700',
  Lab: 'bg-coral-50 border-coral-500 text-coral-600',
  Tutorial: 'bg-ink-900/5 border-ink-700 text-ink-800',
}

function toMinutes(time: string) {
  const [h, m] = time.split(':').map(Number)
  return h * 60 + m
}

export default function ScheduleGrid({ slots }: { slots: ScheduleSlot[] }) {
  const dayStart = hours[0] * 60
  const rowHeight = 56

  return (
    <div className="overflow-x-auto rounded-lg border border-border bg-surface shadow-card">
      <div className="min-w-[760px]">
        <div className="grid grid-cols-[64px_repeat(5,1fr)] border-b border-border bg-surface-raised">
          <div className="py-3" />
          {days.map((d) => (
            <div key={d} className="py-3 text-center text-sm font-semibold text-text-primary">
              {d}
            </div>
          ))}
        </div>
        <div className="relative grid grid-cols-[64px_repeat(5,1fr)]">
          <div>
            {hours.map((h) => (
              <div key={h} style={{ height: rowHeight }} className="border-b border-border px-2 pt-1 text-right text-xs text-text-muted">
                {h}:00
              </div>
            ))}
          </div>
          {days.map((day) => (
            <div key={day} className="relative border-l border-border">
              {hours.map((h) => (
                <div key={h} style={{ height: rowHeight }} className="border-b border-border" />
              ))}
              {slots
                .filter((s) => s.day === day)
                .map((s, i) => {
                  const top = ((toMinutes(s.start) - dayStart) / 60) * rowHeight
                  const height = ((toMinutes(s.end) - toMinutes(s.start)) / 60) * rowHeight
                  return (
                    <div
                      key={i}
                      style={{ top, height }}
                      className={`absolute left-1 right-1 rounded-md border-l-[3px] px-2 py-1 text-xs shadow-sm ${typeStyles[s.type]}`}
                    >
                      <p className="font-semibold leading-tight">{s.courseCode}</p>
                      <p className="truncate leading-tight opacity-80">{s.room}</p>
                    </div>
                  )
                })}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
