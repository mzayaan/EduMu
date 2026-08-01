import { useEffect, useState } from 'react'
import { onOutboxChange, pendingCount } from '@/lib/outbox'

/**
 * Visible sync state. A teacher who marked a register in a dead spot needs to
 * know, without asking, whether it actually left the phone.
 */
export function SyncBadge() {
  const [pending, setPending] = useState(0)
  const [online, setOnline] = useState(navigator.onLine)

  useEffect(() => {
    void pendingCount().then(setPending)
    const off = onOutboxChange(setPending)
    const on = () => setOnline(true)
    const down = () => setOnline(false)
    window.addEventListener('online', on)
    window.addEventListener('offline', down)
    return () => {
      off()
      window.removeEventListener('online', on)
      window.removeEventListener('offline', down)
    }
  }, [])

  if (online && pending === 0) {
    return <span className="rounded-full bg-green-50 px-2.5 py-1 text-xs font-medium text-green-700">Synced</span>
  }
  if (!online) {
    return (
      <span className="rounded-full bg-amber-50 px-2.5 py-1 text-xs font-medium text-amber-800">
        Offline{pending > 0 ? ` · ${pending} pending` : ''}
      </span>
    )
  }
  return (
    <span className="rounded-full bg-blue-50 px-2.5 py-1 text-xs font-medium text-blue-700">
      Syncing {pending}…
    </span>
  )
}
