import { useState, type FormEvent } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { ArrowLeft, CheckCircle2, Send, Info, LayoutGrid } from 'lucide-react'
import { staffServices } from '@staff/data/staffServicesData'
import PageHeader from '@staff/components/layout/PageHeader'
import Card from '@staff/components/ui/Card'
import Button from '@staff/components/ui/Button'
import EmptyState from '@staff/components/ui/EmptyState'
import { useToast } from '@staff/components/ui/Toast'

function ViewerPanel({ records }: { records: { label: string; value: string }[] }) {
  return (
    <Card padded={false}>
      <dl className="divide-y divide-border">
        {records.map((r) => (
          <div key={r.label} className="flex flex-col gap-1 px-5 py-3.5 sm:flex-row sm:items-center sm:justify-between">
            <dt className="text-sm font-medium text-text-secondary">{r.label}</dt>
            <dd className="font-mono text-sm font-semibold text-text-primary sm:text-right">{r.value}</dd>
          </div>
        ))}
      </dl>
    </Card>
  )
}

function FormPanel({
  fields,
  onSubmitted,
}: {
  fields: { label: string; type: string; options?: string[]; placeholder?: string }[]
  onSubmitted: () => void
}) {
  const [submitting, setSubmitting] = useState(false)
  const [values, setValues] = useState<Record<string, string>>({})

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault()
    setSubmitting(true)
    await new Promise((r) => setTimeout(r, 800))
    setSubmitting(false)
    onSubmitted()
  }

  return (
    <Card>
      <form onSubmit={handleSubmit} className="space-y-4">
        {fields.map((f) => (
          <div key={f.label}>
            <label className="mb-1.5 block text-sm font-semibold text-text-primary">{f.label}</label>
            {f.type === 'textarea' ? (
              <textarea
                required
                rows={4}
                placeholder={f.placeholder}
                value={values[f.label] ?? ''}
                onChange={(e) => setValues({ ...values, [f.label]: e.target.value })}
                className="w-full rounded-md border border-border-strong px-3 py-2.5 text-sm placeholder:text-text-muted focus-visible:outline-2 focus-visible:outline-teal-600"
              />
            ) : f.type === 'select' ? (
              <select
                required
                value={values[f.label] ?? ''}
                onChange={(e) => setValues({ ...values, [f.label]: e.target.value })}
                className="w-full rounded-md border border-border-strong px-3 py-2.5 text-sm focus-visible:outline-2 focus-visible:outline-teal-600"
              >
                <option value="" disabled>
                  Select an option
                </option>
                {f.options?.map((o) => (
                  <option key={o} value={o}>
                    {o}
                  </option>
                ))}
              </select>
            ) : (
              <input
                required
                type={f.type === 'date' ? 'date' : 'text'}
                placeholder={f.placeholder}
                value={values[f.label] ?? ''}
                onChange={(e) => setValues({ ...values, [f.label]: e.target.value })}
                className="w-full rounded-md border border-border-strong px-3 py-2.5 text-sm placeholder:text-text-muted focus-visible:outline-2 focus-visible:outline-teal-600"
              />
            )}
          </div>
        ))}
        <div className="flex items-start gap-2 rounded-md bg-teal-50 px-3 py-2.5 text-xs text-teal-700">
          <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" />
          This is a prototype form. Submissions are simulated and not sent to any real system.
        </div>
        <Button type="submit" loading={submitting} icon={<Send className="h-4 w-4" />}>
          Submit Request
        </Button>
      </form>
    </Card>
  )
}

export default function ServiceDetail() {
  const { slug } = useParams()
  const navigate = useNavigate()
  const { showToast } = useToast()
  const [submitted, setSubmitted] = useState(false)
  const service = staffServices.find((s) => s.slug === slug)

  if (!service) {
    return (
      <EmptyState
        icon={<LayoutGrid className="h-5 w-5" />}
        title="Service not found"
        action={
          <Link to="/services" className="text-sm font-semibold text-teal-700 hover:underline">
            Back to Services
          </Link>
        }
      />
    )
  }

  const Icon = service.icon

  const handleSubmitted = () => {
    setSubmitted(true)
    showToast('Your request has been submitted.')
  }

  return (
    <div>
      <PageHeader
        title={service.name}
        crumbs={[{ label: 'Services', to: '/services' }, { label: service.name }]}
        description={service.description}
        actions={
          <div className="flex h-11 w-11 items-center justify-center rounded-md bg-teal-50 text-teal-600">
            <Icon className="h-5 w-5" />
          </div>
        }
      />

      <button onClick={() => navigate('/services')} className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-text-secondary hover:text-teal-700">
        <ArrowLeft className="h-3.5 w-3.5" />
        Back to Services
      </button>

      <div className="mx-auto max-w-2xl">
        {service.kind === 'viewer' && service.records && <ViewerPanel records={service.records} />}

        {service.kind === 'form' &&
          service.fields &&
          (submitted ? (
            <Card className="flex flex-col items-center gap-3 py-10 text-center">
              <div className="flex h-14 w-14 items-center justify-center rounded-full bg-success-100 text-success">
                <CheckCircle2 className="h-7 w-7" />
              </div>
              <p className="font-display text-lg font-semibold text-text-primary">Request Submitted</p>
              <p className="max-w-sm text-sm text-text-secondary">
                Your {service.name.toLowerCase()} request has been received. You can track its status from Requests.
              </p>
              <Button variant="secondary" size="sm" onClick={() => setSubmitted(false)}>
                Submit Another Request
              </Button>
            </Card>
          ) : (
            <FormPanel fields={service.fields} onSubmitted={handleSubmitted} />
          ))}
      </div>
    </div>
  )
}
