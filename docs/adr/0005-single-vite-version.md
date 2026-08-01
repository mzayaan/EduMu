# 5. Pin one Vite version across the workspace

**Status** Accepted · 2026-08-01

## Context
npm workspaces hoisted Vite 5 (pulled in by Vitest 2) to the root while nesting
Vite 6 under `apps/web`. `@vitejs/plugin-react` then resolved its `Plugin` type
against one copy and the config against the other, producing a 200-line
structurally-identical-types error that says nothing about the real cause.

## Decision
Vitest 3 (which supports Vite 6), plus `overrides: { vite: "^6.4.3" }` at the
root as a guarantee that nothing re-nests a second copy.

## Consequences
- One Vite in the tree. The type error class cannot recur.
- It also removed all five npm audit advisories, which lived in the Vite 5
  dependency chain — they were never patched, the vulnerable copy just stopped
  existing.
- Upgrading Vite means upgrading the override and Vitest together.
- Requires a clean reinstall: `overrides` will not dislodge an already-nested
  copy.
