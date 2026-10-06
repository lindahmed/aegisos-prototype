import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { ShieldAlert, ArrowRight } from 'lucide-react'
import { getAtRiskStudents } from '@staff/data/caseManagementData'
import { useCaseManagement } from '@staff/context/CaseManagementContext'
import PageHeader from '@staff/components/layout/PageHeader'
import Card from '@staff/components/ui/Card'
import StatCard from '@staff/components/ui/StatCard'
import SearchBar from '@staff/components/ui/SearchBar'
import FilterBar from '@staff/components/ui/FilterBar'
import StatusBadge from '@staff/components/ui/StatusBadge'
import EmptyState from '@staff/components/ui/EmptyState'

const filters = ['All', 'At Risk', 'Failing']

const gradeStatusTone: Record<string, 'success' | 'warning' | 'error' | 'info'> = {
  Excellent: 'success',
  'On Track': 'info',
  'At Risk': 'warning',
  Failing: 'error',
}

export default function CaseManagement() {
  const atRiskStudents = useMemo(() => getAtRiskStudents(), [])
  const { getInterventionsForStudent, getAssignedAdvisor } = useCaseManagement()

  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState('All')

  const filtered = atRiskStudents.filter((s) => {
    const matchesQuery = s.fullName.toLowerCase().includes(query.toLowerCase()) || s.studentId.includes(query)
    const matchesFilter = filter === 'All' || s.gradeStatus === filter
    return matchesQuery && matchesFilter
  })

  const openCasesCount = atRiskStudents.reduce((sum, s) => sum + getInterventionsForStudent(s.id).filter((iv) => iv.status !== 'Resolved').length, 0)
  const unassignedCount = atRiskStudents.filter((s) => !getAssignedAdvisor(s.id)).length

  return (
    <div>
      <PageHeader
        title="Case Management"
        crumbs={[{ label: 'Case Management' }]}
        description="Track at-risk students, log advisor interventions, and see whether follow-ups are improving outcomes."
        actions={<SearchBar value={query} onChange={setQuery} placeholder="Search by name or ID" className="w-64" />}
      />

      <div className="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
        <StatCard label="At-Risk Students" value={String(atRiskStudents.length)} icon={<ShieldAlert className="h-5 w-5" />} accent="coral" />
        <StatCard label="Open Cases" value={String(openCasesCount)} icon={<ShieldAlert className="h-5 w-5" />} accent="ink" />
        <StatCard label="Unassigned" value={String(unassignedCount)} sublabel="Students without an advisor" icon={<ShieldAlert className="h-5 w-5" />} accent="teal" />
      </div>

      <div className="mb-4">
        <FilterBar options={filters} active={filter} onChange={setFilter} />
      </div>

      {filtered.length > 0 ? (
        <div className="overflow-x-auto rounded-lg border border-border bg-surface shadow-card">
          <table className="w-full min-w-[820px] text-left text-sm">
            <thead>
              <tr className="border-b border-border bg-surface-raised text-xs font-semibold uppercase tracking-wide text-text-muted">
                <th className="px-4 py-3">Student</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3">Attendance</th>
                <th className="px-4 py-3">Assigned Advisor</th>
                <th className="px-4 py-3">Open Cases</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {filtered.map((s) => {
                const cases = getInterventionsForStudent(s.id)
                const openCases = cases.filter((iv) => iv.status !== 'Resolved').length
                const advisor = getAssignedAdvisor(s.id)
                return (
                  <tr key={s.id} className="border-b border-border last:border-0 hover:bg-surface-sunk/60">
                    <td className="px-4 py-3.5">
                      <p className="font-medium text-text-primary">{s.fullName}</p>
                      <p className="font-mono text-xs text-text-muted">{s.studentId}</p>
                    </td>
                    <td className="px-4 py-3.5">
                      <StatusBadge label={s.gradeStatus} tone={gradeStatusTone[s.gradeStatus]} />
                    </td>
                    <td className="px-4 py-3.5 font-mono text-text-secondary">{s.attendancePct}%</td>
                    <td className="px-4 py-3.5 text-text-secondary">
                      {advisor ?? <span className="italic text-text-muted">Unassigned</span>}
                    </td>
                    <td className="px-4 py-3.5 text-text-secondary">
                      {openCases > 0 ? `${openCases} open` : cases.length > 0 ? 'All resolved' : 'No cases yet'}
                    </td>
                    <td className="px-4 py-3.5 text-right">
                      <Link
                        to={`/case-management/${s.id}`}
                        className="inline-flex items-center gap-1 text-sm font-semibold text-teal-700 hover:underline"
                      >
                        Open case
                        <ArrowRight className="h-3.5 w-3.5" />
                      </Link>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      ) : (
        <EmptyState icon={<ShieldAlert className="h-5 w-5" />} title="No matching students" description="Try a different search term or filter." />
      )}
    </div>
  )
}
