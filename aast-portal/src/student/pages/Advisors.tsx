import { useState } from 'react'
import { Mail, Phone, MapPin, Clock, Contact } from 'lucide-react'
import { advisors, advisorDepartments } from '@student/data/advisorsData'
import PageHeader from '@student/components/layout/PageHeader'
import Card from '@student/components/ui/Card'
import SearchBar from '@student/components/ui/SearchBar'
import FilterBar from '@student/components/ui/FilterBar'
import EmptyState from '@student/components/ui/EmptyState'

function initials(name: string): string {
  return name
    .replace(/^(Dr\.|Eng\.)\s*/, '')
    .split(' ')
    .map((n) => n[0])
    .slice(0, 2)
    .join('')
    .toUpperCase()
}

export default function Advisors() {
  const [query, setQuery] = useState('')
  const [department, setDepartment] = useState('All')

  const filtered = advisors.filter((a) => {
    const matchesDepartment = department === 'All' || a.department === department
    const q = query.trim().toLowerCase()
    const matchesQuery =
      !q || a.name.toLowerCase().includes(q) || a.department.toLowerCase().includes(q) || a.title.toLowerCase().includes(q)
    return matchesDepartment && matchesQuery
  })

  return (
    <div>
      <PageHeader
        title="Academic Advisors"
        crumbs={[{ label: 'Advisors' }]}
        description="Find and contact the academic advisor for your department or program."
        actions={<SearchBar value={query} onChange={setQuery} placeholder="Search advisors" className="w-64" />}
      />

      <div className="mb-4">
        <FilterBar options={advisorDepartments} active={department} onChange={setDepartment} />
      </div>

      {filtered.length > 0 ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {filtered.map((a) => (
            <Card key={a.id} className="flex flex-col gap-3">
              <div className="flex items-center gap-3">
                <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-teal-600 font-display text-sm font-bold text-white">
                  {initials(a.name)}
                </div>
                <div className="min-w-0">
                  <p className="truncate text-sm font-semibold text-text-primary">{a.name}</p>
                  <p className="truncate text-xs text-text-muted">{a.title}</p>
                </div>
              </div>

              <p className="text-xs font-semibold uppercase tracking-wide text-teal-700">{a.department}</p>
              <p className="text-sm text-text-secondary">{a.bio}</p>

              <div className="space-y-1.5 border-t border-border pt-3 text-sm text-text-secondary">
                <a href={`mailto:${a.email}`} className="flex items-center gap-2 hover:text-teal-700">
                  <Mail className="h-3.5 w-3.5 shrink-0 text-text-muted" />
                  <span className="truncate">{a.email}</span>
                </a>
                <a href={`tel:${a.phone.replace(/\s+/g, '')}`} className="flex items-center gap-2 hover:text-teal-700">
                  <Phone className="h-3.5 w-3.5 shrink-0 text-text-muted" />
                  {a.phone}
                </a>
                <div className="flex items-center gap-2">
                  <MapPin className="h-3.5 w-3.5 shrink-0 text-text-muted" />
                  {a.office}
                </div>
                <div className="flex items-center gap-2">
                  <Clock className="h-3.5 w-3.5 shrink-0 text-text-muted" />
                  {a.officeHours}
                </div>
              </div>
            </Card>
          ))}
        </div>
      ) : (
        <EmptyState icon={<Contact className="h-5 w-5" />} title="No advisors found" description="Try a different search term or department filter." />
      )}
    </div>
  )
}
