import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import { getPortalStudentAcademics, type PortalStudentAcademics } from '@/lib/portalGrades'
import { useAuth } from '@student/context/AuthContext'

interface StudentAcademicsContextValue {
  academics: PortalStudentAcademics | null
  loading: boolean
  error: string
  refresh: () => Promise<void>
}

const StudentAcademicsContext = createContext<StudentAcademicsContextValue | undefined>(undefined)

export function StudentAcademicsProvider({ children }: { children: ReactNode }) {
  const { academicStudentId } = useAuth()
  const [academics, setAcademics] = useState<PortalStudentAcademics | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  const fetchData = async () => {
    if (!academicStudentId) {
      setLoading(false)
      setError('No academic student ID is available.')
      return
    }
    setLoading(true)
    setError('')
    try {
      const data = await getPortalStudentAcademics(academicStudentId)
      setAcademics(data)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load academic data.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    let active = true
    if (!academicStudentId) {
      setLoading(false)
      return
    }
    setLoading(true)
    getPortalStudentAcademics(academicStudentId)
      .then((data) => {
        if (active) setAcademics(data)
      })
      .catch((err) => {
        if (active) setError(err instanceof Error ? err.message : 'Failed to load academic data.')
      })
      .finally(() => {
        if (active) setLoading(false)
      })
    return () => {
      active = false
    }
  }, [academicStudentId])

  return (
    <StudentAcademicsContext.Provider
      value={{ academics, loading, error, refresh: fetchData }}
    >
      {children}
    </StudentAcademicsContext.Provider>
  )
}

export function useStudentAcademics() {
  const ctx = useContext(StudentAcademicsContext)
  if (!ctx) throw new Error('useStudentAcademics must be used within StudentAcademicsProvider')
  return ctx
}
