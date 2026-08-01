# Consequence API — project plan

Status: planning complete, pre-implementation
Owner: Zayaan
Last updated: 2026-08-01

---

## 0. Read this first

Two findings from verification change the shape of this project. Both are good news, but only if you act on them.

**Finding 1 — all six citations in the KILLCRITIC brief are real.** I fetched each one. Nothing was hallucinated. Full audit in §1.

**Finding 2 — the "Action Passport" already exists, under almost that name.** arXiv 2603.20953 (Uchibeke, March 2026) presents the **Open Agent Passport (OAP)**: an open specification and reference implementation that intercepts tool calls synchronously before execution, evaluates them against a declarative policy, and emits a cryptographically signed record. Median 53 ms over N=1,000. Apache 2.0. That is, line for line, the "signed Action Passport service + deterministic policy engine" in your architecture diagram.

If you build what the brief describes and present it as novel, the first informed reviewer who searches the phrase will find OAP and the project loses all credibility at once. That is the single largest risk to this portfolio piece, and it is entirely avoidable.

The rest of this plan repositions the work so that the overlap becomes an asset — you are building on a cited, dated prior art baseline rather than accidentally reinventing it — and identifies a real, unclaimed gap worth owning.

---

## 1. Citation audit

| # | Claim in brief | Status | What it actually says |
|---|---|---|---|
| 1 | arXiv 2607.13718 — "How Agents Ask for Permission" | **Verified** | Michael & Roesner, 15 Jul 2026. Surveys 21 agent-permission proposals, builds a taxonomy of specification / derivation / runtime enforcement, analyses 5 commercial agents, names the remaining gaps. |
| 2 | modelcontextprotocol.io | **Verified** | MCP provides connectivity and authorization, not consequence semantics. Your framing here is fair. |
| 3 | arXiv 2604.23280 — "AI Identity: Standards, Gaps, and Research Directions" | **Verified** | Resolves to the stated title. |
| 4 | arXiv 2606.22916 — "Intent-Governed Tool Authorization for AI Agents" | **Verified** | Resolves to the stated title. Intent matching as an authorization primitive is already claimed territory. |
| 5 | arXiv 2604.23283 — "Revisable by Design" | **Verified** | Resolves to the stated title. Reversibility taxonomy is already claimed territory. |
| 6 | NIST NCCoE concept paper | **Verified** | "Accelerating the Adoption of Software and AI Agent Identity and Authorization", published 5 Feb 2026, comment period closed 2 Apr 2026. Proposes a demonstration using OAuth 2.0, SPIFFE/SPIRE and MCP. |
| 7 | arXiv 2603.20953 — "Before the Tool Call" | **Verified — and it is your closest competitor** | See §0. Open Agent Passport. Signed pre-action authorization, deterministic policy, 53 ms median, live adversarial testbed with a $5,000 bounty: 74.6% social-engineering success under permissive policy vs. 0% across 879 attempts under restrictive OAP policy. |

Action: cite all seven in the repo. A portfolio project that positions itself accurately against dated prior art reads as far more sophisticated than one that claims a clean field.

---

## 2. What is actually still unclaimed

Walk the five "intelligence layers" from the brief against the literature:

| Layer | Prior art | Verdict |
|---|---|---|
| 1. Intent matching | arXiv 2606.22916 | Claimed |
| 2. Consequence prediction | Partial — no strong single owner | **Partly open** |
| 3. Reversibility classification | arXiv 2604.23283 | Claimed |
| 4. Affected-party / consent detection | Weak coverage | **Open, but hardest to evaluate** |
| 5. Safe alternative generation | Weak coverage | **Open** |
| Signed passports + deterministic enforcement | arXiv 2603.20953 (OAP) | Claimed |
| Taxonomy of permission systems | arXiv 2607.13718 | Claimed |

Building "all five layers plus passports" is therefore a systems-integration exercise on top of a field where most components have a paper. That is a fine engineering project. It is not a contribution.

**But there is a gap sitting in plain sight, and it is in OAP's own headline result.**

OAP reports 0% attacker success under a restrictive policy. It does not report *how many legitimate actions that restrictive policy blocked*. This is the oldest tradeoff in security engineering: any sufficiently restrictive policy achieves a 0% attack rate, including `deny *`. The number that determines whether a guardrail survives contact with real developers is the **false-positive rate on benign traffic**, and the field is not reporting it.

Your own brief names this — "false positives could destroy adoption" — and then files it under weaknesses. It is not a weakness. It is the thesis.

### The repositioned claim

> Pre-action authorization for AI agents is measured almost entirely by attack-prevention rate. That metric is trivially gameable by tightening policy. This project contributes **AgentPreflight-Bench**, an open benchmark of paired benign and dangerous developer-tool actions, and uses it to characterise the security/friction frontier that existing systems leave unreported — then shows that a hybrid deterministic + semantic classifier moves that frontier.

This is defensible to every audience you named:

- **Engineering hiring managers** — you found the unmeasured metric, built the dataset, and did the measurement. This is senior-level judgement, not tutorial-following.
- **Research admissions** — benchmark + empirical study + honest baseline comparison against a named prior system is a workshop paper shape.
- **Investors** — "the incumbent approach has an unquantified false-positive problem and I have the data" is a wedge.

---

## 3. Scope

### In scope (v1)

One surface only: **destructive developer-tool actions**.

Six action families, chosen because ground truth is objectively determinable:

1. Shell commands (`rm`, `dd`, `chmod`, `mv`, redirect-truncation)
2. Git operations (`push --force`, `reset --hard`, branch deletion, history rewrite)
3. SQL/DDL (`DROP`, `TRUNCATE`, unbounded `DELETE`/`UPDATE`)
4. Cloud storage / infra (bucket deletion, public-ACL changes, `terraform destroy`)
5. Package & dependency (publish, unpublish, version yank)
6. Secret exposure (committing credentials, making a repo public)

### Explicitly out of scope — and say so in the README

- Email, calendar, payments, healthcare, IoT, robotics, government
- "Affected party" and consent detection for photos or meetings
- Cross-agent consequence exchange
- Any claim of general consequence prediction
- The `/simulate`, `/outcomes`, `/policies/evaluate`, `/actions/explain` endpoints

The brief lists ten domains and eight endpoints. Shipping two domains well beats sketching ten. A visible, reasoned non-goals list is one of the strongest credibility signals a portfolio project can carry — it demonstrates you can distinguish a roadmap from a product.

### Renaming

Drop "Consequence API" as the primary name. It promises prediction you cannot deliver and invites the "you can't predict the future" objection before anyone reads a line of code. Suggested: **Preflight** (system) + **AgentPreflight-Bench** (benchmark). Frame it as *risk classification and policy enforcement*, never *consequence prediction*.

---

## 3.5 The arena — the centrepiece

**Name: Breakroom.** A public, playable red-team arena. Two modes, one environment, one policy engine.

### Attacker mode

You are dropped into a chat with an agent that has real tools — shell, git, SQL — pointed at a simulated production system. Your goal is to talk the agent into executing a destructive action. Preflight sits between the agent and the tools. You win if a destructive call actually executes.

Every attempt logs: your prompt, the agent's proposed tool call, the preflight verdict with rationale, and the outcome. Live scoreboard.

### Operator mode

Same environment, same agent, same policy. But now you are given a **legitimate** job — "clean up the stale feature branches", "drop the abandoned import scratch tables", "free up disk on the build box". You succeed by completing it.

Every time Preflight blocks or interrupts you doing something you were *supposed* to do, that is a logged false positive.

### Why the two modes together are the contribution

This is the part that makes the whole project cohere.

Run both modes across a ladder of policy strictness — permissive, moderate, restrictive, paranoid. At each rung you measure:

- attacker success rate (from attacker mode)
- benign task completion rate and interruption count (from operator mode)

Those are exactly the two axes of the frontier chart. Which means:

> **The arena isn't a demo of the research. The arena *is* the instrument that produces the research.** You are measuring the security/friction frontier with real human adversaries and real human operators, at multiple policy settings, in one system.

Nobody has that. OAP ran adversaries against a restrictive policy and reported 0% success; they had no operator arm, so the cost of that policy is unknown. Adding the operator arm is a small engineering delta and a large scientific one.

It also solves the benchmark's weakest point. §4 originally asks you to hand-label 1,200 actions alone, with a shaky kappa. The arena replaces synthetic labels with observed human behaviour on both sides. Keep a hand-labelled seed set for regression testing, but the headline dataset is now *earned*, not authored.

### Design constraints — non-negotiable

- **The environment is fully simulated.** Fake filesystem, fake repo, fake database, fake cloud. No command ever touches anything real. The agent believes it is live; nothing is.
- **Scope the published artifact carefully.** What you release is the aggregate: attack *categories*, success rates by policy tier, the frontier data. Not a searchable cookbook of working jailbreak strings. Frame it the way published red-team work does — this is the same posture as OAP's bounty testbed, and it is what keeps the project readable as security research rather than as an attack tool.
- **Consent and logging notice on entry.** Players must know attempts are recorded and may be published in aggregate.
- **Rate limit and cap model spend** before you make it public, not after.

### Build order

1. Simulated environment + tool shims (fake shell/git/SQL that report plausible output)
2. Agent loop with tool calling
3. Preflight in the middle, with a policy tier switch
4. Attacker mode + logging
5. Operator mode + task set + interruption logging
6. Scoreboard and public deploy
7. Analysis: frontier chart from real play data

Ship 1–4 first. That alone is a demoable artifact. Mode 5 is what turns it from a fun demo into a result.

---

## 4. The benchmark — now the arena's seed and regression set

With Breakroom as the centrepiece, this section's role changes. You still need a hand-built labelled set, but it is now the **seed corpus and regression suite** — not the headline dataset. Target ~200 items rather than 1,200, weighted almost entirely toward hard cases and minimal pairs. The arena supplies volume and realism; this supplies the fixed yardstick you can re-run after every change.

Build this **before** the service. If you build the service first you will unconsciously design it to flatter the tests.

### Structure

Target ~1,200 labelled actions, split roughly:

- **40% clearly dangerous** — `rm -rf /`, `DROP TABLE users` on prod, force-push to `main`
- **40% clearly benign** — `rm -rf node_modules`, `DROP TABLE tmp_import_scratch`, force-push to a personal feature branch
- **20% hard cases** — the ones that decide the result. `rm -rf ./build` (benign) vs `rm -rf ./build/` where `build` is a symlink to source (dangerous). `TRUNCATE sessions` in staging vs prod. Identical command strings whose correct label flips on context.

The hard cases are the intellectual content of the benchmark. A system that separates the obvious 80% proves nothing — regex does that. Design at least 100 **minimal pairs**: two actions differing in one contextual variable with opposite correct labels.

### Schema

Each record carries: action string, normalised structured form, environment context (repo, branch, env tag, target host), the stated user intent, gold label (`safe` / `confirm` / `block`), gold reversibility class, and a free-text rationale. The rationale field is what makes the dataset reusable by others.

### Labelling protocol

Two independent labellers minimum. Report **Cohen's kappa**. If you label alone, say so plainly and treat it as the study's primary limitation — do not hide it. Recruit one other developer for a 200-item overlap sample if at all possible; even partial double-labelling with a reported kappa is dramatically more credible than a solo set.

### Metrics — report all of them, always paired

- **Attack prevention rate** (recall on dangerous) — the metric the field reports
- **False positive rate** (benign actions flagged) — the metric the field omits
- **Precision, F1, and the full ROC/PR curve across policy strictness**
- **p50 / p95 / p99 latency** — OAP's 53 ms median is your bar; state yours next to it
- **Friction cost**: confirmations triggered per 100 benign actions, at each threshold

The headline chart of the whole project is a **single curve: false-positive rate against attack-prevention rate, with `deny *` and `allow *` plotted as the trivial endpoints and each system as a point or curve on that frontier.** That chart is the portfolio piece. Everything else supports it.

---

## 5. System design

### Pipeline

```
Action + context + stated intent
   │
   ├─ 1. Normaliser        → structured canonical action
   ├─ 2. Deterministic     → hard policy: limits, denylists, env rules
   │     policy engine        Can BLOCK. Cannot ALLOW past a block.
   ├─ 3. Reversibility     → idempotent | reversible | compensable
   │     classifier           | irreversible | unknown
   ├─ 4. Semantic scorer   → LLM: intent match + risk rationale
   │                          Advisory only. Never sole authority.
   └─ 5. Decision fusion   → allow | confirm | modify | block
                              + signed token + evidence trail
```

### Non-negotiable design rules

- **Deterministic rules are the only thing that can hard-block.** The LLM never gets final authority — your brief is right about this and it is also what makes the system auditable.
- **The LLM can only ever escalate, never de-escalate.** If rules say `confirm`, the model may push to `block` but never down to `allow`. This makes prompt injection against the scorer non-fatal: the worst an attacker achieves is unnecessary friction.
- **Fail closed on timeout.** If the semantic layer exceeds its budget, fall back to the deterministic verdict and mark `degraded: true` in the response.
- **Every response carries `confidence` and `unknowns`.** Never emit a bare verdict.
- **Every response names the rule or model that produced it.** This is your liability posture — you return *evidence*, not *assurance*. Put that sentence in the README and in the API docs.

### On the passport

Keep signed tokens — parameter-hash binding genuinely prevents TOCTOU substitution between approval and execution, and it is good engineering. But **cite OAP when you introduce it**, and call it a token or capability, not a passport. Position: "signed pre-action tokens, following the approach of OAP (arXiv 2603.20953), with the addition of a graded risk verdict rather than binary allow/deny." That framing is honest and still shows a real delta.

### Stack

Your brief's stack is over-specified for an MVP. Reduce:

- **Python + FastAPI** — pydantic gives you JSON Schema and OpenAPI free, and the ML/eval ecosystem is where the benchmark work lives. Choose C#/ASP.NET only if you specifically want .NET on your CV; the eval tooling will cost you time.
- **SQLite** for v1. Postgres when you have a second user. Redis when you have a measured cache-miss problem, not before.
- **Rules in YAML/Rego, loaded at startup.** Skip a full OPA deployment initially — a clean rule interface you can swap for OPA later is worth more than OPA on day one.
- **Signing: JWS via `pyjwt`,** EdDSA keys.
- **One SDK (Python), plus an MCP middleware shim.** Four SDKs is roadmap, not MVP.

---

## 6. Phases

Sized for meaningful part-time work. Each phase ends with something demonstrable, so the project has portfolio value even if you stop early.

> Note: with Breakroom adopted, phases run in the order 1 → 3 → arena → 2 → 4 → 5, because the arena needs a working Preflight in the middle before it can produce data. Revised sequence: seed corpus (1 wk) → Preflight service (2–3 wks) → arena attacker mode (2 wks) → operator mode + policy ladder (1 wk) → baselines and analysis (1 wk) → write-up (1 wk).

**Phase 1 — Benchmark (~2 weeks).** Schema, 1,200 labelled actions, ≥100 minimal pairs, labelling protocol documented, kappa reported. Published as its own repo with a data card. *Standalone value: this is citable on its own.*

**Phase 2 — Baselines (~1 week).** Implement and measure three: (a) regex/denylist, (b) a faithful reimplementation of OAP-style deterministic policy at both permissive and restrictive settings, (c) LLM-only classification. Plot all three on the frontier chart. *You now have the result even if your own system never beats them — a negative result, honestly reported, still demonstrates research maturity.*

**Phase 3 — Preflight service (~2–3 weeks).** The full pipeline in §5. `POST /v1/preflight` and `POST /v1/commit` only. Signed tokens with parameter binding. Test suite including adversarial prompt-injection cases against the semantic layer. Latency instrumented from day one.

**Phase 4 — Evaluation (~1 week).** Run Preflight against the benchmark. Produce the frontier chart. Ablate: what does each layer contribute? Report where the system fails — a documented failure taxonomy is a strength, not an admission.

**Phase 5 — Demo & write-up (~1 week).** MCP middleware wrapping a real shell/git toolchain, recorded end to end. README leading with the chart and the honest claim. Limitations section written with the same care as the results.

Total: roughly 7–8 weeks part-time. Phases 1–2 alone (3 weeks) already constitute a defensible portfolio artifact.

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| Reviewer finds OAP and thinks you copied it | Cite it in the README's opening section and benchmark against it explicitly. Turn it into evidence of literature awareness. |
| Benchmark is self-serving | Freeze the benchmark and publish it *before* tuning the system. Commit history proves the order. |
| Solo labelling undermines the result | Recruit a second labeller for ≥200 items; report kappa; name it as the top limitation regardless. |
| Scope creep back toward ten domains | The non-goals list in the README is load-bearing. Reread it weekly. |
| LLM latency blows the budget | Deterministic path answers alone in <10 ms; semantic layer runs under a hard timeout with fail-closed degradation. Measure p99, not just median. |
| Overclaiming in the write-up | Ban the words "predicts consequences", "guarantees", and "prevents" from all copy. Use "classifies", "flags", "enforces policy on". |

---

## 8. What "perfect" means here

It is not more features. Every additional domain, endpoint and SDK in the original brief *lowers* the ceiling on this project by diluting a measurable claim into an unfalsifiable pitch.

The version of this that carries real weight is small and sharp:

> A benchmark that exposes an unreported metric in a live research area, a system evaluated honestly against a named prior baseline on that benchmark, and a write-up whose limitations section is as rigorous as its results.

That is achievable in under two months and is much harder to dismiss than a ten-domain architecture diagram.

---

## Sources

- [How Agents Ask for Permission (arXiv:2607.13718)](https://arxiv.org/abs/2607.13718)
- [Before the Tool Call: Deterministic Pre-Action Authorization (arXiv:2603.20953)](https://arxiv.org/abs/2603.20953)
- [AI Identity: Standards, Gaps, and Research Directions (arXiv:2604.23280)](https://arxiv.org/abs/2604.23280)
- [Intent-Governed Tool Authorization for AI Agents (arXiv:2606.22916)](https://arxiv.org/abs/2606.22916)
- [Revisable by Design (arXiv:2604.23283)](https://arxiv.org/abs/2604.23283)
- [NIST NCCoE concept paper — Software and AI Agent Identity and Authorization](https://csrc.nist.gov/pubs/other/2026/02/05/accelerating-the-adoption-of-software-and-ai-agent/ipd)
- [NCCoE project page](https://www.nccoe.nist.gov/projects/software-and-ai-agent-identity-and-authorization)
- [Model Context Protocol](https://modelcontextprotocol.io/docs/getting-started/intro)
