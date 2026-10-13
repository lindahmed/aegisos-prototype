import { useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { BarChart3, ClipboardEdit, Award, PieChart } from 'lucide-react'
import { courseSections, students } from '@staff/data/mockData'
import PageHeader from '@staff/components/layout/PageHeader'
import Tabs from '@staff/components/ui/Tabs'
import Card from '@staff/components/ui/Card'
import StatCard from '@staff/components/ui/StatCard'

const tabs = ['Academic', 'Attendance', 'Grades', 'Statistics']

const gradeDistribution = [
  { grade: 'A', count: 22 },
  { grade: 'B', count: 34 },
  { grade: 'C', count: 18 },
  { grade: 'D', count: 6 },
  { grade: 'F', count: 3 },
]

export default function Reports() {
  const [searchParams] = useSearchParams()
  const tabParam = searchParams.get('tab')
  const [activeTab, setActiveTab] = useState(tabs.includes(tabParam ?? '') ? (tabParam as string) : tabs[0])

  useEffect(() => {
    if (tabParam && tabs.includes(tabParam)) setActiveTab(tabParam)
  }, [tabParam])

  const activeCourses = courseSections.filter((c) => c.status === 'Active')
  const avgAttendance = Math.round(students.reduce((sum, s) => sum + s.attendancePct, 0) / students.length)
  const atRisk = students.filter((s) => s.gradeStatus === 'At Risk' || s.gradeStatus === 'Failing').length
  const maxGradeCount = Math.max(...gradeDistribution.map((g) => g.count))

  return (
    <div>
      <PageHeader title="Reports & Statistics" crumbs={[{ label: 'Reports' }]} description="Academic, attendance, and grade insights across your courses." />

      <Card padded={false}>
        <div className="px-2 pt-1">
          <Tabs tabs={tabs} active={activeTab} onChange={setActiveTab} />
        </div>
        <div className="p-5">
          {activeTab === 'Academic' && (
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
              <StatCard label="Active Sections" value={String(activeCourses.length)} icon={<BarChart3 className="h-5 w-5" />} accent="teal" />
              <StatCard label="Total Enrollment" value={String(activeCourses.reduce((s, c) => s + c.studentsCount, 0))} icon={<BarChart3 className="h-5 w-5" />} accent="ink" />
              <StatCard label="Avg. Section Size" value={String(Math.round(activeCourses.reduce((s, c) => s + c.studentsCount, 0) / activeCourses.length))} icon={<BarChart3 className="h-5 w-5" />} accent="teal" />
            </div>
          )}

          {activeTab === 'Attendance' && (
            <div className="space-y-4">
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <StatCard label="Average Attendance" value={`${avgAttendance}%`} icon={<ClipboardEdit className="h-5 w-5" />} accent="teal" />
                <StatCard label="Students Below 75%" value={String(students.filter((s) => s.attendancePct < 75).length)} icon={<ClipboardEdit className="h-5 w-5" />} accent="coral" />
              </div>
            </div>
          )}

          {activeTab === 'Grades' && (
            <div>
              <div className="mb-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
                <StatCard label="At-Risk Students" value={String(atRisk)} icon={<Award className="h-5 w-5" />} accent="coral" />
                <StatCard label="Excellent Standing" value={String(students.filter((s) => s.gradeStatus === 'Excellent').length)} icon={<Award className="h-5 w-5" />} accent="teal" />
              </div>
              <p className="mb-2 text-sm font-semibold text-text-primary">Grade Distribution — CSE 301</p>
              <div className="flex items-end gap-6 rounded-md border border-border p-4">
                {gradeDistribution.map((g) => (
                  <div key={g.grade} className="flex flex-col items-center gap-2">
                    <div className="flex h-28 w-10 items-end rounded-md bg-surface-sunk">
                      <div className="w-full rounded-md bg-teal-600" style={{ height: `${(g.count / maxGradeCount) * 100}%` }} />
                    </div>
                    <span className="font-mono text-xs font-semibold text-text-primary">{g.grade}</span>
                    <span className="text-[11px] text-text-muted">{g.count}</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {activeTab === 'Statistics' && (
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
              <StatCard label="Courses Taught (Career)" value="24" icon={<PieChart className="h-5 w-5" />} accent="ink" />
              <StatCard label="Students Taught (Career)" value="612" icon={<PieChart className="h-5 w-5" />} accent="teal" />
              <StatCard label="Avg. Course Rating" value="4.6 / 5" icon={<PieChart className="h-5 w-5" />} accent="teal" />
            </div>
          )}
        </div>
      </Card>
    </div>
  )
}
