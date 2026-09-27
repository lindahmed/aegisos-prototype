import { API_BASE_URL } from '@/lib/portalGrades'
import { supabase } from '@/lib/supabaseClient'

// PDF files live on a separate service; academic/student data keeps its original API.
const PDF_API_BASE_URL = import.meta.env.VITE_PDF_API_BASE_URL?.replace(/\/+$/, '') || API_BASE_URL

export interface PortalPdf {
  pdf_id: string
  instructor_id: string
  course_id: string | null
  course_name: string | null
  title: string
  description: string | null
  original_filename: string
  size_bytes: number
  uploaded_at: string
}

export interface InstructorCourse {
  course_id: string
  course_name: string
}

async function authenticatedRequest(path: string, init?: RequestInit): Promise<Response> {
  const { data: { session }, error } = await supabase.auth.getSession()
  if (error || !session?.access_token) throw new Error('Your session expired. Please sign in again.')
  let response: Response
  try {
    response = await fetch(`${PDF_API_BASE_URL}${path}`, {
      ...init,
      headers: { ...init?.headers, Authorization: `Bearer ${session.access_token}` },
    })
  } catch {
    throw new Error('PDF service is unavailable. Please try again when the file server is running.')
  }
  if (!response.ok) {
    const payload = await response.json().catch(() => null) as { detail?: string } | null
    throw new Error(payload?.detail ?? `Request failed (${response.status})`)
  }
  return response
}

export async function getInstructorCourses(): Promise<InstructorCourse[]> {
  const response = await authenticatedRequest('/portal/pdfs/staff/courses')
  return (await response.json() as { courses: InstructorCourse[] }).courses
}

export async function getStaffPdfs(): Promise<PortalPdf[]> {
  const response = await authenticatedRequest('/portal/pdfs/staff')
  return (await response.json() as { pdfs: PortalPdf[] }).pdfs
}

export async function getStudentPdfs(): Promise<PortalPdf[]> {
  const response = await authenticatedRequest('/portal/pdfs/student')
  return (await response.json() as { pdfs: PortalPdf[] }).pdfs
}

export async function uploadStaffPdf(input: {
  file: File
  title: string
  description: string
  courseId: string
}): Promise<PortalPdf> {
  const body = new FormData()
  body.append('file', input.file)
  body.append('title', input.title)
  body.append('description', input.description)
  body.append('course_id', input.courseId)
  const response = await authenticatedRequest('/portal/pdfs/staff', { method: 'POST', body })
  return (await response.json() as { pdf: PortalPdf }).pdf
}

export async function deleteStaffPdf(pdfId: string): Promise<void> {
  await authenticatedRequest(`/portal/pdfs/staff/${encodeURIComponent(pdfId)}`, { method: 'DELETE' })
}

export async function openPortalPdf(pdf: PortalPdf, role: 'staff' | 'student', download: boolean): Promise<void> {
  const preview = download ? null : window.open('', '_blank')
  try {
    const response = await authenticatedRequest(
      `/portal/pdfs/${role}/${encodeURIComponent(pdf.pdf_id)}/file${download ? '?download=true' : ''}`,
    )
    const url = URL.createObjectURL(await response.blob())
    if (download) {
      const link = document.createElement('a')
      link.href = url
      link.download = pdf.original_filename
      document.body.append(link)
      link.click()
      link.remove()
      window.setTimeout(() => URL.revokeObjectURL(url), 60_000)
    } else if (preview) {
      preview.opener = null
      preview.location.href = url
      window.setTimeout(() => URL.revokeObjectURL(url), 300_000)
    } else {
      URL.revokeObjectURL(url)
      throw new Error('Allow pop-ups to open the PDF.')
    }
  } catch (error) {
    preview?.close()
    throw error
  }
}
