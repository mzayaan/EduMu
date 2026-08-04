# SMS — what is actually free, and what we built

Researched 2 Aug 2026.

SMS matters more than the guardian portal. Portal adoption will never reach
every family; SMS is what gets read. That is why the queue was built early —
and why it sat undrained for months, because sending costs money and nobody
had chosen a provider.

---

## The honest position on "free"

There is **no permanent free tier for real SMS**. Everything marketed as free
is trial credit with an expiry.

| Provider | What you actually get | Usable for a demo? |
|---|---|---|
| **Twilio** | ~US$15 trial credit (~1,300 messages at 2026 US rates). Every message is prefixed *"Sent from your Twilio trial account"*, and a trial account can only send to **verified numbers, maximum 5** | **No.** Cannot demonstrate a broadcast to guardians |
| **Vonage** | Sandbox plus roughly €2 of credit, no card required | Barely |
| **Africa's Talking** | A genuine **free sandbox** that accepts sends and reports delivery without charging. Built for African markets, best local pricing when you do go live | **Yes**, for the mechanics |
| **textbee** | Open source. **Your own Android phone is the gateway** — messages cost whatever your SIM charges and nothing more | **Yes**, and it reaches real handsets |

For a portfolio, `console` is the right default. For a single pilot school,
textbee is the only route that puts a message on a real phone at no platform
cost.

## What we built

A provider interface in `apps/web/src/lib/sms.ts`. Nothing above that file
knows which provider is configured.

```
VITE_SMS_PROVIDER = console | africastalking | textbee
```

**`console`** (default) — logs and delivers nothing. Costs nothing, never
fails, works forever.

**`africastalking`** — set `VITE_AT_USERNAME=sandbox` for the free
environment.

```
VITE_SMS_PROVIDER=africastalking
VITE_AT_USERNAME=sandbox
VITE_AT_API_KEY=…
VITE_AT_SENDER_ID=…      # optional, needs registration for live
```

**`textbee`** — install the app on an Android handset, keep it on and online.

```
VITE_SMS_PROVIDER=textbee
VITE_TEXTBEE_API_KEY=…
VITE_TEXTBEE_DEVICE_ID=…
```

A misconfigured provider **falls back to `console`** rather than throwing. The
office must still be able to see its queue, and a broken provider must never
look like it delivered.

### `delivers` is load-bearing

Every adapter declares whether it puts a message on a real handset. The Outbox
screen reads that flag and says plainly when nothing was sent. A demo that
silently pretends to text parents about their child's absence would be a worse
lie than one that admits it.

## Details that cost money if you get them wrong

**Segments.** SMS bills per 160 characters — or **70** if any character falls
outside GSM-7. That includes accented French and the curly apostrophe a word
processor inserts. A message pasted from Word can quadruple the bill. The
Outbox shows the segment count and flags Unicode with a `U`.

**Mauritian numbers.** Local convention writes mobiles as `5XXX XXXX` with no
country code, so stored numbers are often 8 digits.
`normaliseMauritianNumber()` handles `+230…`, `230…` and bare `5XXXXXXX`, and
returns `null` for anything else. Rows with no usable number are shown greyed
and cannot be selected — better than silently skipping them.

**Personalisation.** Providers batch by identical body. Every message here
names a pupil, so the dispatcher sends **one at a time**. Batching would
deliver the first pupil's name to every parent — a data breach dressed as an
optimisation.

**Sender ID.** A Mauritian alphanumeric sender ID must be registered with the
operator. Until then messages arrive from a shortcode or pooled number, which
parents may not recognise or trust.

## Why the send button, and not a cron job

Dispatch is triggered from the Outbox screen. In a system that has never met a
real school, an automatic sender that quietly burns credit — or quietly stops —
is worse than one a person presses and watches.

Once a pilot is running, move the drain loop into a scheduled Edge Function.
The adapters do not change; only the caller does.

## Before real use

- [ ] Choose a provider and register a sender ID
- [ ] Move dispatch to a scheduled Edge Function with retry and backoff
- [ ] Handle delivery receipts — `notification.provider_ref` and
      `delivered_at` exist and nothing writes the latter
- [ ] Give guardians an opt-out, and honour it
- [ ] Decide quiet hours. An absence alert at 21:00 helps nobody
- [ ] Check message wording in Kreol and French, not only English

---

## Sources

- [Best free SMS gateway 2026 — what's actually free](https://textbee.dev/blog/free-sms-gateway)
- [Africa's Talking vs Twilio comparison](https://www.courier.com/integrations/compare/africas-talking-vs-twilio)
- [Top SMS providers for developers](https://knock.app/blog/the-top-sms-providers-for-developers)
- [Best SMS APIs 2026](https://www.textmagic.com/blog/best-sms-apis/)
