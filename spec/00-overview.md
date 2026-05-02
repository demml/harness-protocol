---
id: harp-overview
status: draft
normative: false
tier: null
version: 0.1
depends_on: []
---

# HARP — Overview

## 1. Problem

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

## 2. Goals and Non-Goals

### Goals

- Define a vendor-neutral protocol that layers on top of HTTP + OpenAPI 3.1 without breaking existing clients.
- Define **three compliance tiers** (L1 / L2 / L3) so adoption ramps progressively rather than all-or-nothing.
- Make every error, response, and capability **machine-introspectable** with a single canonical envelope.
- Define mechanics for **autonomous-safe writes**: dry-run, two-phase destructive commit, idempotency, optimistic concurrency, audit causality.
- Define a **discovery surface** so agents understand a service from a single GET.
- Ship reusable **skills** and **reference materials** that any project can install to design, review, or migrate APIs to HARP compliance.

### Non-Goals

- Replace OpenAPI. HARP extends it.
- Define an orchestration runtime. Recipes are agent-executed.
- Standardize transport beyond HTTP/JSON. gRPC, GraphQL, etc. are out of scope for v1.
- Replace MCP or A2A — leaves them be. HARP targets API protocol, not LLM-tool bridge or agent coordination.
- Define authentication itself. HARP standardizes scope grammar and metadata; the auth handshake remains the service's choice (JWT, API key, mTLS, etc.).
- Define i18n for human-facing strings beyond a `HARP-Locale` request header.

## 4. Tier Map

Each tier compounds on the prior. A service declares its maximum tier in `/.well-known/harness`. Agents detect tier and downgrade gracefully.

### L1 — Baseline (cheap retrofit on any existing OpenAPI service)

| Capability | Letter | Section |
|---|---|---|
| Error envelope | b | [Envelope](./01-envelope.md) |
| Failure catalog per endpoint | n | [OpenAPI Extensions](./03-openapi-extensions.md) |
| Worked examples in schema | o | [OpenAPI Extensions](./03-openapi-extensions.md) |
| Op semantics tags (`read | write | destructive | idempotent | long_running`) | k | [OpenAPI Extensions](./03-openapi-extensions.md) |
| `trace_id` on every response | s | [Envelope](./01-envelope.md), [Audit](./10-audit.md) |
| Auth scopes in OpenAPI | h | [Auth Scopes](./11-auth-scopes.md) |
| Versioning headers | i | [OpenAPI Extensions](./03-openapi-extensions.md) |

### L2 — Agent-ready (response self-describes; agent navigates without prose)

| Capability | Letter | Section |
|---|---|---|
| `/.well-known/harness` discovery doc | a | [Discovery](./02-discovery.md) |
| Response metadata wrapper `{data, _meta}` | c | [Envelope](./01-envelope.md) |
| Action affordances `_actions[]` | d | [Envelope](./01-envelope.md) |
| Idempotency keys | e | [Write Correctness](./05-write-correctness.md) |
| Cost + latency budget headers and `_meta.cost` | p | [Envelope](./01-envelope.md), [OpenAPI Extensions](./03-openapi-extensions.md) |
| Stability tier per op | q | [OpenAPI Extensions](./03-openapi-extensions.md) |
| Optimistic concurrency (etag) | r | [Write Correctness](./05-write-correctness.md) |
| Schema evolution signals (`Deprecation`, `Sunset`, `Link rel=successor`) | u | [OpenAPI Extensions](./03-openapi-extensions.md) |
| Audit trail | j | [Audit](./10-audit.md) |

### L3 — Autonomous-ready (agent runs unattended)

| Capability | Letter | Section |
|---|---|---|
| Dry-run | l | [Write Safety](./04-write-safety.md) |
| Two-phase destructive commit | m | [Write Safety](./04-write-safety.md) |
| Capability negotiation | f | [Capability Negotiation](./08-capability-negotiation.md) |
| Long-running job pattern | g | [Long-Running Jobs](./06-long-running.md) |
| Recipes catalog | t | [Recipes](./07-recipes.md) |
| Self-test vectors | v | [Self-Test Vectors](./09-self-test-vectors.md) |
