/** Mauritius conventions: dd/mm/yyyy, Indian/Mauritius (UTC+4, no DST). */
export const TZ = 'Indian/Mauritius'

export function formatDate(d: Date | string, locale = 'en-GB') {
  const date = typeof d === 'string' ? new Date(d + 'T00:00:00') : d
  return new Intl.DateTimeFormat(locale, {
    day: '2-digit', month: '2-digit', year: 'numeric', timeZone: TZ,
  }).format(date)
}

export function formatLongDate(d: Date | string, locale = 'en-GB') {
  const date = typeof d === 'string' ? new Date(d + 'T00:00:00') : d
  return new Intl.DateTimeFormat(locale, {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: TZ,
  }).format(date)
}

/** Today in Mauritius, as an ISO date string, regardless of device timezone. */
export function todayInMauritius(): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(new Date())
  return parts
}

export function displayName(p: {
  first_name: string; last_name: string; preferred_name?: string | null
}) {
  return `${p.last_name.toUpperCase()}, ${p.preferred_name || p.first_name}`
}
