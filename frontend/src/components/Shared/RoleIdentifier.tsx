import { useEffect, useRef, useState, type ReactNode, type ButtonHTMLAttributes } from 'react'
import { Check, Copy, ArrowUpRight } from 'lucide-react'

/** SAP identifiers are rendered as one unbroken string: no characters are inserted, copy writes the exact value. */
export const identifierFragments = (value: string) => value

/**
 * BUG-09 (reopened): an identifier is one line inside its own box. When the container is narrower than the name, the name truncates with an
 * ellipsis (CSS); the full value stays in the tooltip and is what Copy writes. No font scaling and no container scrolling: both changed the
 * geometry while a sidebar opened or closed and made the surrounding container scroll.
 */
interface RoleIdentifierProps {
  separateOpenAction?: boolean
  action?: ReactNode
  moduleId?: string | null
  value: string
  label?: string
  onOpen?: () => void
  /** With a href the open control is a real link: modified clicks open a new tab, a plain click calls onOpen. */
  href?: string
  openLabel?: string
  openButtonProps?: ButtonHTMLAttributes<HTMLButtonElement> & { 'data-user'?: string }
}

export function RoleIdentifier({ separateOpenAction = false, action, moduleId: _moduleId, value, label = 'role identifier', onOpen, href, openLabel, openButtonProps }: RoleIdentifierProps) {
  const [message, setMessage] = useState('')
  const timer = useRef<ReturnType<typeof setTimeout>>()
  useEffect(() => () => clearTimeout(timer.current), [])
  return (
    <span
      className="role-identifier"
      data-np
      data-copied={message === 'Copied'}
      onClick={(e) => e.stopPropagation()}
    >
      {onOpen && href ? <a href={href} className="role-identifier-link" aria-label={openLabel || `Open ${value}`} data-user={openButtonProps?.['data-user']} onClick={(event) => { event.stopPropagation(); if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return; event.preventDefault(); onOpen() }}><code title={value} tabIndex={-1}>{identifierFragments(value)}</code>{!separateOpenAction&&<ArrowUpRight size={14} aria-hidden="true" className="shrink-0"/>}</a>
        : onOpen ? <button {...openButtonProps} type="button" className="role-identifier-link" aria-label={openLabel || `Open ${value}`} onClick={event=>{event.stopPropagation();onOpen()}}><code title={value} tabIndex={-1}>{identifierFragments(value)}</code>{!separateOpenAction&&<ArrowUpRight size={14} aria-hidden="true" className="shrink-0"/>}</button> : <code title={value} tabIndex={-1}>{identifierFragments(value)}</code>}
      {separateOpenAction && onOpen && (href
        ? <a href={href} className="inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-control hover:bg-hover focus-visible:outline focus-visible:outline-focus" aria-label={`Open user details for ${value}`} onClick={event=>{event.stopPropagation();if(event.button!==0||event.ctrlKey||event.metaKey||event.shiftKey||event.altKey)return;event.preventDefault();onOpen()}}><ArrowUpRight size={14} aria-hidden="true"/></a>
        : <button type="button" aria-label={`Open user details for ${value}`} disabled={openButtonProps?.disabled} onClick={event=>{event.stopPropagation();onOpen()}}><ArrowUpRight size={14} aria-hidden="true"/></button>)}
      <button
        type="button"
        aria-label={`Copy ${label} ${value}`}
        onClick={async (event) => {
          event.stopPropagation()
          clearTimeout(timer.current)
          try {
            await navigator.clipboard.writeText(value)
            setMessage('Copied')
          } catch {
            setMessage('Copy failed. Select the identifier to copy manually.')
          }
          timer.current = setTimeout(() => setMessage(''), 2000)
        }}
      >
        {message === 'Copied' ? (
          <Check size={14} aria-hidden="true" />
        ) : (
          <Copy size={14} aria-hidden="true" />
        )}
      </button>
      {action}
      <span className="role-copy-feedback" role="status">
        {message}
      </span>
    </span>
  )
}
