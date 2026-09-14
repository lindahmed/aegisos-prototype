import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { GraduationCap, User, AlertCircle, Briefcase, ArrowLeft, Check } from 'lucide-react'
import { useAuth, type PortalRole } from '@/context/AuthContext'
import Button from '@/components/ui/Button'
import LanguageToggle from '@/components/LanguageToggle'
import { useLanguage } from '@/context/LanguageContext'

const roleOptions: {
  role: PortalRole
  title: string
  description: string
  idLabel: string
  idPlaceholder: string
}[] = [
  {
    role: 'student',
    title: 'Student',
    description: 'Register for courses, track grades, view your schedule, and manage tuition.',
    idLabel: 'Registration Number',
    idPlaceholder: 'STU001',
  },
  {
    role: 'staff',
    title: 'Staff',
    description: 'Manage courses, attendance, grades, exam schedules, and student records.',
    idLabel: 'Employee Number',
    idPlaceholder: '104217',
  },
]

export default function Login() {
  const [selectedRole, setSelectedRole] = useState<PortalRole | null>(null)
  const [id, setId] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const { login } = useAuth()
  const { t } = useLanguage()
  const navigate = useNavigate()

  const activeRole = roleOptions.find((r) => r.role === selectedRole)

  const handleRoleSelect = (role: PortalRole) => {
    setSelectedRole(role)
    setId('')
    setError('')
  }

  const handleBack = () => {
    setSelectedRole(null)
    setId('')
    setError('')
  }

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault()
    if (!selectedRole) return
    setError('')
    setLoading(true)
    const result = await login(selectedRole, id)
    setLoading(false)
    if (result.success) {
      navigate('/')
    } else {
      setError(result.error ?? 'Login failed.')
    }
  }

  return (
    <div className="relative flex min-h-screen">
      <div className="absolute end-5 top-5 z-20"><LanguageToggle /></div>
      <div className="relative hidden w-1/2 overflow-hidden bg-ink-900 lg:block">
        <div
          className="absolute inset-0 opacity-40"
          style={{
            backgroundImage:
              'radial-gradient(circle at 20% 20%, rgba(67,134,190,0.48), transparent 45%), radial-gradient(circle at 80% 70%, rgba(76,120,181,0.34), transparent 50%)',
          }}
        />
        <div className="relative flex h-full flex-col justify-between p-12">
          <div className="flex items-center gap-2.5">
            <div className="flex h-10 w-10 items-center justify-center rounded-md bg-teal-600 text-white">
              <GraduationCap className="h-6 w-6" />
            </div>
            <span className="font-display text-lg font-bold text-white">{t('AAST Portal')}</span>
          </div>
          <div>
            <h1 className="max-w-lg font-display text-4xl font-bold leading-tight text-white">
              {t('One portal, for students & staff.')}
            </h1>
            <p className="mt-4 max-w-md text-white/60">
              {t('Sign in with your university account to access courses, grades, schedules, and university services — whether you study here or teach here.')}
            </p>
          </div>
          <p className="text-xs text-white/30">
            {t('© 2026 Arab Academy for Science, Technology & Maritime Transport. All rights reserved.')}
          </p>
        </div>
      </div>

      <div className="flex w-full flex-col justify-center px-6 py-12 lg:w-1/2 lg:px-16">
        <div className="mx-auto w-full max-w-sm">
          <div className="mb-8 flex items-center gap-2.5 lg:hidden">
            <div className="flex h-9 w-9 items-center justify-center rounded-md bg-teal-600 text-white">
              <GraduationCap className="h-5 w-5" />
            </div>
            <span className="font-display text-lg font-bold text-ink-900">{t('AAST Portal')}</span>
          </div>

          {!activeRole ? (
            <>
              <h2 className="font-display text-2xl font-bold text-text-primary">{t('Sign in to your portal')}</h2>
              <p className="mt-1.5 text-sm text-text-secondary">{t('First, tell us who you are.')}</p>

              <div className="mt-6 space-y-3">
                {roleOptions.map((option) => (
                  <button
                    key={option.role}
                    type="button"
                    onClick={() => handleRoleSelect(option.role)}
                    className="group flex w-full items-start gap-4 rounded-lg border border-border-strong bg-white p-4 text-left transition-colors hover:border-teal-600 hover:bg-teal-50/50 focus-visible:outline-2 focus-visible:outline-teal-600"
                  >
                    <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-teal-600 text-white">
                      {option.role === 'student' ? (
                        <GraduationCap className="h-5 w-5" />
                      ) : (
                        <Briefcase className="h-5 w-5" />
                      )}
                    </div>
                    <div>
                      <p className="font-display text-base font-bold text-text-primary">
                        {t(option.role === 'student' ? "I'm a student" : "I'm a staff member")}
                      </p>
                      <p className="mt-0.5 text-sm text-text-secondary">{t(option.description)}</p>
                    </div>
                    <Check className="ml-auto mt-1 h-4 w-4 shrink-0 text-teal-600 opacity-0 transition-opacity group-hover:opacity-100" />
                  </button>
                ))}
              </div>
            </>
          ) : (
            <>
              <button
                type="button"
                onClick={handleBack}
                className="mb-4 inline-flex items-center gap-1.5 text-sm font-semibold text-text-secondary hover:text-teal-700"
              >
                <ArrowLeft className="h-4 w-4 rtl-flip" />
                {t('Back')}
              </button>

              <h2 className="font-display text-2xl font-bold text-text-primary">{t(`Sign in as ${activeRole.title.toLowerCase()}`)}</h2>
              <p className="mt-1.5 text-sm text-text-secondary">
                {t(`Enter your ${activeRole.idLabel} to continue.`)}
              </p>

              <form onSubmit={handleSubmit} className="mt-6 space-y-4">
                <div>
                  <label htmlFor="portalId" className="mb-1.5 block text-sm font-semibold text-text-primary">
                    {t(activeRole.idLabel)}
                  </label>
                  <div className="relative">
                    <User className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted" />
                    <input
                      id="portalId"
                      type="text"
                      required
                      autoFocus
                      value={id}
                      onChange={(e) => setId(e.target.value)}
                      placeholder={activeRole.idPlaceholder}
                      className="w-full rounded-md border border-border-strong bg-white py-2.5 pl-9 pr-3 text-sm placeholder:text-text-muted focus-visible:outline-2 focus-visible:outline-teal-600"
                    />
                  </div>
                </div>

                {error && (
                  <div className="flex items-start gap-2 rounded-md bg-error-100 px-3 py-2.5 text-sm text-error">
                    <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
                    {error}
                  </div>
                )}

                <Button type="submit" loading={loading} className="w-full">
                  Sign In
                </Button>
              </form>

              <p className="mt-6 text-center text-sm text-text-muted">
                {t('Trouble signing in?')}{' '}
                <button type="button" className="font-semibold text-teal-700 hover:underline">
                  {t('Contact IT support')}
                </button>
              </p>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
