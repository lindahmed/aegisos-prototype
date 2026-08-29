import { useState } from 'react'
import { BookOpen } from 'lucide-react'
import { courseSections } from '@staff/data/mockData'
import PageHeader from '@staff/components/layout/PageHeader'
import SearchBar from '@staff/components/ui/SearchBar'
import FilterBar from '@staff/components/ui/FilterBar'
import CourseCard from '@staff/components/ui/CourseCard'
import EmptyState from '@staff/components/ui/EmptyState'

const filters = ['All', 'Active', 'Upcoming', 'Completed']

export default function MyCourses() {
  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState('All')

  const filtered = courseSections.filter((c) => {
    const matchesQuery =
      c.title.toLowerCase().includes(query.toLowerCase()) ||
      c.code.toLowerCase().includes(query.toLowerCase()) ||
      c.section.toLowerCase().includes(query.toLowerCase())
    const matchesFilter = filter === 'All' || c.status === filter
    return matchesQuery && matchesFilter
  })

  return (
    <div>
      <PageHeader
        title="My Courses"
        crumbs={[{ label: 'My Courses' }]}
        description="Your assigned course sections across all semesters."
        actions={<SearchBar value={query} onChange={setQuery} placeholder="Search courses" className="w-64" />}
      />

      <div className="mb-6">
        <FilterBar options={filters} active={filter} onChange={setFilter} />
      </div>

      {filtered.length > 0 ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {filtered.map((c) => (
            <CourseCard key={c.id} course={c} />
          ))}
        </div>
      ) : (
        <EmptyState icon={<BookOpen className="h-5 w-5" />} title="No courses found" description="Try a different search term or filter." />
      )}
    </div>
  )
}
