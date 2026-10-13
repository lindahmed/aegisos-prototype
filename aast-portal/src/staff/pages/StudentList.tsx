import { useMemo, useState } from 'react'
import { Users } from 'lucide-react'
import { students } from '@staff/data/mockData'
import PageHeader from '@staff/components/layout/PageHeader'
import SearchBar from '@staff/components/ui/SearchBar'
import FilterBar from '@staff/components/ui/FilterBar'
import StudentTable from '@staff/components/ui/StudentTable'
import Pagination from '@staff/components/ui/Pagination'
import EmptyState from '@staff/components/ui/EmptyState'

const filters = ['All', 'Sec 01', 'Sec 02']
const PAGE_SIZE = 8

export default function StudentList() {
  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState('All')
  const [page, setPage] = useState(1)

  const filtered = useMemo(() => {
    return students.filter((s) => {
      const matchesQuery = s.fullName.toLowerCase().includes(query.toLowerCase()) || s.studentId.includes(query)
      const matchesFilter = filter === 'All' || s.section === filter
      return matchesQuery && matchesFilter
    })
  }, [query, filter])

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const paged = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  return (
    <div>
      <PageHeader
        title="Student List"
        crumbs={[{ label: 'Students' }]}
        description="Search and browse students across your assigned sections."
        actions={<SearchBar value={query} onChange={(v) => { setQuery(v); setPage(1) }} placeholder="Search by name or ID" className="w-64" />}
      />

      <div className="mb-4">
        <FilterBar options={filters} active={filter} onChange={(v) => { setFilter(v); setPage(1) }} />
      </div>

      {paged.length > 0 ? (
        <>
          <StudentTable students={paged} />
          <Pagination page={page} totalPages={totalPages} onChange={setPage} />
        </>
      ) : (
        <EmptyState icon={<Users className="h-5 w-5" />} title="No students found" description="Try a different search term or filter." />
      )}
    </div>
  )
}
