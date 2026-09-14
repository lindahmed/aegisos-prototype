import { useState } from 'react'
import { Pencil, Save, X, Mail, Phone, MapPin, Calendar, Flag } from 'lucide-react'
import { useAuth } from '@student/context/AuthContext'
import PageHeader from '@student/components/layout/PageHeader'
import ProfileCard from '@student/components/ui/ProfileCard'
import Card from '@student/components/ui/Card'
import Button from '@student/components/ui/Button'
import Tabs from '@student/components/ui/Tabs'
import { useToast } from '@student/components/ui/Toast'

const tabs = ['Personal Information', 'Academic Information', 'Contact Information']

function Field({
  label,
  value,
  editable,
  editing,
  onChange,
  icon,
}: {
  label: string
  value: string
  editable?: boolean
  editing?: boolean
  onChange?: (v: string) => void
  icon?: React.ReactNode
}) {
  return (
    <div>
      <label className="mb-1.5 flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-text-muted">
        {icon}
        {label}
      </label>
      {editing && editable ? (
        <input
          value={value}
          onChange={(e) => onChange?.(e.target.value)}
          className="w-full rounded-md border border-border-strong bg-white px-3 py-2 text-sm focus-visible:outline-2 focus-visible:outline-teal-600"
        />
      ) : (
        <p className="rounded-md bg-surface-sunk px-3 py-2 text-sm text-text-primary">{value}</p>
      )}
    </div>
  )
}

export default function Profile() {
  const { student } = useAuth()
  const [activeTab, setActiveTab] = useState(tabs[0])
  const [editing, setEditing] = useState(false)
  const [form, setForm] = useState({
    email: '',
    phone: '',
    address: '',
  })
  const { showToast } = useToast()

  const save = () => {
    setEditing(false)
    showToast('Profile updated successfully.')
  }

  if (!student) {
    return (
      <div>
        <PageHeader title="My Profile" crumbs={[{ label: 'Profile' }]} description="Loading your profile…" />
        <Card className="py-12 text-center text-text-muted">No academic record linked to this session.</Card>
      </div>
    )
  }

  return (
    <div>
      <PageHeader
        title="My Profile"
        crumbs={[{ label: 'Profile' }]}
        description="View and manage your personal, academic, and contact information."
        actions={
          activeTab === 'Contact Information' ? (
            editing ? (
              <div className="flex gap-2">
                <Button variant="secondary" size="sm" icon={<X className="h-3.5 w-3.5" />} onClick={() => setEditing(false)}>
                  Cancel
                </Button>
                <Button size="sm" icon={<Save className="h-3.5 w-3.5" />} onClick={save}>
                  Save Changes
                </Button>
              </div>
            ) : (
              <Button variant="secondary" size="sm" icon={<Pencil className="h-3.5 w-3.5" />} onClick={() => setEditing(true)}>
                Edit
              </Button>
            )
          ) : undefined
        }
      />

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div className="lg:col-span-1">
          <ProfileCard student={student} />
        </div>

        <div className="lg:col-span-2">
          <Card padded={false}>
            <div className="px-2 pt-1">
              <Tabs tabs={tabs} active={activeTab} onChange={setActiveTab} />
            </div>
            <div className="p-5">
              {activeTab === 'Personal Information' && (
                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                  <Field label="Full Name" value={student.name} />
                  <Field label="Registration Number" value={student.student_id} />
                  <Field label="Date of Birth" value="—" icon={<Calendar className="h-3 w-3" />} />
                  <Field label="Nationality" value="—" icon={<Flag className="h-3 w-3" />} />
                </div>
              )}

              {activeTab === 'Academic Information' && (
                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                  <Field label="Program" value={student.major} />
                  <Field label="Faculty" value="—" />
                  <Field label="Level" value={`Year ${student.year}`} />
                  <Field label="Academic Advisor" value="—" />
                  <Field label="Current Semester" value="Fall 2026" />
                  <Field label="Academic Status" value="Active" />
                </div>
              )}

              {activeTab === 'Contact Information' && (
                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                  <Field
                    label="Email Address"
                    value={form.email}
                    editable
                    editing={editing}
                    onChange={(v) => setForm({ ...form, email: v })}
                    icon={<Mail className="h-3 w-3" />}
                  />
                  <Field
                    label="Phone Number"
                    value={form.phone}
                    editable
                    editing={editing}
                    onChange={(v) => setForm({ ...form, phone: v })}
                    icon={<Phone className="h-3 w-3" />}
                  />
                  <div className="sm:col-span-2">
                    <Field
                      label="Home Address"
                      value={form.address}
                      editable
                      editing={editing}
                      onChange={(v) => setForm({ ...form, address: v })}
                      icon={<MapPin className="h-3 w-3" />}
                    />
                  </div>
                </div>
              )}
            </div>
          </Card>
        </div>
      </div>
    </div>
  )
}
