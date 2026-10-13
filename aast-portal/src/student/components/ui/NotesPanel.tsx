import { useEffect, useMemo, useState } from 'react'
import { FileText, Plus, Trash2 } from 'lucide-react'
import Card from '@student/components/ui/Card'

type Note = { id: string; title: string; body: string; updatedAt: number }

function storageKey(studentId: string) {
  return `aegisos:student-notes:${studentId}`
}

function readNotes(studentId: string): Note[] {
  try {
    const stored: unknown = JSON.parse(localStorage.getItem(storageKey(studentId)) ?? '[]')
    if (!Array.isArray(stored)) return []
    return stored.filter((note): note is Note =>
      note && typeof note.id === 'string' && typeof note.title === 'string' &&
      typeof note.body === 'string' && typeof note.updatedAt === 'number',
    )
  } catch {
    return []
  }
}

export default function NotesPanel({ studentId }: { studentId: string }) {
  const [notes, setNotes] = useState<Note[]>(() => readNotes(studentId))
  const [selectedId, setSelectedId] = useState<string | null>(() => readNotes(studentId)[0]?.id ?? null)
  const selected = useMemo(() => notes.find((note) => note.id === selectedId) ?? null, [notes, selectedId])

  useEffect(() => {
    localStorage.setItem(storageKey(studentId), JSON.stringify(notes))
  }, [notes, studentId])

  function updateSelected(field: 'title' | 'body', value: string) {
    if (!selectedId) return
    setNotes((current) => current.map((note) => note.id === selectedId
      ? { ...note, [field]: value, updatedAt: Date.now() }
      : note))
  }

  function createNote() {
    const note = { id: crypto.randomUUID(), title: 'New Note', body: '', updatedAt: Date.now() }
    setNotes((current) => [note, ...current])
    setSelectedId(note.id)
  }

  function deleteSelected() {
    if (!selected) return
    const remaining = notes.filter((note) => note.id !== selected.id)
    setNotes(remaining)
    setSelectedId(remaining[0]?.id ?? null)
  }

  return (
    <Card padded={false} className="mb-6 overflow-hidden">
      <div className="flex items-center justify-between border-b border-border px-5 py-4">
        <div className="flex items-center gap-2.5">
          <FileText className="h-4 w-4 text-teal-600" />
          <h2 className="font-display text-base font-semibold text-text-primary">Notes</h2>
          <span className="text-xs text-text-muted">{notes.length}</span>
        </div>
        <button type="button" onClick={createNote} className="inline-flex items-center gap-1.5 rounded-md bg-teal-700 px-3 py-2 text-sm font-semibold text-white hover:bg-teal-800">
          <Plus className="h-4 w-4" /> New Note
        </button>
      </div>

      <div className="grid min-h-64 md:grid-cols-[220px_1fr]">
        <div className="max-h-72 overflow-y-auto border-b border-border md:border-b-0 md:border-r">
          {notes.length === 0 ? (
            <p className="px-4 py-6 text-center text-sm text-text-secondary">Your notes will appear here.</p>
          ) : notes.map((note) => (
            <button key={note.id} type="button" onClick={() => setSelectedId(note.id)} className={`block w-full border-b border-border px-4 py-3 text-left hover:bg-surface-sunk/60 ${selectedId === note.id ? 'bg-teal-50' : ''}`}>
              <span className="block truncate text-sm font-semibold text-text-primary">{note.title || 'New Note'}</span>
              <span className="mt-1 block truncate text-xs text-text-secondary">{note.body || 'No additional text'}</span>
              <span className="mt-1 block text-[11px] text-text-muted">{new Date(note.updatedAt).toLocaleDateString()}</span>
            </button>
          ))}
        </div>

        {selected ? (
          <div className="flex min-h-64 flex-col p-4">
            <div className="mb-3 flex items-center gap-2">
              <input aria-label="Note title" value={selected.title} onChange={(event) => updateSelected('title', event.target.value)} className="min-w-0 flex-1 border-0 bg-transparent text-lg font-semibold text-text-primary outline-none placeholder:text-text-muted focus:ring-0" placeholder="Title" />
              <button type="button" onClick={deleteSelected} aria-label="Delete note" title="Delete note" className="rounded-md p-2 text-text-muted hover:bg-red-50 hover:text-red-600">
                <Trash2 className="h-4 w-4" />
              </button>
            </div>
            <textarea aria-label="Note text" value={selected.body} onChange={(event) => updateSelected('body', event.target.value)} placeholder="Write anything you want…" className="min-h-48 flex-1 resize-y border-0 bg-transparent text-sm leading-6 text-text-primary outline-none placeholder:text-text-muted focus:ring-0" />
          </div>
        ) : (
          <div className="flex min-h-64 flex-col items-center justify-center px-6 text-center">
            <FileText className="mb-2 h-7 w-7 text-text-muted" />
            <p className="text-sm text-text-secondary">Select a note or create one to get started.</p>
          </div>
        )}
      </div>
    </Card>
  )
}
