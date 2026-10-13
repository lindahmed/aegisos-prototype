import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'

interface TooltipState {
  label: string
  left: number
  top: number
}

export function useIconNavTooltip() {
  const [tooltip, setTooltip] = useState<TooltipState | null>(null)
  const timer = useRef<number | null>(null)

  useEffect(() => () => {
    if (timer.current !== null) window.clearTimeout(timer.current)
  }, [])

  function hide() {
    if (timer.current !== null) window.clearTimeout(timer.current)
    timer.current = null
    setTooltip(null)
  }

  function show(element: HTMLElement, label: string, temporary = false) {
    if (timer.current !== null) window.clearTimeout(timer.current)
    const rect = element.getBoundingClientRect()
    setTooltip({
      label,
      left: Math.max(80, Math.min(window.innerWidth - 80, rect.left + rect.width / 2)),
      top: rect.bottom + 8,
    })
    timer.current = temporary ? window.setTimeout(hide, 2400) : null
  }

  const tooltipNode = tooltip ? createPortal(
    <span
      aria-hidden="true"
      className="pointer-events-none fixed z-[100] max-w-[calc(100vw-1rem)] -translate-x-1/2 rounded-md bg-ink-900 px-3 py-1.5 text-xs font-semibold text-white shadow-lg"
      style={{ left: tooltip.left, top: tooltip.top }}
    >
      {tooltip.label}
    </span>,
    document.body,
  ) : null

  return { show, hide, tooltipNode }
}
