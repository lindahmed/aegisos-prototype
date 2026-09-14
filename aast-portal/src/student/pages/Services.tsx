import { useMemo, useState, useEffect } from 'react'
import { useSearchParams } from 'react-router-dom'
import { LayoutGrid } from 'lucide-react'
import { services, serviceCategories } from '@student/data/servicesData'
import PageHeader from '@student/components/layout/PageHeader'
import SearchBar from '@student/components/ui/SearchBar'
import FilterBar from '@student/components/ui/FilterBar'
import ServiceCard from '@student/components/ui/ServiceCard'
import EmptyState from '@student/components/ui/EmptyState'

const filters = ['All', ...serviceCategories]

export default function Services() {
  const [searchParams] = useSearchParams()
  const categoryParam = searchParams.get('category')
  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState(categoryParam && filters.includes(categoryParam) ? categoryParam : 'All')

  useEffect(() => {
    if (categoryParam && filters.includes(categoryParam)) setFilter(categoryParam)
  }, [categoryParam])

  const filtered = useMemo(() => {
    return services.filter((s) => {
      const matchesQuery =
        s.name.toLowerCase().includes(query.toLowerCase()) || s.description.toLowerCase().includes(query.toLowerCase())
      const matchesFilter = filter === 'All' || s.category === filter
      return matchesQuery && matchesFilter
    })
  }, [query, filter])

  const grouped = serviceCategories
    .map((cat) => ({ category: cat, items: filtered.filter((s) => s.category === cat) }))
    .filter((g) => g.items.length > 0)

  return (
    <div>
      <PageHeader
        title="Services"
        crumbs={[{ label: 'Services' }]}
        description="Everything you need to manage your student life, in one directory."
        actions={<SearchBar value={query} onChange={setQuery} placeholder="Search services…" className="w-full sm:w-72" />}
      />

      <div className="mb-6">
        <FilterBar options={filters} active={filter} onChange={setFilter} />
      </div>

      {grouped.length > 0 ? (
        <div className="space-y-8">
          {grouped.map((group) => (
            <div key={group.category}>
              <div className="mb-3 flex items-baseline justify-between">
                <h2 className="font-display text-lg font-semibold text-text-primary">{group.category}</h2>
                <span className="text-xs text-text-muted">{group.items.length} services</span>
              </div>
              <div className="grid grid-cols-3 gap-2 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 xl:grid-cols-8">
                {group.items.map((s) => (
                  <ServiceCard key={s.id} service={s} />
                ))}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <EmptyState
          icon={<LayoutGrid className="h-5 w-5" />}
          title="No services found"
          description="Try a different search term or clear your filter."
        />
      )}
    </div>
  )
}
