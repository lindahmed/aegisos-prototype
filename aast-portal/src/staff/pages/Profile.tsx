import { staff } from '@staff/data/mockData'
import PageHeader from '@staff/components/layout/PageHeader'
import Card from '@staff/components/ui/Card'
import { Link } from 'react-router-dom'
import { Mail, Phone, DoorOpen, UserCog, KeyRound } from 'lucide-react'

export default function Profile() {
  return (
    <div>
      <PageHeader title="My Profile" crumbs={[{ label: 'Profile' }]} description="Your personal, academic, and contact information." />

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div className="lg:col-span-1">
          <div className="overflow-hidden rounded-lg border border-border bg-surface shadow-card">
            <div className="bg-ink-900 px-6 py-8 text-center">
              <div className="mx-auto flex h-20 w-20 items-center justify-center rounded-full bg-teal-500 font-display text-2xl font-bold text-white ring-4 ring-white/10">
                {staff.avatarInitials}
              </div>
              <p className="mt-3 font-display text-lg font-semibold text-white">{staff.fullName}</p>
              <p className="font-mono text-sm text-white/50">{staff.staffId}</p>
            </div>
            <dl className="divide-y divide-border">
              {[
                ['Position', staff.position],
                ['Academic Role', staff.academicRole],
                ['Department', staff.department],
                ['College', staff.college],
              ].map(([label, value]) => (
                <div key={label} className="flex justify-between gap-4 px-5 py-3 text-sm">
                  <dt className="text-text-secondary">{label}</dt>
                  <dd className="text-right font-medium text-text-primary">{value}</dd>
                </div>
              ))}
            </dl>
          </div>

          <Card className="mt-4 flex flex-col gap-2">
            <Link to="/profile/update" className="flex items-center justify-center gap-2 rounded-md border border-border-strong px-3 py-2.5 text-sm font-semibold text-text-primary hover:border-teal-500 hover:bg-teal-50 hover:text-teal-700">
              <UserCog className="h-4 w-4" />
              Update Data
            </Link>
            <Link to="/profile/password" className="flex items-center justify-center gap-2 rounded-md border border-border-strong px-3 py-2.5 text-sm font-semibold text-text-primary hover:border-teal-500 hover:bg-teal-50 hover:text-teal-700">
              <KeyRound className="h-4 w-4" />
              Change Password
            </Link>
          </Card>
        </div>

        <div className="lg:col-span-2">
          <Card>
            <h3 className="mb-3 font-display text-sm font-semibold text-text-primary">Contact Information</h3>
            <dl className="space-y-3 text-sm">
              <div className="flex items-center gap-2.5">
                <Mail className="h-4 w-4 text-text-muted" />
                <span className="text-text-secondary">{staff.email}</span>
              </div>
              <div className="flex items-center gap-2.5">
                <Phone className="h-4 w-4 text-text-muted" />
                <span className="text-text-secondary">{staff.phone}</span>
              </div>
              <div className="flex items-center gap-2.5">
                <DoorOpen className="h-4 w-4 text-text-muted" />
                <span className="text-text-secondary">{staff.office}</span>
              </div>
            </dl>
          </Card>
        </div>
      </div>
    </div>
  )
}
