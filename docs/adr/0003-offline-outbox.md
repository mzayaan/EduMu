# 3. Offline-first for attendance, via an outbox

**Status** Accepted · 2026-08-01

## Context
Registers are taken in corridors and classrooms. Mauritian school buildings have
patchy Wi-Fi, and a teacher standing in front of thirty pupils will not wait for
a spinner or retype a register.

## Decision
Attendance and lesson marks are written to an IndexedDB outbox first, applied
optimistically, and drained on reconnect. Every entry carries a natural key, so
the server write is an idempotent upsert and a replay is harmless. Repeat taps
on the same pupil collapse to one entry.

Conflict policy: last-write-wins with an audit entry. Not CRDTs — attendance
conflicts are rare, human-scale and human-resolvable.

## Consequences
- Failures must be visible. A sync badge shows offline/pending/synced state,
  because a teacher needs to know whether the register actually left the phone.
- Entries that fail 5 times are dropped rather than blocking the queue — a 4xx
  from RLS will never succeed on retry.
- The outbox key is versioned (`edumu.outbox.v2`); changing the payload shape
  requires bumping it.
