/**
 * SMS delivery — provider adapters.
 *
 * WHY THIS SHAPE
 * --------------
 * There is no permanent free tier for real SMS anywhere. What is marketed as
 * "free" is almost always trial credit with an expiry:
 *
 *   Twilio            ~US$15 trial credit. Every message is prefixed
 *                     "Sent from your Twilio trial account", and a trial
 *                     account can only reach verified numbers (max 5).
 *                     Unusable for demonstrating a broadcast to guardians.
 *   Vonage            Sandbox plus roughly €2 of credit.
 *   Africa's Talking  A genuine free sandbox that accepts sends and reports
 *                     delivery without charging. Built for African markets.
 *   textbee           Open source; your own Android phone is the gateway, so
 *                     messages cost whatever your SIM charges and nothing
 *                     more. The only genuinely free route to a real handset.
 *
 * So the provider is an interface, `console` is the default, and no code above
 * this file knows which one is configured. A portfolio demo runs on `console`
 * forever at zero cost; a pilot swaps one environment variable.
 *
 * WHAT THIS DOES NOT DO
 * ---------------------
 * Dispatch is triggered from the office screen rather than by a server-side
 * worker. That is a deliberate simplification for a system with no pilot: a
 * cron-driven sender that quietly burns credit — or quietly stops — is worse
 * than one a person presses. For real use, move the drain loop into an Edge
 * Function on a schedule and keep these adapters as they are.
 *
 * A Mauritian sender ID must be registered with the operator before real
 * traffic. Until then messages arrive from a shortcode or a pooled number.
 */

export type SmsProviderName = 'console' | 'africastalking' | 'textbee' | 'vonage'

export interface SmsMessage {
  /** E.164 where possible. Mauritian mobiles are +230 5XXXXXXX. */
  to: string
  body: string
  /** Our notification row, so a provider receipt can be traced back. */
  ref?: string
}

export interface SmsResult {
  ref?: string
  to: string
  ok: boolean
  /** The provider's own id, kept so a delivery report can be matched later. */
  providerRef?: string
  error?: string
}

export interface SmsProvider {
  name: SmsProviderName
  /** Whether this provider actually puts a message on a real handset. */
  readonly delivers: boolean
  send(messages: SmsMessage[]): Promise<SmsResult[]>
}

/**
 * Mauritian mobile numbers.
 *
 * Local convention writes them as 5XXX XXXX with no country code, so a stored
 * number is frequently 8 digits. Normalising here rather than at every call
 * site means one place is wrong if this is wrong.
 */
export function normaliseMauritianNumber(raw: string): string | null {
  const digits = raw.replace(/[^\d+]/g, '')
  if (digits.startsWith('+230')) return digits.length === 12 ? digits : null
  if (digits.startsWith('230')) return digits.length === 11 ? `+${digits}` : null
  // Bare local mobile: 8 digits beginning with 5.
  if (/^5\d{7}$/.test(digits)) return `+230${digits}`
  return null
}

/**
 * Default. Costs nothing, never fails, delivers nothing.
 *
 * `delivers: false` is load-bearing — the UI reads it to say plainly that
 * nothing was sent. A demo that silently pretends to text parents would be a
 * worse lie than one that admits it.
 */
export const consoleProvider: SmsProvider = {
  name: 'console',
  delivers: false,
  async send(messages) {
    for (const m of messages) {
      // eslint-disable-next-line no-console
      console.info(`[sms:console] → ${m.to}\n${m.body}`)
    }
    return messages.map((m) => ({
      ref: m.ref, to: m.to, ok: true, providerRef: `console-${Date.now()}`,
    }))
  },
}

/**
 * Africa's Talking. Set the username to `sandbox` for the free environment,
 * which accepts sends and reports delivery without charging.
 */
export function africasTalkingProvider(
  cfg: { username: string; apiKey: string; from?: string },
): SmsProvider {
  const sandbox = cfg.username === 'sandbox'
  const base = sandbox
    ? 'https://api.sandbox.africastalking.com/version1/messaging'
    : 'https://api.africastalking.com/version1/messaging'

  return {
    name: 'africastalking',
    delivers: !sandbox,
    async send(messages) {
      const body = new URLSearchParams({
        username: cfg.username,
        to: messages.map((m) => m.to).join(','),
        message: messages[0]?.body ?? '',
        ...(cfg.from ? { from: cfg.from } : {}),
      })

      try {
        const res = await fetch(base, {
          method: 'POST',
          headers: {
            apiKey: cfg.apiKey,
            'Content-Type': 'application/x-www-form-urlencoded',
            Accept: 'application/json',
          },
          body,
        })
        const json = (await res.json()) as {
          SMSMessageData?: { Recipients?: Array<{ number: string; status: string; messageId: string }> }
        }
        const recipients = json.SMSMessageData?.Recipients ?? []

        return messages.map((m) => {
          const r = recipients.find((x) => x.number === m.to)
          return {
            ref: m.ref, to: m.to,
            ok: r?.status === 'Success',
            providerRef: r?.messageId,
            error: r && r.status !== 'Success' ? r.status : undefined,
          }
        })
      } catch (e) {
        return messages.map((m) => ({
          ref: m.ref, to: m.to, ok: false,
          error: e instanceof Error ? e.message : String(e),
        }))
      }
    },
  }
}

/**
 * textbee — your own Android handset relays the messages.
 *
 * The only route here that reaches a real phone at no platform cost. Suits a
 * single school: throughput is one handset, and the phone has to stay on and
 * online. Not something to build a national rollout on.
 */
export function textbeeProvider(cfg: { apiKey: string; deviceId: string }): SmsProvider {
  return {
    name: 'textbee',
    delivers: true,
    async send(messages) {
      try {
        const res = await fetch(
          `https://api.textbee.dev/api/v1/gateway/devices/${cfg.deviceId}/send-sms`,
          {
            method: 'POST',
            headers: { 'x-api-key': cfg.apiKey, 'Content-Type': 'application/json' },
            body: JSON.stringify({
              recipients: messages.map((m) => m.to),
              message: messages[0]?.body ?? '',
            }),
          },
        )
        const ok = res.ok
        return messages.map((m) => ({
          ref: m.ref, to: m.to, ok,
          error: ok ? undefined : `HTTP ${res.status}`,
        }))
      } catch (e) {
        return messages.map((m) => ({
          ref: m.ref, to: m.to, ok: false,
          error: e instanceof Error ? e.message : String(e),
        }))
      }
    },
  }
}

/**
 * Chosen by environment. Anything unrecognised falls back to `console` rather
 * than throwing: a misconfigured provider must not stop the office seeing its
 * queue, and it must not silently look like it delivered.
 */
export function resolveProvider(env: ImportMetaEnv = import.meta.env): SmsProvider {
  const name = (env.VITE_SMS_PROVIDER ?? 'console') as SmsProviderName

  switch (name) {
    case 'africastalking':
      if (!env.VITE_AT_API_KEY) return consoleProvider
      return africasTalkingProvider({
        username: env.VITE_AT_USERNAME ?? 'sandbox',
        apiKey: env.VITE_AT_API_KEY,
        from: env.VITE_AT_SENDER_ID,
      })

    case 'textbee':
      if (!env.VITE_TEXTBEE_API_KEY || !env.VITE_TEXTBEE_DEVICE_ID) return consoleProvider
      return textbeeProvider({
        apiKey: env.VITE_TEXTBEE_API_KEY,
        deviceId: env.VITE_TEXTBEE_DEVICE_ID,
      })

    default:
      return consoleProvider
  }
}

/**
 * SMS is charged per 160-character segment (70 if any character is outside
 * GSM-7 — which includes the curly apostrophes a word processor inserts, and
 * most accented French). Worth showing the office before they send 800 of them.
 */
export function segmentCount(body: string): { segments: number; unicode: boolean } {
  const unicode = /[^\x00-\x7F]/.test(body)
  const limit = unicode ? 70 : 160
  const multi = unicode ? 67 : 153
  if (body.length <= limit) return { segments: 1, unicode }
  return { segments: Math.ceil(body.length / multi), unicode }
}
