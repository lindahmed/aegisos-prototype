import { useState } from 'react'
import { FileText, Download, Eye, Clock, AlertCircle } from 'lucide-react'
import { documents as initialDocuments } from '@student/data/mockData'
import type { DocumentRecord } from '@student/types'
import PageHeader from '@student/components/layout/PageHeader'
import Card from '@student/components/ui/Card'
import StatusBadge from '@student/components/ui/StatusBadge'
import Button from '@student/components/ui/Button'
import EmptyState from '@student/components/ui/EmptyState'
import { useToast } from '@student/components/ui/Toast'

const statusTone: Record<DocumentRecord['status'], 'success' | 'warning' | 'error'> = {
  Ready: 'success',
  Processing: 'warning',
  'Requires Action': 'error',
}

const statusIcon: Record<DocumentRecord['status'], typeof Clock> = {
  Ready: FileText,
  Processing: Clock,
  'Requires Action': AlertCircle,
}

export default function Documents() {
  const [documents] = useState(initialDocuments)
  const { showToast } = useToast()

  const categories = Array.from(new Set(documents.map((d) => d.category)))

  return (
    <div>
      <PageHeader
        title="Documents"
        crumbs={[{ label: 'Documents' }]}
        description="Academic records, transcripts, and financial statements."
      />

      {categories.map((category) => (
        <div key={category} className="mb-6">
          <h2 className="mb-3 font-display text-lg font-semibold text-text-primary">{category}</h2>
          <div className="space-y-3">
            {documents
              .filter((d) => d.category === category)
              .map((d) => {
                const Icon = statusIcon[d.status]
                return (
                  <Card key={d.id} className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                    <div className="flex items-center gap-3">
                      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-teal-50 text-teal-600">
                        <Icon className="h-4.5 w-4.5" />
                      </div>
                      <div>
                        <p className="font-medium text-text-primary">{d.name}</p>
                        <p className="text-xs text-text-muted">
                          {d.issuedDate !== '—' ? `Issued ${new Date(d.issuedDate).toLocaleDateString()}` : 'Not yet issued'}
                        </p>
                      </div>
                    </div>
                    <div className="flex items-center gap-3">
                      <StatusBadge label={d.status} tone={statusTone[d.status]} />
                      {d.status === 'Ready' ? (
                        <div className="flex gap-2">
                          <Button size="sm" variant="secondary" icon={<Eye className="h-3.5 w-3.5" />} onClick={() => showToast(`Opening ${d.name}…`, 'info')}>
                            View
                          </Button>
                          <Button size="sm" icon={<Download className="h-3.5 w-3.5" />} onClick={() => showToast(`${d.name} downloaded.`)}>
                            Download
                          </Button>
                        </div>
                      ) : d.status === 'Requires Action' ? (
                        <Button size="sm" variant="danger" onClick={() => showToast('Redirecting to required form…', 'warning')}>
                          Complete Form
                        </Button>
                      ) : (
                        <Button size="sm" variant="secondary" disabled>
                          Processing
                        </Button>
                      )}
                    </div>
                  </Card>
                )
              })}
          </div>
        </div>
      ))}

      {documents.length === 0 && (
        <EmptyState icon={<FileText className="h-5 w-5" />} title="No documents available" description="Requested documents will appear here." />
      )}
    </div>
  )
}
