import { useState, type FormEvent } from 'react'
import { KeyRound, AlertCircle } from 'lucide-react'
import PageHeader from '@staff/components/layout/PageHeader'
import Card from '@staff/components/ui/Card'
import Button from '@staff/components/ui/Button'
import { useToast } from '@staff/components/ui/Toast'

export default function ChangePassword() {
  const [current, setCurrent] = useState('')
  const [next, setNext] = useState('')
  const [confirm, setConfirm] = useState('')
  const [error, setError] = useState('')
  const [saving, setSaving] = useState(false)
  const { showToast } = useToast()

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault()
    setError('')
    if (next.length < 8) {
      setError('New password must be at least 8 characters.')
      return
    }
    if (next !== confirm) {
      setError('New password and confirmation do not match.')
      return
    }
    setSaving(true)
    await new Promise((r) => setTimeout(r, 700))
    setSaving(false)
    setCurrent('')
    setNext('')
    setConfirm('')
    showToast('Password changed successfully.')
  }

  return (
    <div>
      <PageHeader title="Change Password" crumbs={[{ label: 'Profile', to: '/profile' }, { label: 'Change Password' }]} description="Update the password for your staff portal account." />

      <div className="mx-auto max-w-xl">
        <Card>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="mb-1.5 block text-sm font-semibold text-text-primary">Current Password</label>
              <input
                required
                type="password"
                value={current}
                onChange={(e) => setCurrent(e.target.value)}
                className="w-full rounded-md border border-border-strong px-3 py-2.5 text-sm focus-visible:outline-2 focus-visible:outline-teal-600"
              />
            </div>
            <div>
              <label className="mb-1.5 block text-sm font-semibold text-text-primary">New Password</label>
              <input
                required
                type="password"
                value={next}
                onChange={(e) => setNext(e.target.value)}
                className="w-full rounded-md border border-border-strong px-3 py-2.5 text-sm focus-visible:outline-2 focus-visible:outline-teal-600"
              />
            </div>
            <div>
              <label className="mb-1.5 block text-sm font-semibold text-text-primary">Confirm New Password</label>
              <input
                required
                type="password"
                value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
                className="w-full rounded-md border border-border-strong px-3 py-2.5 text-sm focus-visible:outline-2 focus-visible:outline-teal-600"
              />
            </div>
            {error && (
              <div className="flex items-start gap-2 rounded-md bg-error-100 px-3 py-2.5 text-sm text-error">
                <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
                {error}
              </div>
            )}
            <Button type="submit" loading={saving} icon={<KeyRound className="h-4 w-4" />}>
              Change Password
            </Button>
          </form>
        </Card>
      </div>
    </div>
  )
}
