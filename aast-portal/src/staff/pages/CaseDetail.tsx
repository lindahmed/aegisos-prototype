import { useMemo, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import {
  ArrowLeft,
  Users as UsersIcon,
  ShieldAlert,
  Clock,
  GraduationCap,
  ClipboardList,
  MessageSquarePlus,
  CheckCircle2,
  TrendingUp,
  TrendingDown,
  Minus,
  HourglassIcon,
} from 'lucide-react'
import { students } from '@staff/data/mockData'
import { advisorNames, estimatedAverageScore, buildStudentTimeline, getInterventionOutcome } from '@staff/data/caseManagementData'
import { useCaseManagement } from '@staff/context/CaseManagementContext'
import { useToast } from '@staff/components/ui/Toast'
import PageHeader from '@staff/components/layout/PageHeader'
import Card from '@staff/components/ui/Card'
import Button from '@staff/components/ui/Button'
import Dropdown from '@staff/components/ui/Dropdown'
import Modal from '@staff/components/ui/Modal'
import StatusBadge from '@staff/components/ui/StatusBadge'
import EmptyState from '@staff/components/ui/EmptyState'
import type { TimelineEventKind, InterventionStatus } from '@staff/types'

const timelineIcon: Record<TimelineEventKind, React.ElementType> = {
  grade: GraduationCap,
  attendance: Clock,
  request: ClipboardList,
  intervention: MessageSquarePlus,
}

const toneDot: Record<string, string> = {
  success: 'bg-success',
  warning: 'bg-warning',
  error: 'bg-error',
  info: 'bg-teal-600',
  neutral: 'bg-text-muted',
}

const statusTone: Record<InterventionStatus, 'success' | 'warning' | 'info'> = {
  Open: 'warning',
  'Follow-up Scheduled': 'info',
  Resolved: 'success',
}

const outcomeDisplay: Record<string, { label: string; tone: 'success' | 'warning' | 'error' | 'info'; Icon: React.ElementType }> = {
  Improved: { label: 'Improved', tone: 'success', Icon: TrendingUp },
  'No Change': { label: 'No Change', tone: 'warning', Icon: Minus },
  Declined: { label: 'Declined', tone: 'error', Icon: TrendingDown },
  Pending: { label: 'Pending follow-up', tone: 'info', Icon: HourglassIcon },
}

const gradeStatusTone: Record<string, 'success' | 'warning' | 'error' | 'info'> = {
  Excellent: 'success',
  'On Track': 'info',
  'At Risk': 'warning',
  Failing: 'error',
}

export default function CaseDetail() {
  const { id } = useParams()
  const student = students.find((s) => s.id === id)
  const { getInterventionsForStudent, getAssignedAdvisor, setAdvisorForStudent, addIntervention, resolveIntervention } =
    useCaseManagement()
  const { showToast } = useToast()

  const [modalOpen, setModalOpen] = useState(false)
  const [note, setNote] = useState('')
  const [followUpDate, setFollowUpDate] = useState('')
  const [noteAdvisor, setNoteAdvisor] = useState(advisorNames[0])

  if (!student) {
    return (
      <EmptyState
        icon={<UsersIcon className="h-5 w-5" />}
        title="Student not found"
        action={
          <Link to="/case-management" className="text-sm font-semibold text-teal-700 hover:underline">
            Back to Case Management
          </Link>
        }
      />
    )
  }

  const cases = getInterventionsForStudent(student.id)
  const timeline = useMemo(() => buildStudentTimeline(student, cases), [student, cases])
  const assignedAdvisor = getAssignedAdvisor(student.id)

  function handleAddNote() {
    if (!student) return
    if (!note.trim() || !followUpDate) {
      showToast('Please add a note and a follow-up date.', 'warning')
      return
    }
    addIntervention({
      studentId: student.id,
      note: note.trim(),
      followUpDate,
      assignedAdvisor: noteAdvisor,
      baselineAttendancePct: student.attendancePct,
      baselineAvgScore: estimatedAverageScore(student),
    })
    showToast('Note logged and follow-up scheduled.')
    setNote('')
    setFollowUpDate('')
    setModalOpen(false)
  }

  return (
    <div>
      <PageHeader
        title={student.fullName}
        crumbs={[{ label: 'Case Management', to: '/case-management' }, { label: student.studentId }]}
        description={`${student.department} · ${student.level}`}
        actions={<StatusBadge label={student.gradeStatus} tone={gradeStatusTone[student.gradeStatus]} />}
      />

      <Link to="/case-management" className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-text-secondary hover:text-teal-700">
        <ArrowLeft className="h-3.5 w-3.5" />
        Back to Case Management
      </Link>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div className="space-y-4 lg:col-span-1">
          <Card>
            <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-teal-600 font-display text-xl font-bold text-white">
              {student.fullName.split(' ').map((n) => n[0]).slice(0, 2).join('')}
            </div>
            <p className="mt-3 text-center font-display text-base font-semibold text-text-primary">{student.fullName}</p>
            <p className="text-center font-mono text-xs text-text-muted">{student.studentId}</p>
            <dl className="mt-4 space-y-2.5 border-t border-border pt-4 text-sm">
              <div className="flex justify-between gap-3">
                <dt className="text-text-secondary">Attendance</dt>
                <dd className="font-mono font-semibold text-text-primary">{student.attendancePct}%</dd>
              </div>
              <div className="flex justify-between gap-3">
                <dt className="text-text-secondary">Est. running average</dt>
                <dd className="font-mono font-semibold text-text-primary">{estimatedAverageScore(student)}/100</dd>
              </div>
              <div className="flex justify-between gap-3">
                <dt className="text-text-secondary">Section</dt>
                <dd className="text-right font-medium text-text-primary">{student.section}</dd>
              </div>
            </dl>
          </Card>

          <Card>
            <p className="mb-2 flex items-center gap-1.5 text-sm font-semibold text-text-primary">
              <ShieldAlert className="h-4 w-4 text-teal-600" />
              Assigned Advisor
            </p>
            <Dropdown
              label="Assign advisor"
              value={assignedAdvisor}
              onSelect={(v) => {
                setAdvisorForStudent(student.id, v)
                showToast(`${student.fullName} assigned to ${v}.`)
              }}
              options={advisorNames.map((a) => ({ label: a, value: a }))}
            />
          </Card>

          <Button className="w-full" icon={<MessageSquarePlus className="h-4 w-4" />} onClick={() => setModalOpen(true)}>
            Log Intervention
          </Button>
        </div>

        <div className="space-y-4 lg:col-span-2">
          <Card>
            <p className="mb-3 text-sm font-semibold text-text-primary">Intervention Cases</p>
            {cases.length > 0 ? (
              <div className="divide-y divide-border">
                {cases.map((iv) => {
                  const outcome = getInterventionOutcome(iv, student)
                  const { label, tone, Icon } = outcomeDisplay[outcome]
                  return (
                    <div key={iv.id} className="py-3 first:pt-0">
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <div className="flex items-center gap-2">
                          <StatusBadge label={iv.status} tone={statusTone[iv.status]} />
                          <span className="inline-flex items-center gap-1 text-xs font-semibold text-text-secondary">
                            <Icon className="h-3.5 w-3.5" />
                            <StatusBadge label={label} tone={tone} />
                          </span>
                        </div>
                        {iv.status !== 'Resolved' && (
                          <Button variant="secondary" size="sm" icon={<CheckCircle2 className="h-3.5 w-3.5" />} onClick={() => resolveIntervention(iv.id)}>
                            Mark Resolved
                          </Button>
                        )}
                      </div>
                      <p className="mt-2 text-sm text-text-secondary">{iv.note}</p>
                      <p className="mt-1.5 text-xs text-text-muted">
                        Logged {new Date(iv.createdDate).toLocaleDateString()} by {iv.createdBy} · Advisor: {iv.assignedAdvisor} · Follow-up{' '}
                        {new Date(iv.followUpDate).toLocaleDateString()}
                      </p>
                    </div>
                  )
                })}
              </div>
            ) : (
              <EmptyState icon={<MessageSquarePlus className="h-5 w-5" />} title="No interventions logged yet" description="Log a note to start tracking this case." />
            )}
          </Card>

          <Card>
            <p className="mb-3 text-sm font-semibold text-text-primary">Student Timeline</p>
            <div className="space-y-0">
              {timeline.map((event, i) => {
                const Icon = timelineIcon[event.kind]
                return (
                  <div key={event.id} className="relative flex gap-3 pb-5 last:pb-0">
                    {i < timeline.length - 1 && <span className="absolute left-[15px] top-8 h-full w-px bg-border" aria-hidden="true" />}
                    <div className={`z-10 flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-white ${toneDot[event.tone]}`}>
                      <Icon className="h-4 w-4" />
                    </div>
                    <div className="min-w-0 flex-1 pt-0.5">
                      <div className="flex flex-wrap items-baseline justify-between gap-x-3">
                        <p className="text-sm font-semibold text-text-primary">{event.title}</p>
                        <p className="text-xs text-text-muted">{new Date(event.date).toLocaleDateString()}</p>
                      </div>
                      <p className="mt-0.5 text-sm text-text-secondary">{event.description}</p>
                    </div>
                  </div>
                )
              })}
            </div>
          </Card>
        </div>
      </div>

      <Modal
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        title="Log Intervention"
        footer={
          <>
            <Button variant="secondary" onClick={() => setModalOpen(false)}>
              Cancel
            </Button>
            <Button onClick={handleAddNote}>Save Note</Button>
          </>
        }
      >
        <div className="space-y-4">
          <div>
            <label className="mb-1.5 block text-sm font-medium text-text-primary">Note</label>
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={4}
              placeholder="Describe what was observed and what action was taken..."
              className="w-full rounded-md border border-border-strong bg-white px-3 py-2 text-sm text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-2 focus:ring-teal-600/40"
            />
          </div>
          <div>
            <label className="mb-1.5 block text-sm font-medium text-text-primary">Follow-up date</label>
            <input
              type="date"
              value={followUpDate}
              onChange={(e) => setFollowUpDate(e.target.value)}
              className="w-full rounded-md border border-border-strong bg-white px-3 py-2 text-sm text-text-primary focus:outline-none focus:ring-2 focus:ring-teal-600/40"
            />
          </div>
          <div>
            <label className="mb-1.5 block text-sm font-medium text-text-primary">Assign to advisor</label>
            <Dropdown label="Select advisor" value={noteAdvisor} onSelect={setNoteAdvisor} options={advisorNames.map((a) => ({ label: a, value: a }))} />
          </div>
        </div>
      </Modal>
    </div>
  )
}
