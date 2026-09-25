import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react'
import { Megaphone, MessageCircle, Plus, Search, Send, Users } from 'lucide-react'
import { staff } from '@staff/data/mockData'
import {
  getMessageContacts,
  getMessages,
  markPortalMessagesRead,
  sendPortalMessage,
  type MessageContact,
  type PortalMessage,
} from '@/lib/portalGrades'

const broadcastContact: MessageContact = {
  type: 'staff',
  id: 'broadcast',
  name: 'All students',
  subtitle: 'Broadcast channel',
}

function messageTime(value: string) {
  const date = new Date(value)
  const today = new Date()
  return new Intl.DateTimeFormat('en', date.toDateString() === today.toDateString()
    ? { hour: 'numeric', minute: '2-digit' }
    : { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }).format(date)
}

function initials(name: string) {
  return name.split(/\s+/).slice(0, 2).map((part) => part[0]).join('').toUpperCase()
}

export default function Messages() {
  const [contacts, setContacts] = useState<MessageContact[]>([])
  const [messages, setMessages] = useState<PortalMessage[]>([])
  const [selected, setSelected] = useState<MessageContact | null>(null)
  const [query, setQuery] = useState('')
  const [draft, setDraft] = useState('')
  const [loading, setLoading] = useState(true)
  const [sending, setSending] = useState(false)
  const [error, setError] = useState('')

  const refresh = useCallback(async (quiet = false) => {
    if (!quiet) setLoading(true)
    try {
      const [contactResult, messageResult] = await Promise.all([
        getMessageContacts('staff', staff.staffId),
        getMessages('staff', staff.staffId),
      ])
      setContacts(contactResult.contacts)
      setMessages(messageResult.messages)
      setError('')
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : 'Messages could not be loaded.')
    } finally {
      if (!quiet) setLoading(false)
    }
  }, [])

  useEffect(() => {
    refresh()
    const timer = window.setInterval(() => refresh(true), 15000)
    return () => window.clearInterval(timer)
  }, [refresh])

  const messagesFor = useCallback((contact: MessageContact) => {
    if (contact.id === 'broadcast') return messages.filter((message) => message.is_broadcast)
    return messages.filter((message) => !message.is_broadcast && (
      (message.sender_type === 'student' && message.sender_id === contact.id)
      || (message.recipient_type === 'student' && message.recipient_id === contact.id)
    ))
  }, [messages])

  const visibleContacts = useMemo(() => {
    const normalized = query.trim().toLowerCase()
    const result = contacts.filter((contact) =>
      `${contact.name} ${contact.id} ${contact.subtitle}`.toLowerCase().includes(normalized))
    return result.sort((left, right) => {
      const leftTime = messagesFor(left).at(-1)?.created_at ?? ''
      const rightTime = messagesFor(right).at(-1)?.created_at ?? ''
      return rightTime.localeCompare(leftTime)
    })
  }, [contacts, messagesFor, query])

  const thread = selected ? messagesFor(selected) : []

  useEffect(() => {
    if (!selected) return
    const unread = messagesFor(selected)
      .filter((message) => !message.read && message.sender_type === 'student')
      .map((message) => message.message_id)
    if (!unread.length) return
    const unreadSet = new Set(unread)
    setMessages((current) => current.map((message) =>
      unreadSet.has(message.message_id) ? { ...message, read: true } : message))
    markPortalMessagesRead('staff', staff.staffId, unread).catch(() => refresh(true))
  }, [messagesFor, refresh, selected])

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (!selected || !draft.trim()) return
    setSending(true)
    try {
      await sendPortalMessage({
        sender_type: 'staff',
        sender_id: staff.staffId,
        ...(selected.id === 'broadcast'
          ? { is_broadcast: true }
          : { recipient_type: 'student' as const, recipient_id: selected.id }),
        body: draft.trim(),
      })
      setDraft('')
      await refresh(true)
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : 'Message could not be sent.')
    } finally {
      setSending(false)
    }
  }

  function conversationButton(contact: MessageContact, broadcast = false) {
    const contactMessages = messagesFor(contact)
    const latest = contactMessages.at(-1)
    const unread = contactMessages.filter((message) => !message.read && message.sender_type === 'student').length
    const active = selected?.id === contact.id
    return (
      <button
        key={contact.id}
        type="button"
        onClick={() => setSelected(contact)}
        className={`flex w-full items-center gap-3 rounded-xl border px-3 py-3 text-left transition-colors ${active
          ? 'border-teal-500 bg-teal-50'
          : 'border-transparent hover:border-border hover:bg-surface-sunk'}`}
      >
        <span className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-xl text-xs font-bold text-white ${broadcast ? 'bg-coral-500' : 'bg-teal-600'}`}>
          {broadcast ? <Megaphone className="h-5 w-5" /> : initials(contact.name)}
        </span>
        <span className="min-w-0 flex-1">
          <span className="flex items-baseline justify-between gap-2">
            <strong className="truncate text-sm text-text-primary">{contact.name}</strong>
            {latest && <time className="shrink-0 text-[10px] text-text-muted">{messageTime(latest.created_at)}</time>}
          </span>
          <span className="mt-1 block truncate text-xs text-text-muted">{latest?.body ?? contact.subtitle}</span>
        </span>
        {unread > 0 && <span className="flex h-5 min-w-5 items-center justify-center rounded-full bg-coral-500 px-1.5 text-[10px] font-bold text-white">{unread}</span>}
      </button>
    )
  }

  return (
    <div className="mx-auto flex h-[calc(100vh-8rem)] min-h-[560px] max-w-7xl flex-col">
      <div className="mb-5 flex items-end justify-between gap-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-teal-700">Student communication</p>
          <h1 className="mt-1 font-display text-3xl font-bold text-ink-900">Inbox</h1>
          <p className="mt-1 text-sm text-text-secondary">Message a student privately or send an update to everyone.</p>
        </div>
        <button type="button" onClick={() => { setSelected(broadcastContact); setDraft('') }} className="inline-flex items-center gap-2 rounded-lg bg-coral-500 px-4 py-2.5 text-sm font-semibold text-white shadow-card transition hover:bg-coral-600">
          <Megaphone className="h-4 w-4" /> New broadcast
        </button>
      </div>

      <div className="grid min-h-0 flex-1 grid-cols-1 overflow-hidden rounded-2xl border border-border bg-white shadow-card md:grid-cols-[340px_minmax(0,1fr)]">
        <aside className="flex min-h-0 flex-col border-b border-border bg-surface-raised p-4 md:border-b-0 md:border-r">
          <div className="relative mb-3">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted" />
            <input value={query} onChange={(event) => setQuery(event.target.value)} className="w-full rounded-lg border border-border bg-white py-2.5 pl-9 pr-3 text-sm outline-none focus:border-teal-500 focus:ring-2 focus:ring-teal-100" placeholder="Search students" />
          </div>
          <button type="button" onClick={() => setSelected(broadcastContact)} className="mb-2 flex items-center gap-2 rounded-lg border border-dashed border-coral-300 bg-coral-50 px-3 py-2.5 text-sm font-semibold text-coral-700 hover:bg-coral-100">
            <Plus className="h-4 w-4" /> Broadcast to all students
          </button>
          <div className="min-h-0 flex-1 space-y-1 overflow-y-auto">
            {messages.some((message) => message.is_broadcast) && conversationButton(broadcastContact, true)}
            {visibleContacts.map((contact) => conversationButton(contact))}
            {!loading && visibleContacts.length === 0 && <p className="px-4 py-8 text-center text-sm text-text-muted">No students match your search.</p>}
            {loading && <p className="px-4 py-8 text-center text-sm text-text-muted">Loading conversations…</p>}
          </div>
        </aside>

        <section className="flex min-h-0 flex-col">
          {selected ? (
            <>
              <header className="flex h-[76px] shrink-0 items-center gap-3 border-b border-border px-5">
                <span className={`flex h-11 w-11 items-center justify-center rounded-xl text-sm font-bold text-white ${selected.id === 'broadcast' ? 'bg-coral-500' : 'bg-teal-600'}`}>
                  {selected.id === 'broadcast' ? <Users className="h-5 w-5" /> : initials(selected.name)}
                </span>
                <div>
                  <h2 className="font-display text-lg font-bold text-ink-900">{selected.name}</h2>
                  <p className="text-xs text-text-muted">{selected.id === 'broadcast' ? 'Every registered student will receive this message' : `${selected.subtitle} · ${selected.id}`}</p>
                </div>
              </header>
              <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto bg-slate-50/70 p-5">
                {thread.length === 0 && (
                  <div className="m-auto text-center">
                    <MessageCircle className="mx-auto h-10 w-10 text-teal-300" />
                    <p className="mt-3 font-semibold text-text-primary">No messages yet</p>
                    <p className="mt-1 text-sm text-text-muted">Write the first message below.</p>
                  </div>
                )}
                {thread.map((message) => {
                  const outgoing = message.sender_type === 'staff' && message.sender_id === staff.staffId
                  return (
                    <article key={message.message_id} className={`max-w-[76%] rounded-2xl px-4 py-3 shadow-sm ${outgoing ? 'ml-auto rounded-tr-md bg-teal-700 text-white' : 'mr-auto rounded-tl-md border border-border bg-white text-text-primary'}`}>
                      <div className={`mb-1.5 flex items-baseline justify-between gap-6 text-xs ${outgoing ? 'text-white/75' : 'text-text-muted'}`}>
                        <strong>{outgoing ? 'You' : message.sender_name}</strong>
                        <time>{messageTime(message.created_at)}</time>
                      </div>
                      <p className="whitespace-pre-wrap text-sm leading-6">{message.body}</p>
                    </article>
                  )
                })}
              </div>
              <form onSubmit={submit} className="grid shrink-0 grid-cols-[minmax(0,1fr)_auto] gap-3 border-t border-border bg-white p-4">
                <textarea value={draft} onChange={(event) => setDraft(event.target.value)} rows={2} maxLength={4000} required placeholder={selected.id === 'broadcast' ? 'Write an announcement for all students…' : `Message ${selected.name.split(' ')[0]}…`} className="min-h-[54px] resize-none rounded-xl border border-border px-3.5 py-3 text-sm outline-none focus:border-teal-500 focus:ring-2 focus:ring-teal-100" />
                <button type="submit" disabled={sending || !draft.trim()} className="inline-flex min-w-24 items-center justify-center gap-2 rounded-xl bg-teal-700 px-4 text-sm font-semibold text-white disabled:cursor-not-allowed disabled:opacity-50">
                  <Send className="h-4 w-4" /> {sending ? 'Sending' : 'Send'}
                </button>
              </form>
            </>
          ) : (
            <div className="m-auto max-w-sm px-6 text-center">
              <span className="mx-auto flex h-16 w-16 items-center justify-center rounded-2xl bg-teal-50 text-teal-700"><MessageCircle className="h-8 w-8" /></span>
              <h2 className="mt-4 font-display text-xl font-bold text-ink-900">Your student conversations</h2>
              <p className="mt-2 text-sm leading-6 text-text-muted">Choose a student for a private message, or create a broadcast for everyone.</p>
            </div>
          )}
          {error && <p className="shrink-0 border-t border-error/20 bg-error-100 px-4 py-2 text-sm text-error">{error}</p>}
        </section>
      </div>
    </div>
  )
}
