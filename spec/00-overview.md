---
id: harp-overview
status: draft
normative: false
tier: null
version: 0.1
depends_on: []
---

# HARP — Overview

## Why this exists

Without a shared protocol layer, every team that builds an agent harness reinvents the same five wheels: error parsing, retry logic, write confirmation, capability detection, and action navigation. The result is a fleet of bespoke harnesses that fail in incompatible ways, require service-specific handling for every new integration, and break silently when service behavior changes.

Human developers face a narrower but related problem: error responses that say "bad request" without naming the field, success responses that omit what to do next, and operation semantics buried in prose documentation rather than machine-readable contracts. The 2am debugging scenario is not "I don't understand the domain" — it is "I can't tell which field is wrong and what the server expected."

HARP fixes the layer below the harness. It specifies contracts that every well-engineered API would invent regardless, standardizes them across services, and makes them machine-introspectable. A service that implements HARP does not need a custom harness — the harness is implied by the protocol. An agent consuming a HARP-compliant service can determine available operations, required preconditions, retry policy, and recovery hints from the response body alone, without parsing prose or making follow-up calls.

## Mental model

The closest prior art is the combination of RFC 7807 (Problem Details for HTTP APIs) and HAL (Hypertext Application Language). RFC 7807 standardizes error responses; HAL standardizes hypermedia links. HARP combines both concerns and extends them: it covers not just errors and links but operation semantics, cost signaling, write safety, and capability negotiation.

Where HARP diverges from prior art: RFC 7807 defines a problem format but not a remediation contract. HAL defines link relations but not operation preconditions. OpenAPI defines operation schemas but not runtime semantics. HARP defines all of these in a single composable protocol that layers on HTTP + OpenAPI 3.1 without breaking existing clients.

The design analogy that makes it click: HTTP gave us a uniform interface (GET, POST, PUT, DELETE) and status codes. OpenAPI gave us typed schemas. HARP gives us typed _semantics_ — what an operation does, what it costs, what can go wrong, what to do next, and whether it is safe to run autonomously.

## Specification

### 1. Problem

Modern services are consumed by two audiences with overlapping but non-identical needs: humans (developers reading docs, exploring with curl/Postman, debugging at 2am) and AI agents (Claude Code, Codex, Cursor, Copilot, custom bespoke agents) operating with limited context and no ability to ask follow-up questions.

Today's status quo:

- **OpenAPI / Swagger** ships type-level contracts but stops at field shapes. It does not declare operation semantics, retry safety, cost, dry-run support, deprecation paths, or recovery hints.
- **MCP** is becoming outdated: invented to bridge LLMs to tools when LLMs lacked good HTTP/OpenAPI grounding. Modern agents do not need a parallel transport — they need stronger contracts on the transport they already speak.
- **A2A** addresses agent-to-agent coordination but solves a problem agents do not have. Agents do not need a "how do I talk to another agent" protocol; they need stronger machine-readable contracts on the APIs they call.
- **Error responses** are mostly prose, sometimes typed by status code, rarely actionable without a follow-up call.
- **Action affordances** (what to do next) live in human docs.
- **Cost, latency, deprecation** are tribal knowledge.
- **Recovery** requires parsing prose error messages.

Result: agent harnesses (Martin Fowler's framing of `Model + Harness`) duplicate effort across teams, each re-deriving error grammars, retry semantics, dry-run conventions, action graphs, and capability negotiation. None of it interoperates.

HARP fixes the layer below the harness: it makes services intrinsically harnessable by codifying the contracts that any well-engineered API would have to invent regardless. Self-correcting agent loops collapse from "parse prose, guess intent" to "look up code, fetch doc, fix field." Humans benefit equally — every richer contract is a better Swagger UI, a better error message, a better runbook.

### 2. Goals and Non-Goals

#### Goals

- Define a vendor-neutral protocol that layers on top of HTTP + OpenAPI 3.1 without breaking existing clients.
- Define **three compliance tiers** (L1 / L2 / L3) so adoption ramps progressively rather than all-or-nothing.
- Make every error, response, and capability **machine-introspectable** with a single canonical envelope.
- Define mechanics for **autonomous-safe writes**: dry-run, two-phase destructive commit, idempotency, optimistic concurrency, audit causality.
- Define a **discovery surface** so agents understand a service from a single GET.
- Ship reusable **skills** and **reference materials** that any project can install to design, review, or migrate APIs to HARP compliance.

#### Non-Goals

- Replace OpenAPI. HARP extends it.
- Define an orchestration runtime. Recipes are agent-executed.
- Standardize transport beyond HTTP/JSON. gRPC, GraphQL, etc. are out of scope for v1.
- Replace MCP or A2A — leaves them be. HARP targets API protocol, not LLM-tool bridge or agent coordination.
- Define authentication itself. HARP standardizes scope grammar and metadata; the auth handshake remains the service's choice (JWT, API key, mTLS, etc.).
- Define i18n for human-facing strings beyond a `HARP-Locale` request header.

### 4. Tier Map

Each tier compounds on the prior. A service declares its maximum tier in `/.well-known/harness`. Agents detect tier and downgrade gracefully.

#### L1 — Baseline (cheap retrofit on any existing OpenAPI service)

| Capability | Letter | Section |
|---|---|---|
| Minimal `/.well-known/harness` discovery doc | a | [Discovery](./02-discovery.md) |
| Error envelope | b | [Envelope](./01-envelope.md) |
| Failure catalog per endpoint | n | [OpenAPI Extensions](./03-openapi-extensions.md) |
| Worked examples in schema | o | [OpenAPI Extensions](./03-openapi-extensions.md) |
| Op semantics tags (`read | write | destructive`) | k | [OpenAPI Extensions](./03-openapi-extensions.md) |
| `trace_id` on every response | s | [Envelope](./01-envelope.md), [Audit](./10-audit.md) |
| Auth scopes in OpenAPI | h | [Auth Scopes](./11-auth-scopes.md) |
| Versioning headers | i | [OpenAPI Extensions](./03-openapi-extensions.md) |

#### L2 — Agent-ready (response self-describes; agent navigates without prose)

| Capability | Letter | Section |
|---|---|---|
| Response metadata wrapper `{data, _meta}` | c | [Envelope](./01-envelope.md) |
| Action affordances `_actions[]` | d | [Envelope](./01-envelope.md) |
| Idempotency keys | e | [Write Correctness](./05-write-correctness.md) |
| Cost + latency budget headers and `_meta.cost` | p | [Envelope](./01-envelope.md), [OpenAPI Extensions](./03-openapi-extensions.md) |
| Stability tier per op | q | [OpenAPI Extensions](./03-openapi-extensions.md) |
| Optimistic concurrency (etag) | r | [Write Correctness](./05-write-correctness.md) |
| Schema evolution signals (`Deprecation`, `Sunset`, `Link rel=successor`) | u | [OpenAPI Extensions](./03-openapi-extensions.md) |
| Audit trail | j | [Audit](./10-audit.md) |

#### L3 — Autonomous-ready (agent runs unattended)

| Capability | Letter | Section |
|---|---|---|
| Dry-run | l | [Write Safety](./04-write-safety.md) |
| Two-phase destructive commit | m | [Write Safety](./04-write-safety.md) |
| Capability negotiation | f | [Capability Negotiation](./08-capability-negotiation.md) |
| Long-running job pattern | g | [Long-Running Jobs](./06-long-running.md) |
| Recipes catalog | t | [Recipes](./07-recipes.md) |
| Self-test vectors | v | [Self-Test Vectors](./09-self-test-vectors.md) |

## Why three tiers

Three tiers rather than one mandatory standard or five granular levels is a deliberate adoption calculus.

**One mandatory standard fails adoption.** Requiring L3 to claim any compliance means services with existing API contracts either absorb a large upfront retrofit cost or defer HARP entirely. Most services have a working API today; they will not break clients to adopt a protocol they can't incrementally validate.

**Five levels fail clarity.** A compliance system with five rungs requires integrators to remember which capabilities land at which level. Decision fatigue at level 3 kills momentum before level 4 is reached.

**Three tiers maps to three adoption gates.** L1 is a 2-day retrofit: add error envelopes and OpenAPI extensions. Any team with an existing OpenAPI spec can reach L1 without client-breaking changes. L2 is the "your agent doesn't need docs" level: responses self-describe their follow-on actions. L3 is the "unattended operation" level: write safety, job management, and recovery are all machine-navigable. Each tier answers a distinct question an agent or operator would ask: "Can I parse errors?" (L1), "Can I navigate without docs?" (L2), "Can I run this unsupervised?" (L3).

A service at L1 is already meaningfully better than the status quo. That is the design intent: make the first step cheap enough that no team has an excuse to skip it.

## Examples

**Good: a service announces its tier in the discovery doc, and an agent gates its behavior accordingly.**

An agent fetching `/.well-known/harness` sees `max_tier: L2`. It knows dry-run and two-phase commit are not supported. It routes destructive operations through a human confirmation step instead of relying on two-phase. No fallback logic requires hardcoding the service name.

**Bad: no tier declaration, agent assumes L3.**

An agent sends `?dryRun=true` on a `DELETE`. The service ignores the query parameter and executes the deletion. The agent has no way to detect this — `_meta.dry_run` is absent, which it treats as `false` only if it knows to check. Without tier declaration, the agent cannot know whether absence means "not dry-run" or "dry-run not supported."

## Cross-references

- [Envelope](./01-envelope.md) — canonical error and success envelope
- [Discovery](./02-discovery.md) — `/.well-known/harness` discovery doc
- [OpenAPI Extensions](./03-openapi-extensions.md) — per-operation `x-harness` block
- [Write Safety](./04-write-safety.md) — dry-run and two-phase commit
- [Write Correctness](./05-write-correctness.md) — idempotency and optimistic concurrency
- [Long-Running Jobs](./06-long-running.md) — 202 + poll pattern
- [Recipes](./07-recipes.md) — agent-executable workflow DAGs
- [Capability Negotiation](./08-capability-negotiation.md) — per-request header negotiation
- [Self-Test Vectors](./09-self-test-vectors.md) — canonical request/response pairs
- [Audit](./10-audit.md) — causality chain and audit trail
- [Auth Scopes](./11-auth-scopes.md) — scope grammar
- [Tiers](./12-tiers.md) — normative tier restatement
- [Conformance](./13-conformance.md) — conformance test suite
- [Tooling](./14-tooling.md) — `harp` CLI and reference middleware

## Limitations and v0.1 caveats

HARP v0.1 is HTTP/JSON only. gRPC, GraphQL, and WebSocket transports are out of scope. The recipe execution model assumes a single-agent executor; multi-agent DAG coordination is not addressed. Field-mask support (selective response projection) is deferred to v0.2. The conformance suite is defined normatively but the reference implementation is not yet complete. i18n support is limited to a `HARP-Locale` hint header with no server-side rendering obligation beyond passing it through.
