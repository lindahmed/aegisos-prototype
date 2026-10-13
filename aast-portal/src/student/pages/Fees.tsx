import { useState } from 'react'
import { Wallet, X } from 'lucide-react'
import { invoices } from '@student/data/mockData'
import type { Invoice } from '@student/types'
import PageHeader from '@student/components/layout/PageHeader'
import Card from '@student/components/ui/Card'
import StatusBadge from '@student/components/ui/StatusBadge'
import Modal from '@student/components/ui/Modal'
import Button from '@student/components/ui/Button'
import { useToast } from '@student/components/ui/Toast'

const statusTone: Record<Invoice['status'], 'success' | 'warning' | 'error' | 'neutral'> = {
  Paid: 'success',
  'Partially Paid': 'warning',
  Unpaid: 'neutral',
  Overdue: 'error',
}

export default function Fees() {
  const [selected, setSelected] = useState<Invoice | null>(null)
  const [paying, setPaying] = useState(false)
  const { showToast } = useToast()

  const totalDue = invoices.reduce((sum, invoice) => sum + (invoice.amount - invoice.paid), 0)
  const sortedInvoices = [...invoices].sort(
    (a, b) => new Date(b.invoiceDate).getTime() - new Date(a.invoiceDate).getTime(),
  )

  const handlePay = async () => {
    setPaying(true)
    await new Promise((resolve) => setTimeout(resolve, 900))
    setPaying(false)
    setSelected(null)
    showToast('Payment submitted successfully.')
  }

  return (
    <div>
      <PageHeader
        title="Fees & Financial"
        crumbs={[{ label: 'Fees' }]}
        description="Review your current balance and invoice history."
      />

      <Card accent="coral" className="flex items-center justify-between gap-4">
        <div>
          <p className="text-sm font-medium text-text-secondary">Current Balance</p>
          <p className="mt-1 font-display text-2xl font-bold text-text-primary">
            EGP {totalDue.toLocaleString()}
          </p>
          <p className="mt-1 text-xs text-text-muted">Your currently outstanding balance</p>
        </div>
        <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-lg bg-coral-50 text-coral-600">
          <Wallet className="h-5 w-5" />
        </div>
      </Card>

      <section className="mt-6" aria-labelledby="invoices-history-heading">
        <h2 id="invoices-history-heading" className="mb-3 font-display text-lg font-semibold text-text-primary">
          Invoices History
        </h2>
        <div className="overflow-hidden rounded-lg border border-border bg-surface shadow-card">
          <div className="hidden overflow-x-auto md:block">
            <table className="w-full min-w-[720px] text-left text-sm">
              <thead>
                <tr className="border-b border-border bg-surface-raised text-xs font-semibold uppercase tracking-wide text-text-muted">
                  <th className="px-4 py-3">Invoice date</th>
                  <th className="px-4 py-3">Invoice</th>
                  <th className="px-4 py-3 text-right">Amount</th>
                  <th className="px-4 py-3">Status</th>
                  <th className="px-4 py-3 text-right"><span className="sr-only">Action</span></th>
                </tr>
              </thead>
              <tbody>
                {sortedInvoices.map((invoice) => (
                  <tr key={invoice.id} className="border-b border-border last:border-0 hover:bg-surface-sunk/60">
                    <td className="whitespace-nowrap px-4 py-3.5 text-text-secondary">
                      {new Date(invoice.invoiceDate).toLocaleDateString()}
                    </td>
                    <td className="px-4 py-3.5">
                      <p className="font-medium text-text-primary">{invoice.label}</p>
                      <p className="text-xs text-text-muted">
                        {invoice.semester} · Due {new Date(invoice.dueDate).toLocaleDateString()}
                      </p>
                    </td>
                    <td className="whitespace-nowrap px-4 py-3.5 text-right font-mono font-semibold text-text-primary">
                      EGP {invoice.amount.toLocaleString()}
                    </td>
                    <td className="px-4 py-3.5">
                      <StatusBadge label={invoice.status} tone={statusTone[invoice.status]} />
                    </td>
                    <td className="px-4 py-3.5 text-right">
                      <Button size="sm" variant="secondary" onClick={() => setSelected(invoice)}>
                        View Invoice
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="divide-y divide-border md:hidden">
            {sortedInvoices.map((invoice) => (
              <article key={invoice.id} className="p-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="font-display text-sm font-semibold text-text-primary">{invoice.label}</p>
                    <p className="mt-0.5 text-xs text-text-muted">
                      Issued {new Date(invoice.invoiceDate).toLocaleDateString()} · {invoice.semester}
                    </p>
                  </div>
                  <StatusBadge label={invoice.status} tone={statusTone[invoice.status]} />
                </div>
                <div className="mt-4 flex items-end justify-between gap-3">
                  <div>
                    <p className="font-mono text-sm font-semibold text-text-primary">
                      EGP {invoice.amount.toLocaleString()}
                    </p>
                    <p className="text-xs text-text-muted">
                      Due {new Date(invoice.dueDate).toLocaleDateString()}
                    </p>
                  </div>
                  <Button size="sm" variant="secondary" onClick={() => setSelected(invoice)}>
                    View Invoice
                  </Button>
                </div>
              </article>
            ))}
          </div>
        </div>
      </section>

      <Modal
        open={!!selected}
        onClose={() => setSelected(null)}
        title="Invoice Details"
        footer={
          <>
            <Button
              variant="secondary"
              onClick={() => setSelected(null)}
              icon={<X className="h-3.5 w-3.5" />}
            >
              Close
            </Button>
            {selected && selected.status !== 'Paid' && (
              <Button loading={paying} onClick={handlePay}>
                Pay EGP {(selected.amount - selected.paid).toLocaleString()}
              </Button>
            )}
          </>
        }
      >
        {selected && (
          <div className="space-y-3 text-sm">
            <div className="flex justify-between gap-4">
              <span className="text-text-secondary">Description</span>
              <span className="text-right font-medium text-text-primary">{selected.label}</span>
            </div>
            <div className="flex justify-between gap-4">
              <span className="text-text-secondary">Semester</span>
              <span className="text-right font-medium text-text-primary">{selected.semester}</span>
            </div>
            <div className="flex justify-between gap-4">
              <span className="text-text-secondary">Invoice Date</span>
              <span className="text-right font-medium text-text-primary">
                {new Date(selected.invoiceDate).toLocaleDateString()}
              </span>
            </div>
            <div className="flex justify-between gap-4">
              <span className="text-text-secondary">Due Date</span>
              <span className="text-right font-medium text-text-primary">
                {new Date(selected.dueDate).toLocaleDateString()}
              </span>
            </div>
            <div className="flex items-center justify-between gap-4">
              <span className="text-text-secondary">Status</span>
              <StatusBadge label={selected.status} tone={statusTone[selected.status]} />
            </div>
            <div className="flex justify-between gap-4 border-t border-border pt-3">
              <span className="font-semibold text-text-primary">Amount</span>
              <span className="font-mono font-semibold text-text-primary">
                EGP {selected.amount.toLocaleString()}
              </span>
            </div>
          </div>
        )}
      </Modal>
    </div>
  )
}
