import { useState } from 'react'
import PageHeader from '@staff/components/layout/PageHeader'
import Card from '@staff/components/ui/Card'
import { useToast } from '@staff/components/ui/Toast'
import { useLanguage } from '@/context/LanguageContext'

function Toggle({ checked, onChange, label, description }: { checked: boolean; onChange: (v: boolean) => void; label: string; description: string }) {
  const { t } = useLanguage()

  return (
    <div className="flex items-center justify-between gap-4 py-3">
      <div>
        <p className="text-sm font-medium text-text-primary">{t(label)}</p>
        <p className="text-xs text-text-muted">{t(description)}</p>
      </div>
      <button
        role="switch"
        aria-checked={checked}
        onClick={() => onChange(!checked)}
        className={`relative h-6 w-11 shrink-0 rounded-full transition-colors ${checked ? 'bg-teal-600' : 'bg-border-strong'}`}
      >
        <span className={`absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-transform ${checked ? 'translate-x-5' : 'translate-x-0.5'}`} />
      </button>
    </div>
  )
}

export default function Settings() {
  const [emailNotifs, setEmailNotifs] = useState(true)
  const [requestAlerts, setRequestAlerts] = useState(true)
  const [weeklyDigest, setWeeklyDigest] = useState(false)
  const { showToast } = useToast()
  const { language, setLanguage, t } = useLanguage()

  const handleToggle = (setter: (v: boolean) => void, label: string) => (v: boolean) => {
    setter(v)
    showToast(`${label} ${v ? 'enabled' : 'disabled'}.`)
  }

  return (
    <div>
      <PageHeader title="Settings" crumbs={[{ label: 'Settings' }]} description="Manage your notification and portal preferences." />

      <div className="mx-auto max-w-xl space-y-4">
        <Card padded={false}>
          <div className="border-b border-border px-5 py-3">
            <h3 className="font-display text-sm font-semibold text-text-primary">{t('Notification Preferences')}</h3>
          </div>
          <div className="divide-y divide-border px-5">
            <Toggle
              checked={emailNotifs}
              onChange={handleToggle(setEmailNotifs, 'Email notifications')}
              label="Email Notifications"
              description="Receive email copies of important portal notifications."
            />
            <Toggle
              checked={requestAlerts}
              onChange={handleToggle(setRequestAlerts, 'Request alerts')}
              label="Student Request Alerts"
              description="Get notified immediately when a student submits a request."
            />
            <Toggle
              checked={weeklyDigest}
              onChange={handleToggle(setWeeklyDigest, 'Weekly digest')}
              label="Weekly Summary Digest"
              description="Receive a weekly summary of attendance and grading activity."
            />
          </div>
        </Card>

        <Card>
          <h3 className="mb-1 font-display text-sm font-semibold text-text-primary">{t('Language')}</h3>
          <p className="mb-3 text-xs text-text-muted">{t('Choose your preferred portal display language.')}</p>
          <select
            value={language}
            className="w-full rounded-md border border-border-strong px-3 py-2.5 text-sm focus-visible:outline-2 focus-visible:outline-teal-600"
            onChange={(event) => {
              setLanguage(event.target.value === 'ar' ? 'ar' : 'en')
              showToast(t('Language preference updated.'))
            }}
          >
            <option value="en">{t('English')}</option>
            <option value="ar">العربية</option>
          </select>
        </Card>
      </div>
    </div>
  )
}
