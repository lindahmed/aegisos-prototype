import { useState } from 'react'
import { LayoutGrid } from 'lucide-react'
import { staffServices } from '@staff/data/staffServicesData'
import PageHeader from '@staff/components/layout/PageHeader'
import SearchBar from '@staff/components/ui/SearchBar'
import ServiceCard from '@staff/components/ui/ServiceCard'
import EmptyState from '@staff/components/ui/EmptyState'

export default function StaffServices() {
  const [query, setQuery] = useState('')

  const filtered = staffServices.filter(
    (s) => s.name.toLowerCase().includes(query.toLowerCase()) || s.description.toLowerCase().includes(query.toLowerCase())
  )

  return (
    <div>
      <PageHeader
        title="Staff Services"
        crumbs={[{ label: 'Services' }]}
        description="Administrative and support services available to faculty and staff."
        actions={<SearchBar value={query} onChange={setQuery} placeholder="Search services…" className="w-64" />}
      />

      {filtered.length > 0 ? (
        <div className="grid grid-cols-3 gap-2 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 xl:grid-cols-8">
          {filtered.map((s) => (
            <ServiceCard key={s.id} service={s} />
          ))}
        </div>
      ) : (
        <EmptyState icon={<LayoutGrid className="h-5 w-5" />} title="No services found" description="Try a different search term." />
      )}
    </div>
  )
}
