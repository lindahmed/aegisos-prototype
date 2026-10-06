import { useState, type FormEvent } from 'react'
import { LifeBuoy, Send, Info } from 'lucide-react'
import PageHeader from '@staff/components/layout/PageHeader'
import Card from '@staff/components/ui/Card'
import Button from '@staff/components/ui/Button'
import { useToast } from '@staff/components/ui/Toast'

export default function Support() {
  const [submitting, setSubmitting] = useState(false)
  const [submitted, setSubmitted] = useState(false)
  const { showToast } = useToast()

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault()
    setSubmitting(true)
    await new Promise((r) => setTimeout(r, 800))
    setSubmitting(false)
    setSubmitted(true)
    showToast('Your inquiry has been submitted.')
  }

  return (
    <div>
      <PageHeader title="Support and Inquiries" crumbs={[{ label: 'Support' }]} description="Reach out to IT, HR, or academic affairs with a question or issue." />

      <div className="mx-auto max-w-2xl">
        {submitted ? (
          <Card className="flex flex-col items-center gap-3 py-10 text-center">
            <div className="flex h-14 w-14 items-center justify-center rounded-full bg-success-100 text-success">
              <LifeBuoy className="h-7 w-7" />
            </div>
            <p className="font-display text-lg font-semibold text-text-primary">Inquiry Submitted</p>
            <p className="max-w-sm text-sm text-text-secondary">
              Support typically responds within one business day. You can track this from your Requests page.
            </p>
            <Button variant="secondary" size="sm" onClick={() => setSubmitted(false)}>
              Submit Another Inquiry
            </Button>
          </Card>
        ) : (
          <Card>
            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label className="mb-1.5 block text-sm font-semibold text-text-primary">Department</label>
                <select required defaultValue="" className="w-full rounded-md border border-border-strong px-3 py-2.5 text-sm focus-visible:outline-2 focus-visible:outline-teal-600">
                  <option value="" disabled>
                    Select a department
                  </option>
                  <option>IT Support</option>
                  <option>Human Resources</option>
                  <option>Academic Affairs</option>
                  <option>Facilities</option>
                </select>
              </div>
              <div>
                <label className="mb-1.5 block text-sm font-semibold text-text-primary">Subject</label>
                <input
                  required
                  type="text"
                  placeholder="Short summary of your inquiry"
                  className="w-full rounded-md border border-border-strong px-3 py-2.5 text-sm placeholder:text-text-muted focus-visible:outline-2 focus-visible:outline-teal-600"
                />
              </div>
              <div>
                <label className="mb-1.5 block text-sm font-semibold text-text-primary">Message</label>
                <textarea
                  required
                  rows={5}
                  placeholder="Describe your question or issue…"
                  className="w-full rounded-md border border-border-strong px-3 py-2.5 text-sm placeholder:text-text-muted focus-visible:outline-2 focus-visible:outline-teal-600"
                />
              </div>
              <div className="flex items-start gap-2 rounded-md bg-teal-50 px-3 py-2.5 text-xs text-teal-700">
                <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                This is a prototype form. Submissions are simulated and not sent to any real system.
              </div>
              <Button type="submit" loading={submitting} icon={<Send className="h-4 w-4" />}>
                Submit Inquiry
              </Button>
            </form>
          </Card>
        )}
      </div>
    </div>
  )
}
