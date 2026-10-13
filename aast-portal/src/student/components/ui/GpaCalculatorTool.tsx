import { useState } from 'react'
import { Plus, Trash2, Calculator } from 'lucide-react'
import { useAuth } from '@student/context/AuthContext'
import Card from './Card'
import Button from './Button'

interface PlannedCourse {
  id: number
  name: string
  credits: number
  grade: string
}

const gradePoints: Record<string, number> = {
  'A': 4.0, 'A-': 3.7, 'B+': 3.3, 'B': 3.0, 'B-': 2.7, 'C+': 2.3, 'C': 2.0, 'D': 1.0, 'F': 0.0,
}

let nextId = 1

export default function GpaCalculatorTool() {
  const { student } = useAuth()
  const [rows, setRows] = useState<PlannedCourse[]>([
    { id: nextId++, name: 'CSE 340 — Operating Systems', credits: 3, grade: 'A-' },
    { id: nextId++, name: 'MTH 250 — Probability & Statistics', credits: 3, grade: 'B+' },
  ])

  const addRow = () => setRows((prev) => [...prev, { id: nextId++, name: '', credits: 3, grade: 'A' }])
  const removeRow = (id: number) => setRows((prev) => prev.filter((r) => r.id !== id))
  const updateRow = (id: number, patch: Partial<PlannedCourse>) =>
    setRows((prev) => prev.map((r) => (r.id === id ? { ...r, ...patch } : r)))

  const plannedPoints = rows.reduce((sum, r) => sum + r.credits * gradePoints[r.grade], 0)
  const plannedCredits = rows.reduce((sum, r) => sum + r.credits, 0)

  const priorGpa = student?.gpa ?? 0
  const priorCredits = (student?.courses.length ?? 0) * 3
  const priorPoints = priorGpa * priorCredits
  const projectedGpa = plannedCredits + priorCredits > 0
    ? (priorPoints + plannedPoints) / (priorCredits + plannedCredits)
    : priorGpa

  return (
    <div className="space-y-4">
      <Card className="flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-md bg-teal-50 text-teal-600">
          <Calculator className="h-5 w-5" />
        </div>
        <div>
          <p className="text-sm text-text-secondary">
            Starting point: current GPA <span className="font-mono font-semibold text-text-primary">{priorGpa.toFixed(2)}</span> over{' '}
            <span className="font-mono font-semibold text-text-primary">{priorCredits}</span> estimated credits.
          </p>
        </div>
      </Card>

      <Card padded={false}>
        <div className="divide-y divide-border">
          {rows.map((row) => (
            <div key={row.id} className="flex flex-col gap-2 p-4 sm:flex-row sm:items-center">
              <input
                value={row.name}
                onChange={(e) => updateRow(row.id, { name: e.target.value })}
                placeholder="Course name"
                className="flex-1 rounded-md border border-border-strong px-3 py-2 text-sm focus-visible:outline-2 focus-visible:outline-teal-600"
              />
              <div className="flex gap-2">
                <input
                  type="number"
                  min={1}
                  max={6}
                  value={row.credits}
                  onChange={(e) => updateRow(row.id, { credits: Number(e.target.value) })}
                  className="w-20 rounded-md border border-border-strong px-3 py-2 text-sm font-mono focus-visible:outline-2 focus-visible:outline-teal-600"
                  aria-label="Credit hours"
                />
                <select
                  value={row.grade}
                  onChange={(e) => updateRow(row.id, { grade: e.target.value })}
                  className="w-24 rounded-md border border-border-strong px-2 py-2 text-sm font-mono focus-visible:outline-2 focus-visible:outline-teal-600"
                  aria-label="Expected grade"
                >
                  {Object.keys(gradePoints).map((g) => (
                    <option key={g} value={g}>
                      {g}
                    </option>
                  ))}
                </select>
                <button
                  onClick={() => removeRow(row.id)}
                  aria-label="Remove course"
                  className="flex h-9 w-9 items-center justify-center rounded-md text-text-muted hover:bg-error-100 hover:text-error"
                >
                  <Trash2 className="h-4 w-4" />
                </button>
              </div>
            </div>
          ))}
        </div>
        <div className="border-t border-border p-4">
          <Button variant="secondary" size="sm" icon={<Plus className="h-3.5 w-3.5" />} onClick={addRow}>
            Add Course
          </Button>
        </div>
      </Card>

      <Card accent="teal" className="flex flex-col items-center gap-1 py-6 text-center">
        <p className="text-sm font-medium text-text-secondary">Projected Cumulative GPA</p>
        <p className="font-mono text-4xl font-bold text-teal-700">{projectedGpa.toFixed(2)}</p>
        <p className="text-xs text-text-muted">
          Based on {plannedCredits} planned credit hours added to your existing record. This is an estimate only.
        </p>
      </Card>
    </div>
  )
}
