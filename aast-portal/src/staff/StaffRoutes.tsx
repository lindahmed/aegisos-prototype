import { Routes, Route } from 'react-router-dom'
import AppShell from '@staff/components/layout/AppShell'
import { ToastProvider } from '@staff/components/ui/Toast'
import { CaseManagementProvider } from '@staff/context/CaseManagementContext'
import Dashboard from '@staff/pages/Dashboard'
import MyCourses from '@staff/pages/MyCourses'
import CourseDetail from '@staff/pages/CourseDetail'
import StudentList from '@staff/pages/StudentList'
import StudentDetail from '@staff/pages/StudentDetail'
import CaseManagement from '@staff/pages/CaseManagement'
import CaseDetail from '@staff/pages/CaseDetail'
import Attendance from '@staff/pages/Attendance'
import Grades from '@staff/pages/Grades'
import Schedule from '@staff/pages/Schedule'
import ExamSchedule from '@staff/pages/ExamSchedule'
import Requests from '@staff/pages/Requests'
import Reports from '@staff/pages/Reports'
import StaffServices from '@staff/pages/StaffServices'
import ServiceDetail from '@staff/pages/ServiceDetail'
import Support from '@staff/pages/Support'
import Announcements from '@staff/pages/Announcements'
import Notifications from '@staff/pages/Notifications'
import Profile from '@staff/pages/Profile'
import UpdateData from '@staff/pages/UpdateData'
import ChangePassword from '@staff/pages/ChangePassword'
import Settings from '@staff/pages/Settings'

export default function StaffRoutes() {
  return (
    <ToastProvider>
      <CaseManagementProvider>
      <Routes>
      <Route
        element={<AppShell />}
      >
        <Route path="/" element={<Dashboard />} />
        <Route path="/courses" element={<MyCourses />} />
        <Route path="/courses/:id" element={<CourseDetail />} />
        <Route path="/students" element={<StudentList />} />
        <Route path="/students/:id" element={<StudentDetail />} />
        <Route path="/case-management" element={<CaseManagement />} />
        <Route path="/case-management/:id" element={<CaseDetail />} />
        <Route path="/attendance" element={<Attendance />} />
        <Route path="/grades" element={<Grades />} />
        <Route path="/schedule" element={<Schedule />} />
        <Route path="/exams" element={<ExamSchedule />} />
        <Route path="/requests" element={<Requests />} />
        <Route path="/reports" element={<Reports />} />
        <Route path="/services" element={<StaffServices />} />
        <Route path="/services/:slug" element={<ServiceDetail />} />
        <Route path="/support" element={<Support />} />
        <Route path="/announcements" element={<Announcements />} />
        <Route path="/notifications" element={<Notifications />} />
        <Route path="/profile" element={<Profile />} />
        <Route path="/profile/update" element={<UpdateData />} />
        <Route path="/profile/password" element={<ChangePassword />} />
        <Route path="/settings" element={<Settings />} />
      </Route>
      </Routes>
      </CaseManagementProvider>
    </ToastProvider>
  )
}
