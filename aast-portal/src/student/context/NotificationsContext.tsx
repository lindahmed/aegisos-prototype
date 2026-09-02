import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import {
  getPortalStudentNotifications,
  setPortalNotificationsRead,
  type PortalNotification,
} from '@/lib/portalGrades'
import { useAuth } from '@student/context/AuthContext'

interface NotificationsContextValue {
  notifications: PortalNotification[]
  loading: boolean
  error: string
  refresh: () => Promise<void>
  toggleRead: (id: string) => Promise<void>
  markAllRead: () => Promise<void>
}

const NotificationsContext = createContext<NotificationsContextValue | undefined>(undefined)
const POLL_INTERVAL_MS = 60_000

export function NotificationsProvider({ children }: { children: ReactNode }) {
  const { academicStudentId } = useAuth()
  const [notifications, setNotifications] = useState<PortalNotification[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  const refresh = useCallback(async () => {
    if (!academicStudentId) {
      setNotifications([])
      setLoading(false)
      return
    }
    try {
      const response = await getPortalStudentNotifications(academicStudentId)
      setNotifications(response.notifications)
      setError('')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load notifications.')
    } finally {
      setLoading(false)
    }
  }, [academicStudentId])

  useEffect(() => {
    setLoading(true)
    void refresh()
    const timer = window.setInterval(() => void refresh(), POLL_INTERVAL_MS)
    return () => window.clearInterval(timer)
  }, [refresh])

  const updateReadState = async (ids: string[], read: boolean) => {
    if (!academicStudentId || ids.length === 0) return
    setNotifications((current) =>
      current.map((notification) =>
        ids.includes(notification.id) ? { ...notification, read } : notification,
      ),
    )
    try {
      const response = await setPortalNotificationsRead(academicStudentId, ids, read)
      setNotifications(response.notifications)
      setError('')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update notifications.')
      await refresh()
    }
  }

  const toggleRead = async (id: string) => {
    const notification = notifications.find((item) => item.id === id)
    if (notification) await updateReadState([id], !notification.read)
  }

  const markAllRead = async () => {
    await updateReadState(
      notifications.filter((notification) => !notification.read).map((notification) => notification.id),
      true,
    )
  }

  return (
    <NotificationsContext.Provider
      value={{ notifications, loading, error, refresh, toggleRead, markAllRead }}
    >
      {children}
    </NotificationsContext.Provider>
  )
}

export function useNotifications() {
  const context = useContext(NotificationsContext)
  if (!context) throw new Error('useNotifications must be used within NotificationsProvider')
  return context
}
