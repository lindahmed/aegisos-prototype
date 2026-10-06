import { useState, type FormEvent } from 'react'
import { Save } from 'lucide-react'
import { staff } from '@staff/data/mockData'
import PageHeader from '@staff/components/layout/PageHeader'
import Card from '@staff/components/ui/Card'
import Button from '@staff/components/ui/Button'
import { useToast } from '@staff/components/ui/Toast'

export default function UpdateData() {
  const [form, setForm] = useState({ email: staff.email, phone: staff.phone, office: staff.office })
  const [saving, setSaving] = useState(false)
  const { showToast } = useToast()

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault()
    setSaving(true)
    await new Promise((r) => setTimeout(r, 700))
    setSaving(false)
    showToast('Your information has been updated.')
  }

  return (
    <div>
      <PageHeader title="Update Data" crumbs={[{ label: 'Profile', to: '/profile' }, { label: 'Update Data' }]} description="Update your contact information." />

      <div className="mx-auto max-w-xl">
        <Card>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="mb-1.5 block text-sm font-semibold text-text-primary">Email Address</label>
              <input
                type="email"
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
                className="w-full rounded-md border border-border-strong px-3 py-2.5 text-sm focus-visible:outline-2 focus-visible:outline-teal-600"
              />
            </div>
            <div>
              <label className="mb-1.5 block text-sm font-semibold text-text-primary">Phone Number</label>
              <input
                type="text"
                value={form.phone}
                onChange={(e) => setForm({ ...form, phone: e.target.value })}
                className="w-full rounded-md border border-border-strong px-3 py-2.5 text-sm focus-visible:outline-2 focus-visible:outline-teal-600"
              />
            </div>
            <div>
              <label className="mb-1.5 block text-sm font-semibold text-text-primary">Office Location</label>
              <input
                type="text"
                value={form.office}
                onChange={(e) => setForm({ ...form, office: e.target.value })}
                className="w-full rounded-md border border-border-strong px-3 py-2.5 text-sm focus-visible:outline-2 focus-visible:outline-teal-600"
              />
            </div>
            <Button type="submit" loading={saving} icon={<Save className="h-4 w-4" />}>
              Save Changes
            </Button>
          </form>
        </Card>
      </div>
    </div>
  )
}
