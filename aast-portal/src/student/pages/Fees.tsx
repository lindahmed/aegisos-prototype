import { useState } from 'react'
import { Wallet, Receipt, CreditCard, X } from 'lucide-react'
import { invoices, paymentHistory } from '@student/data/mockData'
import type { Invoice } from '@student/types'
import PageHeader from '@student/components/layout/PageHeader'
import Card from '@student/components/ui/Card'
import StatCard from '@student/components/ui/StatCard'
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

  const totalDue = invoices.reduce((sum, i) => sum + (i.amount - i.paid), 0)
  const totalPaid = invoices.reduce((sum, i) => sum + i.paid, 0)

  const handlePay = async () => {
    setPaying(true)
    await new Promise((r) => setTimeout(r, 900))
    setPaying(false)
    setSelected(null)
    showToast('Payment submitted successfully.')
  }

  return (
    <div>
      <PageHeader title="Fees & Financial" crumbs={[{ label: 'Fees' }]} description="View tuition invoices and payment history." />

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <StatCard label="Outstanding Balance" value={`EGP ${totalDue.toLocaleString()}`} icon={<Wallet className="h-5 w-5" />} accent="coral" />
        <StatCard label="Total Paid (Fall 2026)" value={`EGP ${totalPaid.toLocaleString()}`} icon={<CreditCard className="h-5 w-5" />} accent="teal" />
        <StatCard label="Next Due Date" value="Sep 5" sublabel="Installment 2" icon={<Receipt className="h-5 w-5" />} accent="ink" />
      </div>

      <div className="mt-6">
        <h2 className="mb-3 font-display text-lg font-semibold text-text-primary">Invoices</h2>
        <div className="space-y-3">
          {invoices.map((inv) => (
            <Card key={inv.id} className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p className="font-display text-base font-semibold text-text-primary">{inv.label}</p>
                <p className="text-xs text-text-muted">{inv.semester} · Due {new Date(inv.dueDate).toLocaleDateString()}</p>
              </div>
              <div className="flex items-center gap-4">
                <div className="text-right">
                  <p className="font-mono text-sm font-semibold text-text-primary">EGP {inv.amount.toLocaleString()}</p>
                  <StatusBadge label={inv.status} tone={statusTone[inv.status]} />
                </div>
                <Button size="sm" variant={inv.status === 'Paid' ? 'secondary' : 'primary'} onClick={() => setSelected(inv)}>
                  {inv.status === 'Paid' ? 'View Invoice' : 'Pay Now'}
                </Button>
              </div>
            </Card>
          ))}
        </div>
      </div>

      <div className="mt-6">
        <h2 className="mb-3 font-display text-lg font-semibold text-text-primary">Payment History</h2>
        <div className="overflow-x-auto rounded-lg border border-border bg-surface shadow-card">
          <table className="w-full min-w-[520px] text-left text-sm">
            <thead>
              <tr className="border-b border-border bg-surface-raised text-xs font-semibold uppercase tracking-wide text-text-muted">
                <th className="px-4 py-3">Date</th>
                <th className="px-4 py-3">Reference</th>
                <th className="px-4 py-3">Method</th>
                <th className="px-4 py-3 text-right">Amount</th>
              </tr>
            </thead>
            <tbody>
              {paymentHistory.map((p) => (
                <tr key={p.id} className="border-b border-border last:border-0 hover:bg-surface-sunk/60">
                  <td className="px-4 py-3.5 text-text-secondary">{new Date(p.date).toLocaleDateString()}</td>
                  <td className="px-4 py-3.5 font-mono text-xs text-text-muted">{p.reference}</td>
                  <td className="px-4 py-3.5 text-text-secondary">{p.method}</td>
                  <td className="px-4 py-3.5 text-right font-mono font-semibold text-text-primary">EGP {p.amount.toLocaleString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <Modal
        open={!!selected}
        onClose={() => setSelected(null)}
        title={selected?.status === 'Paid' ? 'Invoice Details' : 'Confirm Payment'}
        footer={
          selected?.status === 'Paid' ? (
            <Button variant="secondary" onClick={() => setSelected(null)}>
              Close
            </Button>
          ) : (
            <>
              <Button variant="secondary" onClick={() => setSelected(null)} icon={<X className="h-3.5 w-3.5" />}>
                Cancel
              </Button>
              <Button loading={paying} onClick={handlePay}>
                Confirm Payment
              </Button>
            </>
          )
        }
      >
        {selected && (
          <div className="space-y-3 text-sm">
            <div className="flex justify-between">
              <span className="text-text-secondary">Description</span>
              <span className="font-medium text-text-primary">{selected.label}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-text-secondary">Semester</span>
              <span className="font-medium text-text-primary">{selected.semester}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-text-secondary">Due Date</span>
              <span className="font-medium text-text-primary">{new Date(selected.dueDate).toLocaleDateString()}</span>
            </div>
            <div className="flex justify-between border-t border-border pt-3">
              <span className="font-semibold text-text-primary">Amount</span>
              <span className="font-mono font-semibold text-text-primary">EGP {selected.amount.toLocaleString()}</span>
            </div>
          </div>
        )}
      </Modal>
    </div>
  )
}
