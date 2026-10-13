import { useState } from 'react'
import { CalendarCheck2, Clock, Stethoscope, CheckCircle2 } from 'lucide-react'
import Card from './Card'
import Button from './Button'
import { useToast } from './Toast'

const services = ['General Consultation', 'Dental Checkup', 'Vaccination', 'Lab Test', 'Mental Health Counseling']
const dates = ['Mon, Sep 1', 'Tue, Sep 2', 'Wed, Sep 3', 'Thu, Sep 4', 'Fri, Sep 5']
const times = ['09:00 AM', '10:30 AM', '12:00 PM', '01:30 PM', '03:00 PM']

export default function ClinicReservationTool() {
  const [service, setService] = useState(services[0])
  const [date, setDate] = useState(dates[0])
  const [time, setTime] = useState(times[0])
  const [confirmed, setConfirmed] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const { showToast } = useToast()

  const handleBook = async () => {
    setSubmitting(true)
    await new Promise((r) => setTimeout(r, 800))
    setSubmitting(false)
    setConfirmed(true)
    showToast('Clinic appointment reserved.')
  }

  if (confirmed) {
    return (
      <Card className="flex flex-col items-center gap-3 py-10 text-center">
        <div className="flex h-14 w-14 items-center justify-center rounded-full bg-success-100 text-success">
          <CheckCircle2 className="h-7 w-7" />
        </div>
        <p className="font-display text-lg font-semibold text-text-primary">Appointment Confirmed</p>
        <p className="max-w-sm text-sm text-text-secondary">
          Your <strong>{service}</strong> appointment is booked for <strong>{date}</strong> at <strong>{time}</strong>. A confirmation has
          been sent to your student email.
        </p>
        <Button variant="secondary" size="sm" onClick={() => setConfirmed(false)}>
          Book Another Appointment
        </Button>
      </Card>
    )
  }

  return (
    <div className="space-y-4">
      <Card className="flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-md bg-teal-50 text-teal-600">
          <Stethoscope className="h-5 w-5" />
        </div>
        <p className="text-sm text-text-secondary">Book an appointment at the on-campus Student Health Clinic.</p>
      </Card>

      <Card>
        <label className="mb-1.5 block text-sm font-semibold text-text-primary">Service</label>
        <select
          value={service}
          onChange={(e) => setService(e.target.value)}
          className="w-full rounded-md border border-border-strong px-3 py-2.5 text-sm focus-visible:outline-2 focus-visible:outline-teal-600"
        >
          {services.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>

        <label className="mb-1.5 mt-4 flex items-center gap-1.5 text-sm font-semibold text-text-primary">
          <CalendarCheck2 className="h-3.5 w-3.5" /> Select a Date
        </label>
        <div className="flex flex-wrap gap-2">
          {dates.map((d) => (
            <button
              key={d}
              onClick={() => setDate(d)}
              className={`rounded-md border px-3 py-2 text-sm font-medium transition-colors ${
                date === d ? 'border-teal-600 bg-teal-600 text-white' : 'border-border-strong text-text-secondary hover:bg-surface-sunk'
              }`}
            >
              {d}
            </button>
          ))}
        </div>

        <label className="mb-1.5 mt-4 flex items-center gap-1.5 text-sm font-semibold text-text-primary">
          <Clock className="h-3.5 w-3.5" /> Select a Time
        </label>
        <div className="flex flex-wrap gap-2">
          {times.map((t) => (
            <button
              key={t}
              onClick={() => setTime(t)}
              className={`rounded-md border px-3 py-2 text-sm font-mono font-medium transition-colors ${
                time === t ? 'border-teal-600 bg-teal-600 text-white' : 'border-border-strong text-text-secondary hover:bg-surface-sunk'
              }`}
            >
              {t}
            </button>
          ))}
        </div>
      </Card>

      <div className="flex justify-end">
        <Button loading={submitting} onClick={handleBook}>
          Confirm Reservation
        </Button>
      </div>
    </div>
  )
}
