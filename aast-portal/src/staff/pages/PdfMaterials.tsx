import { useEffect, useState, type FormEvent } from 'react'
import { Download, Eye, FileText, Trash2, Upload } from 'lucide-react'
import {
  deleteStaffPdf, getInstructorCourses, getStaffPdfs, openPortalPdf, uploadStaffPdf,
  type InstructorCourse, type PortalPdf,
} from '@/lib/portalPdfs'
import PageHeader from '@staff/components/layout/PageHeader'
import Card from '@staff/components/ui/Card'
import Button from '@staff/components/ui/Button'
import EmptyState from '@staff/components/ui/EmptyState'
import { useToast } from '@staff/components/ui/Toast'

export default function PdfMaterials() {
  const [courses, setCourses] = useState<InstructorCourse[]>([])
  const [pdfs, setPdfs] = useState<PortalPdf[]>([])
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [courseId, setCourseId] = useState('')
  const [file, setFile] = useState<File | null>(null)
  const [inputKey, setInputKey] = useState(0)
  const [loading, setLoading] = useState(true)
  const [uploading, setUploading] = useState(false)
  const [deletingId, setDeletingId] = useState<string | null>(null)
  const [error, setError] = useState('')
  const { showToast } = useToast()

  useEffect(() => {
    let active = true
    Promise.all([getInstructorCourses(), getStaffPdfs()])
      .then(([nextCourses, nextPdfs]) => {
        if (active) { setCourses(nextCourses); setPdfs(nextPdfs) }
      })
      .catch((err: Error) => { if (active) setError(err.message) })
      .finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [])

  async function upload(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!file || !title.trim() || !courseId) { setError('Choose a course, PDF, and title.'); return }
    if (file.size > 10 * 1024 * 1024 || !file.name.toLowerCase().endsWith('.pdf')) {
      setError('Choose a PDF file no larger than 10 MB.')
      return
    }
    setUploading(true)
    setError('')
    try {
      const added = await uploadStaffPdf({ file, title: title.trim(), description: description.trim(), courseId })
      setPdfs((current) => [{ ...added, course_name: courses.find((c) => c.course_id === courseId)?.course_name ?? null }, ...current])
      setTitle(''); setDescription(''); setCourseId(''); setFile(null); setInputKey((key) => key + 1)
      showToast('PDF uploaded. Eligible students can see it now.')
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Upload failed.'
      setError(message)
      showToast(message, 'error')
    } finally { setUploading(false) }
  }

  async function remove(pdf: PortalPdf) {
    if (!window.confirm(`Delete “${pdf.title}”? Students will lose access.`)) return
    setDeletingId(pdf.pdf_id)
    setError('')
    try {
      await deleteStaffPdf(pdf.pdf_id)
      setPdfs((current) => current.filter((item) => item.pdf_id !== pdf.pdf_id))
      showToast('PDF deleted.')
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Could not delete PDF.'
      setError(message)
      showToast(message, 'error')
    } finally { setDeletingId(null) }
  }

  async function fileAction(pdf: PortalPdf, download: boolean) {
    try { await openPortalPdf(pdf, 'staff', download) }
    catch (err) { showToast(err instanceof Error ? err.message : 'Could not open PDF.', 'error') }
  }

  return <div>
    <PageHeader title="Course Materials" crumbs={[{ label: 'Course Materials' }]} description="Share PDF resources with students." />
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
      <Card className="lg:col-span-1">
        <h2 className="mb-4 font-display text-lg font-semibold text-text-primary">Upload a PDF</h2>
        <form onSubmit={upload} className="space-y-4">
          <label className="block text-sm font-medium text-text-primary">Title
            <input value={title} onChange={(event) => setTitle(event.target.value)} maxLength={160} required className="mt-1 w-full rounded-md border border-border-strong bg-white px-3 py-2 text-sm" />
          </label>
          <label className="block text-sm font-medium text-text-primary">Description (optional)
            <textarea value={description} onChange={(event) => setDescription(event.target.value)} maxLength={2000} rows={3} className="mt-1 w-full rounded-md border border-border-strong bg-white px-3 py-2 text-sm" />
          </label>
          <label className="block text-sm font-medium text-text-primary">Audience
            <select value={courseId} onChange={(event) => setCourseId(event.target.value)} required className="mt-1 w-full rounded-md border border-border-strong bg-white px-3 py-2 text-sm">
              <option value="" disabled>Select a course</option>
              {courses.map((course) => <option key={course.course_id} value={course.course_id}>{course.course_id} · {course.course_name}</option>)}
            </select>
          </label>
          <label className="block text-sm font-medium text-text-primary">PDF file (maximum 10 MB)
            <input key={inputKey} type="file" accept=".pdf,application/pdf" required onChange={(event) => setFile(event.target.files?.[0] ?? null)} className="mt-1 block w-full text-sm text-text-secondary" />
          </label>
          <Button type="submit" loading={uploading} icon={<Upload className="h-4 w-4" />}>Upload PDF</Button>
        </form>
      </Card>
      <div className="lg:col-span-2">
        <h2 className="mb-3 font-display text-lg font-semibold text-text-primary">My PDFs</h2>
        {loading ? <p className="text-sm text-text-secondary" role="status">Loading PDFs…</p> : pdfs.length === 0 ?
          <EmptyState icon={<FileText className="h-5 w-5" />} title="No PDFs uploaded" description="Upload one to share it with students." /> :
          <div className="space-y-3">{pdfs.map((pdf) => <Card key={pdf.pdf_id}>
            <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div className="min-w-0">
                <p className="font-medium text-text-primary">{pdf.title}</p>
                {pdf.description && <p className="mt-1 text-sm text-text-secondary">{pdf.description}</p>}
                <p className="mt-2 text-xs text-text-muted">{pdf.course_name ?? 'All students'} · {new Date(pdf.uploaded_at).toLocaleDateString()} · {(pdf.size_bytes / 1024).toFixed(0)} KB</p>
              </div>
              <div className="flex flex-wrap gap-2">
                <Button size="sm" variant="secondary" icon={<Eye className="h-3.5 w-3.5" />} onClick={() => void fileAction(pdf, false)}>View</Button>
                <Button size="sm" variant="secondary" icon={<Download className="h-3.5 w-3.5" />} onClick={() => void fileAction(pdf, true)}>Download</Button>
                <Button size="sm" variant="danger" disabled={deletingId === pdf.pdf_id} icon={<Trash2 className="h-3.5 w-3.5" />} onClick={() => void remove(pdf)}>Delete</Button>
              </div>
            </div>
          </Card>)}</div>}
      </div>
    </div>
    {error && <p role="alert" className="mt-4 rounded-md border border-error/30 bg-red-50 px-4 py-3 text-sm text-error">{error}</p>}
  </div>
}
