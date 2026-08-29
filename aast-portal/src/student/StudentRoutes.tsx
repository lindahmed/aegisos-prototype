import { Routes, Route } from 'react-router-dom'
import AppShell from '@student/components/layout/AppShell'
import { ToastProvider } from '@student/components/ui/Toast'
import { StudentAcademicsProvider } from '@student/context/StudentAcademicsContext'
import Dashboard from '@student/pages/Dashboard'
import Profile from '@student/pages/Profile'
import Registration from '@student/pages/Registration'
import Courses from '@student/pages/Courses'
import CourseDetail from '@student/pages/CourseDetail'
import Schedule from '@student/pages/Schedule'
import Grades from '@student/pages/Grades'
import Exams from '@student/pages/Exams'
import Fees from '@student/pages/Fees'
import Announcements from '@student/pages/Announcements'
import Notifications from '@student/pages/Notifications'
import Documents from '@student/pages/Documents'
import Services from '@student/pages/Services'
import ServiceDetail from '@student/pages/ServiceDetail'

export default function StudentRoutes() {
  return (
    <ToastProvider>
      <StudentAcademicsProvider>
        <Routes>
          <Route element={<AppShell />}>
            <Route path="/" element={<Dashboard />} />
            <Route path="/profile" element={<Profile />} />
            <Route path="/registration" element={<Registration />} />
            <Route path="/courses" element={<Courses />} />
            <Route path="/courses/:id" element={<CourseDetail />} />
            <Route path="/schedule" element={<Schedule />} />
            <Route path="/grades" element={<Grades />} />
            <Route path="/exams" element={<Exams />} />
            <Route path="/fees" element={<Fees />} />
            <Route path="/announcements" element={<Announcements />} />
            <Route path="/notifications" element={<Notifications />} />
            <Route path="/documents" element={<Documents />} />
            <Route path="/services" element={<Services />} />
            <Route path="/services/:slug" element={<ServiceDetail />} />
          </Route>
        </Routes>
      </StudentAcademicsProvider>
    </ToastProvider>
  )
}
