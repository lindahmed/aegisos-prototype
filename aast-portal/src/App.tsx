import { Routes, Route } from 'react-router-dom'
import ProtectedRoute from '@/router/ProtectedRoute'
import Login from '@/pages/Login'
import { useAuth } from '@/context/AuthContext'
import StudentRoutes from '@student/StudentRoutes'
import StaffRoutes from '@staff/StaffRoutes'

export default function App() {
  const { isAuthenticated, role } = useAuth()

  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route
        path="/*"
        element={
          <ProtectedRoute>
            {role === 'staff' ? <StaffRoutes /> : <StudentRoutes />}
          </ProtectedRoute>
        }
      />
    </Routes>
  )
}
