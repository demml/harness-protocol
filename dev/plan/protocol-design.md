---
id: harp-protocol-design
status: draft
version: 0.1
date: 2026-05-02
authors:
  - Steven Forrester
audience:
  - api-designers
  - agent-tooling-authors
  - protocol-implementers
---

# HARP — Harness Agent-Ready Protocol — Design

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

## 3. Locked Decisions

The following decisions came out of the brainstorm and are locked entering the implementation plan. Each links to its detailed shape later in this document.

| # | Decision | Rationale |
|---|---|---|
| D1 | Hybrid layering: `x-harness` extensions on OpenAPI + sibling `harness.yaml` / `/.well-known/harness/` for cross-cutting concerns | Reuses Swagger ecosystem; avoids forcing OpenAPI into shapes it resists |
| D2 | Three compliance tiers (L1, L2, L3), each compounds on prior | Adoption ramp; partial compliance is meaningful |
| D3 | Single canonical envelope shape for both success and error responses | Universal grep target; one schema to teach |
| D4 | Two-phase destructive commit uses HMAC-signed confirmation tokens (stateless) | No server storage; signature self-validates |
| D5 | Idempotency keys are stateful (server-side cache) | Replay detection requires state |
| D6 | Recipes are agent-executed; server does not orchestrate | Keeps server stateless; recipes are guidance, not contracts |
| D7 | Capability negotiation via `HARP-*` request headers (no field-mask in v1) | Reduces server complexity; field-mask deferred |
| D8 | Audit trail is mandatory at L2+; request bodies not logged by default | Privacy-by-default; metadata sufficient |
| D9 | Auth scopes use `<resource>:<action>[:<qualifier>]` grammar | Machine-parseable; matches widely-deployed conventions |
| D10 | Long-running jobs support poll + optional HMAC webhook | Both push and pull consumers supported |
| D11 | Self-test vectors are mandatory at every tier with coverage requirements | Conformance verifiable by replay |
| D12 | Markdown source-of-truth for spec; YAML frontmatter; RFC 2119 keywords; `spec/index.json` | Standard, agent-friendly, diff-friendly |
| D13 | Spec lives in standalone repo `~/Documents/GitHub/harness-protocol`; skills in `~/.claude/skills/` | Reusable across all of Steven's projects |
| D14 | Protocol name **HARP**; headers `HARP-*`; protocol error codes `HARP_*`; service codes keep own prefix | Pronounceable, distinct from existing namespaces |

## 4. Tier Map

Each tier compounds on the prior. A service declares its maximum tier in `/.well-known/harness`. Agents detect tier and downgrade gracefully.

### L1 — Baseline (cheap retrofit on any existing OpenAPI service)

| Capability | Letter | Section |
|---|---|---|
| Minimal `/.well-known/harness` discovery doc | a | §5 |
| Error envelope | b | §6 |
| Failure catalog per endpoint | n | §7 |
| Worked examples in schema | o | §7 |
| Op semantics tags (`read | write | destructive`) | k | §7 |
| `trace_id` on every response | s | §6, §11 |
| Auth scopes in OpenAPI | h | §13 |
| Versioning headers | i | §7 |

### L2 — Agent-ready (response self-describes; agent navigates without prose)

| Capability | Letter | Section |
|---|---|---|
| Response metadata wrapper `{data, _meta}` | c | §6 |
| Action affordances `_actions[]` | d | §6 |
| Idempotency keys | e | §9 |
| Cost + latency budget headers and `_meta.cost` | p | §6, §7 |
| Stability tier per op | q | §7 |
| Optimistic concurrency (etag) | r | §9 |
| Schema evolution signals (`Deprecation`, `Sunset`, `Link rel=successor`) | u | §7 |
| Audit trail | j | §11 |

### L3 — Autonomous-ready (agent runs unattended)

| Capability | Letter | Section |
|---|---|---|
| Dry-run | l | §8 |
| Two-phase destructive commit | m | §8 |
| Capability negotiation | f | §10 |
| Long-running job pattern | g | §12 |
| Recipes catalog | t | §14 |
| Self-test vectors | v | §15 |

## 5. Discovery Doc — `/.well-known/harness`

Single GET. Cacheable. Agent fetches once and knows everything else.

```yaml
harness_version: "0.1"
service:
  name: scouter
  version: "0.10.2"
  stability: stable                 # stable | beta | experimental
  max_tier: L2                      # service compliance ceiling
links:
  openapi: /openapi.json
  recipes: /.well-known/harness/recipes
  examples: /openapi/examples
  errors: /.well-known/harness/errors
  scopes: /.well-known/harness/scopes
  doc_root: https://docs.scouter.ai
  health: /healthz
  audit: /audit
auth:
  modes: [bearer_jwt, api_key]
  default_scope: read:public
errors:
  envelope_schema: /.well-known/harness/envelope.json
  code_prefix: SCOUTER_              # service-specific code namespace
capabilities:
  dry_run: true
  two_phase_commit: false
  long_running: true
  idempotency: true
  optimistic_concurrency: true
  capability_negotiation: false
budgets:
  default_p99_ms: 250
  rate_limit_per_min: 600
trace:
  header: x-trace-id
  propagation: w3c_traceparent
```

`/.well-known/harness/errors`, `/.well-known/harness/scopes`, `/.well-known/harness/recipes`, `/.well-known/harness/envelope.json` are sub-resources documented in their own sections.

L1 services serve a minimal discovery document with protocol version, service identity, declared tier, OpenAPI/error links, auth modes, envelope schema link, and trace header. L2+ services add richer capability, budget, audit, scopes, examples, and effective-tier fields.

## 6. Canonical Envelope

### 6.1 Error envelope (every non-2xx response)

```json
{
  "error": {
    "message": "DataCard 'foo/bar/1.0' not found",
    "code": "SCOUTER_DATACARD_NOT_FOUND",
    "field": "datacard_uid",
    "hint": "Register DataCard before linking from ModelCard",
    "doc_url": "https://docs.scouter.ai/errors/SCOUTER_DATACARD_NOT_FOUND",
    "retry": {
      "retryable": false,
      "after_ms": null,
      "max_attempts": 0
    },
    "suggested_action": {
      "operation": "POST /datacards",
      "example_url": "/openapi/examples/create_datacard"
    },
    "trace_id": "01HV7P...",
    "occurred_at": "2026-05-02T19:14:00Z"
  },
  "_meta": {
    "schema_ref": "/.well-known/harness/envelope.json",
    "tier": "L1",
    "service_version": "0.10.2"
  }
}
```

Rules (MUST unless noted):

- Every non-2xx response body MUST match this schema. No exceptions.
- `code` MUST be namespaced (`<prefix>_<area>_<reason>`). Codes MUST be stable across versions; renames require deprecation cycle.
- `field` SHOULD be a JSON-pointer when applicable; otherwise null.
- `retry.retryable=true` MUST only be set for transient failures (5xx, 429). MUST NOT be set on validation errors.
- `suggested_action` SHOULD be populated when a clear next step exists.
- `trace_id` MUST match the `x-trace-id` response header.
- Protocol-level errors use `HARP_*` codes (`HARP_ETAG_MISMATCH`, `HARP_INSUFFICIENT_SCOPE`, `HARP_IDEMPOTENCY_KEY_REUSED`, `HARP_DRY_RUN_NOT_SUPPORTED`, etc.). Service-level errors use the service's declared prefix.

### 6.2 Success envelope (every 2xx response)

```json
{
  "data": { /* actual payload */ },
  "_meta": {
    "schema_ref": "/openapi.json#/components/schemas/DriftProfile",
    "tier": "L1",
    "service_version": "0.10.2",
    "trace_id": "01HV7P...",
    "occurred_at": "2026-05-02T19:14:00Z",
    "stability": "stable",
    "etag": "W/\"v42\"",
    "deprecation": null,
    "cost": {
      "p99_ms_budget": 250,
      "actual_ms": 87
    }
  },
  "_actions": [
    {
      "rel": "update",
      "method": "PUT",
      "href": "/drift/profiles/foo/bar/1.0",
      "requires_etag": true,
      "semantics": "write",
      "doc_url": "https://docs.scouter.ai/api/update_profile"
    },
    {
      "rel": "delete",
      "method": "DELETE",
      "href": "/drift/profiles/foo/bar/1.0",
      "requires_two_phase": true,
      "preview_href": "/drift/profiles/foo/bar/1.0/delete?phase=preview",
      "commit_href": "/drift/profiles/foo/bar/1.0/delete?phase=commit&confirmation_token={confirmation_token}",
      "semantics": "destructive",
      "doc_url": "..."
    },
    {
      "rel": "alerts",
      "method": "GET",
      "href": "/drift/alerts?profile_uid=...",
      "semantics": "read"
    }
  ]
}
```

Rules:

- At L2+, `data` MUST be present on every 2xx. Empty response: `{"data": null}`.
- At L2+, `_meta` MUST be present on every 2xx.
- L1 services MAY use the success envelope, but are not required to wrap every successful response.
- `_actions` MUST be present at L2+ for ops returning a resource. MAY be empty.
- `_actions[].semantics` MUST use the same vocabulary as `x-harness.semantics` (§7).
- `_actions[].requires_etag` and `requires_two_phase` flag client preconditions inline.
- `_actions[].preview_href` and `_actions[].commit_href` MUST be present when `requires_two_phase: true`.
- List responses use `data: [...]` with `_meta.pagination: { next_cursor, total }`.
- `_meta.cost` is the body-side mirror of the `HARP-Cost-Units` and `HARP-Actual-Ms` headers; both header and body MUST be present at L2+. See §10.3 for the full header set.

## 7. Per-Operation OpenAPI Extension `x-harness`

```yaml
paths:
  /drift/profiles:
    post:
      summary: Register drift profile
      x-harness:
        semantics: write              # read | write | destructive
        stability: stable             # stable | beta | experimental
        idempotent: false             # supports Idempotency-Key header
        requires_etag: false          # writes require If-Match
        dry_run: true                 # accepts ?dryRun=true
        two_phase: false              # destructive ops only
        two_phase_token_ttl_seconds: 300   # optional override; default 300
        long_running: false           # returns 202 + job_id
        cost:
          p99_ms_budget: 300
          compute_units: 1
        scopes_required: [drift:write]
        possible_errors:
          - SCOUTER_VALIDATION
          - SCOUTER_DUPLICATE_PROFILE
          - SCOUTER_AUTH_FORBIDDEN
        examples_ref: /openapi/examples/register_profile
        deprecation: null             # { since, sunset, successor }
        related_recipes: [register_drift_workflow]
```

Rules:

- `semantics` MUST be set on every operation at L1+.
- `possible_errors` MUST enumerate every error code an op can return at L1+. Conformance test: replay every code from this list and verify the envelope matches.
- `examples_ref` MUST resolve to a JSON document conforming to the self-test-vector schema (§15).
- `deprecation`, when non-null, MUST also surface as `Deprecation` and `Sunset` HTTP headers and a `Link: rel=successor-version` header on responses.
- `cost.p99_ms_budget` MAY override the discovery doc default for this op.

## 8. Write Safety

### 8.1 Dry-run

Applies to ops with `x-harness.dry_run: true`.

Client sends `?dryRun=true` query parameter or `HARP-Dry-Run: 1` header (either is sufficient). When both are present and disagree, the query parameter wins. Any truthy value (`true`, `1`, `yes`) triggers dry-run; any other value or absence is treated as a real call.

Server MUST:

- Return 200 with the standard success envelope.
- Set `_meta.dry_run: true`.
- Return simulated post-state in `data`.
- Populate `_meta.effects` as an itemized list:
  ```json
  "effects": [
    { "kind": "create", "resource": "drift/profiles/foo/bar/1.0", "summary": "would create new PSI profile with 12 features" },
    { "kind": "side_effect", "resource": "scheduler/cron", "summary": "would register hourly drift scan" }
  ]
  ```
- NOT mutate any state.
- NOT consume the `Idempotency-Key`.
- Count quota at 10% of real cost.

### 8.2 Two-phase destructive commit

Mandatory at L3 for ops with `x-harness.two_phase: true`. Cannot be bypassed.

**Phase 1 — preview:**

```
POST /drift/profiles/foo/bar/1.0/delete?phase=preview
```

Response (200):

```json
{
  "data": {
    "confirmation_token": "ct_01HV7P...",
    "expires_at": "2026-05-02T19:19:00Z"
  },
  "_meta": {
    "preview": true,
    "effects": [...]
  }
}
```

Token is a HMAC-signed value:

```
ct_<base32(payload)>.<base32(hmac)>
```

`payload` includes (resource, op, requestor, request_body_hash, expiry_unix).

`hmac` uses a service-secret signing key.

Token TTL default: 5 minutes. Configurable per-op via `x-harness.two_phase_token_ttl_seconds` (§7).

**Phase 2 — commit:**

```
POST /drift/profiles/foo/bar/1.0/delete?phase=commit&confirmation_token=ct_...
```

Server MUST:

- Verify HMAC signature.
- Verify expiry.
- Verify (resource, op, requestor) bound to token matches request.
- Verify body hash matches token's payload.
- Execute the destructive op.
- Return standard success envelope.

Replay of consumed token: 410 Gone + `code: HARP_TOKEN_CONSUMED`.

Token reuse on different target: 400 + `code: HARP_TOKEN_BINDING_MISMATCH`.

Stateless verification: server does not need to store issued tokens. Replay protection requires a small consumed-token cache (TTL = max token TTL); spec mandates this minimum state.

## 9. Write Correctness

### 9.1 Idempotency keys

Applies to ops with `x-harness.idempotent: true`.

Client sends `Idempotency-Key: <uuid>` header. Server MUST:

- Cache `(requestor, op, key) → response` for TTL (default 24h).
- Replay with same body: return cached response (status, body, etag identical).
- Replay with different body: 409 + `HARP_IDEMPOTENCY_KEY_REUSED` envelope; include body hash mismatch detail in `_meta`.
- Scope keys per-(service, requestor, op). Not per-resource: same key on different resources by the same requestor for the same op IS treated as a replay; clients are responsible for choosing fresh keys (UUIDv4 recommended).

Storage MUST be persistent (Redis, Postgres, or equivalent).

### 9.2 Optimistic concurrency

Applies to ops with `x-harness.requires_etag: true`.

Reads MUST return `ETag: W/"<version>"` header AND `_meta.etag`.

Writes MUST require `If-Match: W/"<version>"` header.

Mismatch: 412 + envelope:

```json
{
  "error": {
    "code": "HARP_ETAG_MISMATCH",
    "field": "if-match",
    "hint": "Resource modified by another writer. Re-fetch and retry.",
    "retry": { "retryable": true, "after_ms": 0 }
  },
  "_meta": { "current_etag": "W/\"v43\"" }
}
```

Etag format opaque to client. Server's choice (version int, content hash, timestamp).

### 9.3 Interaction

When both `Idempotency-Key` and `If-Match` are present and the request is a replay: the cached response is served and the etag check is skipped. Original semantics preserved.

## 10. Capability Negotiation (L3)

### 10.1 Request headers

| Header | Values | Purpose |
|---|---|---|
| `HARP-Client` | `<name>/<version> (tier=Lx)` | Agent identity + tier ceiling |
| `HARP-Verbosity` | `compact \| normal \| verbose` | Response shape selector |
| `HARP-Context-Budget` | `<int>` | Max tokens agent can spend on this response |
| `HARP-Format` | `json \| yaml \| json-compact` | Wire format pref |
| `HARP-Locale` | BCP-47 (e.g. `en-US`) | Language for human-facing strings only; codes always English |

Field-mask is **out of v1**.

### 10.2 Server behavior

- `compact`: MAY drop `_actions`, `_meta.cost`, and optional `_meta` fields. MUST keep `data` or `error`, `_meta.tier`, `trace_id`, and error `code`.
- `verbose`: expand `_actions` with inline examples, inline `failure_catalog` for current op, include `recipes_relevant`.
- Context-Budget enforced server-side. If projected response exceeds budget: server applies fallback projection in this order:
  1. Drop `_actions[].doc_url` and recipes.
  2. Drop `_meta.cost`.
  3. Truncate `data` arrays. MUST set `_meta.truncated: { dropped: N, total: M }`.
- Server MUST confirm what was applied via response header `HARP-Verbosity-Applied` and `_meta.adaptations`:
  ```json
  "adaptations": { "verbosity": "compact", "truncated": false, "omitted_fields": ["_actions", "_meta.cost"] }
  ```

### 10.3 Full HARP header reference

| Header | Direction | Tier | Purpose |
|---|---|---|---|
| `HARP-Client` | request | L3 | Agent identity + tier ceiling |
| `HARP-Verbosity` | request | L3 | `compact \| normal \| verbose` |
| `HARP-Verbosity-Applied` | response | L3 | Echo of applied verbosity |
| `HARP-Context-Budget` | request | L3 | Max tokens for response |
| `HARP-Format` | request | L3 | Wire format pref |
| `HARP-Locale` | request | L3 | BCP-47 for human-facing strings |
| `HARP-Dry-Run` | request | L3 | Truthy triggers dry-run; query param wins on conflict |
| `HARP-Causality` | request | L2+ | Parent trace_id for audit chain |
| `HARP-Signature` | response (callback) | L3 | HMAC-SHA256 of webhook body |
| `HARP-Cost-Units` | response | L2+ | Compute units consumed |
| `HARP-Actual-Ms` | response | L2+ | Wall-clock latency for this call |
| `x-trace-id` | response | L1+ | Request trace identifier (lowercase by W3C convention) |
| `Idempotency-Key` | request | L2 | Client-chosen UUID; UUIDv4 recommended |
| `If-Match` | request | L2 | Etag for optimistic concurrency |
| `ETag` | response | L2 | Resource version |
| `Retry-After` | response | L1+ | RFC 7231 standard for 429 / 503 / job poll |
| `Deprecation` | response | L2 | RFC 9745 deprecation signal |
| `Sunset` | response | L2 | RFC 8594 sunset date |
| `Link` | response | L2 | `rel=successor-version` for migrations |

## 11. Audit Trail (L2+)

### 11.1 Causality

Every request MAY carry `HARP-Causality: <parent_trace_id>` to declare the upstream operation that initiated it. Forms a causality chain.

Every response MUST carry `x-trace-id` and `_meta.trace_id` (matching the header).

### 11.2 Mandatory log row

Per write/destructive op, server MUST persist:

```
{
  trace_id, parent_trace_id,
  requestor,                  // subject from JWT/API key
  agent_id,                   // from HARP-Client header (may differ from requestor)
  operation,                  // operationId
  resource,
  semantics,
  timestamp,
  outcome,                    // "success" | "error_<code>"
  etag_before, etag_after,
  dry_run: bool,
  two_phase_token: <hash>     // never raw token
}
```

### 11.3 Endpoints

| Endpoint | Returns |
|---|---|
| `GET /audit/trace/{trace_id}` | Full row + envelope |
| `GET /audit?resource=<r>&since=<t>&until=<t>` | Ordered audit rows for resource |
| `GET /audit/causality/{trace_id}` | Recursive parent walk producing the full chain |

### 11.4 Privacy

Request bodies MUST NOT be logged by default. `_meta.audited_fields: ["model_uid", "feature_count"]` declares what server captured. Operators may opt into deeper logging via service config; spec mandates the metadata-only default.

### 11.5 Retention

Spec mandates ≥ 30 days. Service may extend.

## 12. Long-Running Jobs (L3)

### 12.1 Submit

Op with `x-harness.long_running: true` returns 202:

```json
{
  "data": {
    "job_id": "job_01HV7P...",
    "status": "pending",
    "submitted_at": "...",
    "estimated_completion_at": "..."
  },
  "_meta": { ... },
  "_actions": [
    { "rel": "status", "method": "GET", "href": "/jobs/job_01HV7P..." },
    { "rel": "cancel", "method": "DELETE", "href": "/jobs/job_01HV7P...", "semantics": "destructive" },
    { "rel": "result", "method": "GET", "href": "/jobs/job_01HV7P.../result", "available_when": "succeeded" }
  ]
}
```

### 12.2 Poll

`GET /jobs/{job_id}`:

```json
"data": {
  "job_id": "...",
  "status": "pending | running | succeeded | failed | cancelled",
  "progress": { "pct": 42, "message": "binning features" },
  "submitted_at": "...",
  "started_at": "...",
  "completed_at": "...",
  "result_url": "/jobs/.../result",       // null until terminal
  "error": { ... }                          // populated on "failed"
}
```

Server SHOULD return `Retry-After` header on non-terminal responses.

### 12.3 Result

`GET /jobs/{job_id}/result` returns the final envelope as if the op had been synchronous.

TTL on result default: 24h. After expiry: 410 Gone.

### 12.4 Cancel

`DELETE /jobs/{job_id}` is idempotent; returns final state.

### 12.5 List

`GET /jobs?requestor=<r>&status=<s>` returns ordered jobs visible to caller.

### 12.6 Optional webhook callback

Submission accepts `?callback_url=https://...&callback_secret=...`. Server POSTs the final envelope to the callback. Body is HMAC-SHA256 signed with `callback_secret` (header `HARP-Signature: <hmac>`). Server retries with exponential backoff on non-2xx delivery for up to 24h, then drops with audit row.

`callback_secret` lifecycle:

- Stored encrypted at rest, scoped to the job row only.
- Discarded when the job reaches a terminal state AND callback delivery succeeds OR retry budget is exhausted.
- Never echoed back to clients (job poll responses MUST omit the secret; presence is signaled via `_meta.callback_configured: true`).

## 13. Auth Scope Grammar (L1+)

### 13.1 Format

```
<resource>:<action>[:<qualifier>]
```

| Component | Values |
|---|---|
| `resource` | noun (e.g. `drift`, `profile`, `alert`, `audit`, `job`, `*`) |
| `action` | `read | write | destroy | execute | admin` |
| `qualifier` | optional narrowing (`own`, `space:<name>`, `tier:public`) |

### 13.2 Discovery sub-resource

`/.well-known/harness/scopes`:

```yaml
scopes:
  - id: drift:read
    description: Read drift profiles and results
    grants_implicit: []
  - id: drift:write
    description: Create/update drift profiles
    grants_implicit: [drift:read]
  - id: drift:destroy
    description: Delete drift profiles
    grants_implicit: [drift:read, drift:write]
  - id: "*:admin"
    description: Full administrative access
    grants_implicit: ["*"]
```

Per-op required scopes are declared via `x-harness.scopes_required`.

### 13.3 Failure envelope

403 + `HARP_INSUFFICIENT_SCOPE` with `_meta.required_scopes` and `_meta.granted_scopes` so an agent can reason about the gap.

### 13.4 Token introspection

`GET /.well-known/harness/whoami` returns:

```json
"data": {
  "requestor": "user@example.com",
  "agent_id": "claude-code/0.42",
  "granted_scopes": ["drift:write", "audit:read:own"],
  "expires_at": "..."
}
```

Agents call this once at startup and cache.

## 14. Recipes Catalog (L3)

`/.well-known/harness/recipes` lists machine-executable workflow DAGs. Server does not orchestrate; agents fetch and execute.

```yaml
recipes:
  - id: register_drift_workflow
    title: Register a PSI drift profile end-to-end
    description: Create profile, attach alert config, schedule cron job.
    when_to_use: |
      Agent wants to set up monitoring for a new model. Use this instead of
      calling endpoints individually.
    inputs:
      - name: model_uid
        schema: { type: string, format: uuid }
      - name: feature_names
        schema: { type: array, items: { type: string } }
    outputs:
      - name: profile_uid
      - name: cron_job_id
    steps:
      - id: create
        operation_id: register_drift_profile
        body_template: |
          { "model_uid": ${inputs.model_uid}, "features": ${inputs.feature_names} }
        capture: { profile_uid: "$.data.uid" }
      - id: alert
        operation_id: create_alert_config
        depends_on: [create]
        body_template: |
          { "profile_uid": ${steps.create.profile_uid}, "channel": "slack" }
      - id: schedule
        operation_id: create_cron_schedule
        depends_on: [create]
        body_template: |
          { "profile_uid": ${steps.create.profile_uid}, "cron": "0 * * * *" }
        capture: { cron_job_id: "$.data.id" }
    failure_modes:
      - step: create
        error: SCOUTER_DUPLICATE_PROFILE
        recovery: "Use existing profile_uid from error._meta.existing_uid; skip to alert step"
        action: use_existing
        use_existing_from: "$.error._meta.existing_uid"
        continue_at: alert
    examples_ref: /openapi/examples/recipes/register_drift_workflow
    tier: L2
```

Notes:

- `body_template` uses simple `${...}` interpolation with namespaces `inputs.<name>` and `steps.<id>.<captured>`. JSONata explicitly NOT used in v1 to keep agent execution trivial.
- Interpolation is JSON-value substitution after input schema validation; runners quote strings and preserve array/object/number/boolean/null types.
- `operation_id` is a join key into `links.openapi`; agents resolve it to method, path template, parameters, request body schema, and server URL from OpenAPI before executing the step.
- `capture` extracts via JSONPath into named vars for downstream steps.
- `depends_on` declares the DAG.
- `failure_modes` enumerates known recovery hints per step + error code.
- `tier` is the minimum service tier required to execute the recipe.

## 15. Self-Test Vectors

`/openapi/examples/<operation_id>` returns canonical request/response pairs.

```json
{
  "operation_id": "register_drift_profile",
  "version": "0.10.2",
  "vectors": [
    {
      "name": "success_psi_basic",
      "request": {
        "method": "POST",
        "path": "/drift/profiles",
        "headers": { "Authorization": "Bearer $TOKEN", "Idempotency-Key": "$UUID" },
        "body": { "model_uid": "...", "features": [], "drift_type": "psi" }
      },
      "response": {
        "status": 201,
        "headers": { "ETag": "W/\"v1\"" },
        "body": { "uid": "...", "status": "active" }
      },
      "tier_required": "L1"
    },
    {
      "name": "failure_duplicate",
      "request": { },
      "response": {
        "status": 409,
        "body": { "error": { "code": "SCOUTER_DUPLICATE_PROFILE" } }
      }
    },
    {
      "name": "dry_run_psi",
      "request": { },
      "response": {
        "status": 200,
        "body": { "_meta": { "dry_run": true, "effects": [] } }
      }
    }
  ]
}
```

**Substitution grammar inside vectors:** vectors use bare `$NAME` placeholders (distinct from recipes' `${...}` interpolation in §14, which executes at agent runtime against captured state). Vector placeholders are filled by a test runner from a fixture environment (`$TOKEN`, `$UUID`, `$NOW`, `$ETAG_FROM_STEP_<n>`). Conformance test runners MUST resolve these before replay; the spec ships canonical fixture-name conventions in `schemas/vector.json`.

### 15.1 Use cases

- **Agent self-validation**: agent generates client code, replays vectors against its own client, asserts response shape matches. Catches drift.
- **Conformance testing**: a test suite replays vectors against any server claiming tier compliance.
- **Pattern matching**: agent reads vectors before constructing first call. Beats parsing OpenAPI.
- **Doc generation**: Swagger UI / docs site renders vectors as live examples.

### 15.2 Coverage requirements

| Tier | Mandatory coverage |
|---|---|
| L1+ | At least one success vector per op |
| L2+ | At least one vector per `possible_errors` entry |
| L3 | One dry-run vector if op supports it; one two-phase preview+commit pair if applicable |

Fixture conventions, including canonical placeholder names (`$TOKEN`, `$UUID`, `$NOW`, `$ETAG_FROM_STEP_<n>`) and shared assets across crate tests, live in the `harp-fixtures` crate (§16). Vector authors and conformance runners both depend on `harp-fixtures` for the canonical names.

## 16. Repo Layout

New repo: `~/Documents/GitHub/harness-protocol/`. Cargo workspace mirroring opsml's structural conventions; Python sub-package mirrors py-opsml / py-scouter.

```
harness-protocol/
  Cargo.toml                        # workspace root
  Cargo.lock
  Makefile
  README.md
  CONTRIBUTING.md

  crates/
    harp/                           # binary crate; bin name "harp"
      src/
        main.rs
        lib.rs
        error.rs
        cli/                        # clap subcommand structs
          mod.rs
          init.rs
          scaffold.rs
          lint.rs
          test.rs
          migrate.rs
          docs.rs
          serve_refs.rs
        actions/                    # orchestration per command
          init.rs
          scaffold.rs
          lint.rs
          conformance.rs
          migrate.rs
          docs.rs

    harp-core/                      # protocol types
      src/
        envelope.rs                 # success + error envelopes
        discovery.rs                # /.well-known/harness/* shapes
        extension.rs                # x-harness deserialize/validate
        recipe.rs
        vector.rs
        tier.rs
        codes.rs                    # canonical HARP_* error codes
        error.rs
        lib.rs

    harp-openapi/                   # OpenAPI 3.1 reader/writer w/ x-harness awareness
    harp-lint/                      # tier-rule engine; pure logic
    harp-conformance/               # live URL test runner; replays vectors
    harp-migrate/                   # diff engine; current state vs target tier
    harp-codegen/                   # scaffold generators (schemas, catalog, discovery, vectors, docs)
    harp-harness/                   # client-side service registry, planning, and safe execution
    harp-axum/                      # reference Rust middleware (tower layer)
    harp-fixtures/                  # canonical fixtures shared across crate tests

  py-harp/                          # mirrors py-opsml / py-scouter pattern
    python/harp/
      __init__.py
      fastapi/                      # ASGI middleware (pure Python wrapping PyO3 core)
        __init__.py
        middleware.py
        decorators.py               # @dry_run, @two_phase, @idempotent, @audited
      cli/                          # PyO3 bindings exposing harp-lint + harp-conformance
        __init__.py
    src/                            # PyO3 FFI
      lib.rs
    pyproject.toml                  # uv + maturin managed
    Makefile

  ref-impl/
    rust-axum/                      # <500 LOC reference server using harp-axum
    python-fastapi/                 # <500 LOC reference server using py-harp.fastapi

  spec/                             # markdown source-of-truth
    index.json                      # machine-readable section index
    00-overview.md
    01-envelope.md
    02-discovery.md
    03-openapi-extensions.md
    04-write-safety.md              # dry-run + two-phase
    05-write-correctness.md         # idempotency + etag
    06-long-running.md
    07-recipes.md
    08-capability-negotiation.md
    09-self-test-vectors.md
    10-audit.md
    11-auth-scopes.md
    12-tiers.md
    13-conformance.md
    14-tooling.md                   # mirrors §21 of this design doc
  schemas/
    discovery.json
    envelope-error.json
    envelope-success.json
    openapi-extension.json
    recipe.json
    vector.json
  examples/                         # tested reference fixtures
  conformance/                      # tier-graded test scaffolds (consumed by harp-conformance)
  docs/                             # Astro Starlight site generated by `harp docs build`

  .github/workflows/
    rust.yml                        # cargo fmt + clippy + test --all-features
    python.yml                      # uv lint + pytest + maturin develop
    schemas.yml                     # validate every example against schema; spec/index.json drift
    conformance.yml                 # ref-impl conformance run on PR
```

Workspace `Cargo.toml` skeleton:

```toml
[workspace]
resolver = "2"
members = ["crates/*", "py-harp"]
default-members = ["crates/*"]

[workspace.package]
version = "0.1.0"
authors = ["Steven Forrester <sjforrester32@gmail.com>"]
edition = "2024"
license = "MIT"
repository = "https://github.com/demml/harness-protocol"

[workspace.dependencies]
harp = { path = "crates/harp" }
harp-core = { path = "crates/harp-core" }
harp-openapi = { path = "crates/harp-openapi" }
harp-lint = { path = "crates/harp-lint" }
harp-conformance = { path = "crates/harp-conformance" }
harp-migrate = { path = "crates/harp-migrate" }
harp-codegen = { path = "crates/harp-codegen" }
harp-harness = { path = "crates/harp-harness" }
harp-axum = { path = "crates/harp-axum" }
harp-fixtures = { path = "crates/harp-fixtures" }
```

### 16.1 Per-file frontmatter convention

```yaml
---
id: harp-envelope
status: draft           # draft | proposed | stable
normative: true
tier: L1                # or L2, L3, or null for cross-tier
version: 1.0
depends_on: []
---
```

### 16.2 `spec/index.json`

```json
{
  "harp_version": "1.0",
  "sections": [
    {
      "id": "harp-envelope",
      "file": "01-envelope.md",
      "tier": "L1",
      "must_count": 7,
      "schemas": ["envelope-error.json", "envelope-success.json"]
    }
  ]
}
```

### 16.3 Conventions

- Markdown only (CommonMark, no exotic extensions).
- RFC 2119 keywords (`MUST`, `SHOULD`, `MAY`, `MUST NOT`, `SHOULD NOT`) capitalized.
- Stable section IDs; renames require deprecation cycle.
- All schemas in `schemas/` are JSON Schema 2020-12.
- Every example block in spec MUST have a matching tested file in `examples/` validated against its schema in CI. Drift = build break.

## 17. Skill Artifacts (Reusable Across Projects)

Installed at `~/.claude/skills/`.

| Skill | When invoked | What it does |
|---|---|---|
| `harness-api-design` | New API design or significant feature add | Walks Claude through tier checklist, error envelope, OpenAPI extensions. Flags gaps. Proposes target tier. |
| `harness-api-review` | PR review on any API surface | Audits diff against tier requirements. Reports compliance gap with specific MUST/SHOULD violations. |
| `harness-conformance-test` | Standing up test infra for a HARP-claiming service | Generates conformance test scaffold per declared tier. |
| `harness-api-migrate` | Existing OpenAPI service wants to adopt HARP | Progressive lift L1 → L2 → L3. Each phase a separate PR. |

Each skill references canonical material in the standalone repo (read via skill's `description` or fetched from a pinned commit). Skills are thin: they enforce process; the spec holds substance.

## 18. Conformance Test Suite

Lives in `harness-protocol/conformance/`. Generic harness in any language; reference impl in Rust + Python.

### 18.1 Inputs

- Service base URL.
- Auth credentials (service's choice of mode).
- Declared tier from `/.well-known/harness`.

### 18.2 Test categories

| Category | Tier | Scope |
|---|---|---|
| Discovery doc shape | L1+ | Validate against `discovery.json` schema |
| Error envelope on synthetic errors | L1+ | Trigger every `possible_errors` entry per op via vector replay |
| Success envelope on synthetic happy path | L2+ | Validate `data`, `_meta` presence, `_meta.trace_id` consistency |
| Action affordances correctness | L2+ | Follow `_actions[]` rels, verify reachable, verify required preconditions match |
| Idempotency replay semantics | L2+ | Replay same key + same body, replay + different body |
| Etag concurrency | L2+ | Stale `If-Match` returns 412 + envelope |
| Cost headers + body mirror | L2+ | Header / body parity |
| Audit trail correctness | L2+ | Write op produces audit row reachable via `/audit/trace/{trace_id}` |
| Dry-run no-mutation | L3 | Dry-run + immediate read shows no state change |
| Two-phase token semantics | L3 | Expired token rejected; reused token rejected; replay rejected |
| Long-running poll-to-completion | L3 | Submit, poll to terminal, fetch result, cancel |
| Capability negotiation adaptation | L3 | `compact` strips correctly; `verbose` expands; budget enforces; `HARP-Verbosity-Applied` echoes |
| Self-test vector roundtrip | L3 | Every vector replayable against the live service |
| Recipe DAG executability | L3 | Each recipe DAG resolvable via OpenAPI ops; `body_template` interpolation parseable |

### 18.3 Output

```
{
  "service": "scouter",
  "declared_tier": "L2",
  "results": {
    "L1": { "passed": 47, "failed": 0, "skipped": 0 },
    "L2": { "passed": 22, "failed": 1, "skipped": 0 },
    "L3": { "passed": 0,  "failed": 0, "skipped": 14 }
  },
  "violations": [
    { "section": "harp-audit", "rule": "MUST audit every write op", "evidence": "trace_id=01HV7P... not found in /audit/trace endpoint" }
  ],
  "tier_attained": "L1"
}
```

`tier_attained` is the highest tier with zero failures. Service may publish this in the discovery doc as `effective_tier`.

## 19. Risks and Trade-offs

### Adoption risk

Spec lives or dies by reference implementations. Without scouter / opsml / a third independent service running L2+ end-to-end, HARP is paper. Mitigation: scouter is the proving ground (separate plan, separate repo).

### Verbosity tax

`_meta` and `_actions[]` add bytes to every response. For high-fanout list endpoints this is non-trivial. Mitigation: `HARP-Verbosity: compact` exists precisely for hot paths; conformance test ensures compact mode is honored.

### Token state for idempotency

Idempotency requires a server-side cache. Some teams resist any new state. Mitigation: HMAC-only tokens for two-phase commit (no state) covers the most-feared case (autonomous deletes); idempotency state is small, scoped, TTL'd.

### Recipe interpolation complexity

`${...}` interpolation is simple but not standardized. Edge cases (escaping, nested objects, type coercion) accumulate. Mitigation: keep `body_template` to `${var}` substitution into JSON literals only; no math, no functions; document escaping rules in §14.

### Drift between OpenAPI and `x-harness`

OpenAPI tooling does not validate vendor extensions. Stale `possible_errors` lists are silent landmines. Mitigation: conformance test (§18) replays every `possible_errors` entry per op; mismatch fails the build.

### Breaking change to clients written before HARP

Existing clients ignore `_meta` and `_actions` (forward-compatible JSON). New error envelope is breaking only if clients hardcoded a different shape; field-renames in HARP itself MUST go through deprecation cycle (§7 deprecation).

## 20. Open Questions for Implementation Plan

The implementation plan (next phase, via `superpowers:writing-plans`) needs to resolve:

1. **Decomposition:** which spec section ships first? Suggest envelope (§6) + tiers (§4) + discovery (§5) + JSON Schemas as the foundational milestone; everything else can follow incrementally.
2. **Repo bootstrap:** README, license, contributor guide, CI for schema validation + example tests, GitHub Actions for `index.json` regeneration.
3. **Schema authoring tooling:** hand-write JSON Schemas vs. derive from a single source. Initial recommendation: hand-write, automate later.
4. **Reference implementation strategy:** is scouter the canonical reference, or does the spec repo ship a tiny reference server (Rust + Python) for conformance test self-validation? Recommended: ship a tiny reference server in `harness-protocol/ref-impl/` so the conformance suite has a known-good target.
5. **Skill packaging:** does `~/.claude/skills/harness-*` symlink to material in the standalone repo (single source of truth) or is the spec content vendored into each skill? Recommended: pin a commit hash in each skill's metadata, fetch on first use, cache locally. Avoids stale skill content.
6. **Versioning policy:** semver for the protocol itself? Spec MUST declare a versioning rule for `harness_version` field in §5. **Early-decision flag for the planner:** this touches the wire format (discovery doc) and the `_meta.tier`/`schema_ref` fields — resolve before the first PR that ships any of those structures.

## 21. Tooling — Friction Reduction

Spec without tooling = paper. v1.0 ships the toolchain below to push adoption cost from "engineer-weeks per service" down to "days for L1, ~week for L2, ~3 weeks for L3."

### 21.1 Tier 1 (must ship with v1.0)

#### `harp` Rust binary CLI

Two-layer architecture: thin clap shell (`crates/harp/src/cli/*`) delegates to per-command orchestrator (`crates/harp/src/actions/*`), which calls into pure-logic core crates. Core crates are reusable from a future LSP server, GH Action binary, or IDE extension without dragging clap.

| Subcommand | Purpose | Backed by crate |
|---|---|---|
| `harp init` | Bootstrap. Takes existing OpenAPI doc → scaffolds `x-harness` blocks with safe defaults, creates `harness.yaml`, emits human-review TODOs for fields that cannot be inferred (cost budgets, scopes, related_recipes). | `harp-codegen` |
| `harp scaffold` | Generate ancillary files (JSON Schemas, error catalog, discovery doc template, vector skeletons) from existing `x-harness` annotations. Run after `init` or after editing extensions. | `harp-codegen` |
| `harp lint` | Static tier compliance check. No network. Reads OpenAPI doc, `harness.yaml`, schemas, vectors, recipes. Validates: minimal discovery doc shape (L1); every op has `semantics` using `read \| write \| destructive` (L1); `possible_errors` codes are namespaced and resolve to catalog (L1); `examples_ref` resolves to a valid vector file (L1); richer discovery fields validate for L2+; response schemas declare `data` and `_meta` (L2); `_actions[]` rels and two-phase hrefs are valid (L2/L3); idempotency / etag flags consistent (L2); recipe DAG `operation_id` values reference real OpenAPI operations and `body_template` is parseable (L3); vector coverage matches tier minimum (one success vector per op at L1; one failure vector per `possible_errors` entry at L2; one dry-run vector and one two-phase preview+commit pair at L3, when applicable); all cross-refs (discovery → openapi → x-harness → schemas) resolve. Exits non-zero on violations. | `harp-lint` |
| `harp test --url <base>` | Live conformance. Runs `harp lint` first (static), then dynamic conformance suite (§18) against the deployed service. Replays vectors. Outputs structured `tier_attained` + violations JSON. | `harp-conformance` |
| `harp migrate --from L1 --to L2` | Diff current state against target tier. Emits patch suggestions. `--apply` writes them; default = dry-run. | `harp-migrate` |
| `harp docs build` | Render docs site from spec + OpenAPI + recipes + vectors. Astro Starlight template. Service ships docs for free. | `harp-codegen` + Starlight |
| `harp serve-refs --lang rust\|python` | Boot a reference server locally for poking and agent demos. | `harp-axum` (Rust) or shells out to `ref-impl/python-fastapi` |
| `harp harness ...` | Client-side harness registry and safe service execution. Adds HARP services, indexes OpenAPI operations, resolves user intent, and calls services through HARP policy. | `harp-harness` |
| `harp agent install <adapter>` | Installs agent-specific adapters such as Claude Code skills that teach agents to use `harp harness`. | `harp-codegen` + `harp-harness` |

Shared CLI flags across all subcommands: `--format json|human` (default human), `--config <path>`, `--quiet`, `--verbose`, `-v|-vv`. Exit codes: 0 ok, 1 violation, 2 error.

Lint engine is the same crate (`harp-lint`) consumed by `harp lint`, `harp test` (static prepass), the planned LSP, and a future GitHub Action binary. Single source of compliance truth.

#### Agent harness CLI

`harp harness` is the client-side runtime for humans and agents consuming HARP services. It is separate from service-side adoption commands like `harp init` and `harp lint`.

Registry locations:

| Location | Scope | Secret policy |
|---|---|---|
| `~/.harp/harness.yaml` | User-global | May reference secrets via `auth_ref`, never stores raw secrets |
| `.harp/harness.yaml` | Project-local | Commit only if it contains no secrets |

Project-local entries override user-global entries with the same service name.

Expected command surface:

| Command | Purpose |
|---|---|
| `harp harness init --scope user\|project` | Create a harness registry. |
| `harp harness add <name> <base-url> --auth-env <ENV_VAR>` | Fetch discovery/OpenAPI, validate HARP metadata, index `operationId`, and store an auth reference. |
| `harp harness refresh <name>` | Refresh discovery and OpenAPI metadata. |
| `harp harness inspect <name>` | Show service metadata, capabilities, auth status, and cached operation count. |
| `harp harness ops <name>` | List operations, optionally filtered by semantics. |
| `harp harness recipes <name>` | List recipes advertised by the service. |
| `harp harness plan <name> "<intent>"` | Map user intent to candidate operations or recipes. |
| `harp harness call <name> <operation_id>` | Execute an operation through HARP policy rather than raw HTTP. |
| `harp harness recipe run <name> <recipe_id>` | Execute a recipe through the harness. |
| `harp harness commit <name> <confirmation_token>` | Commit a previously previewed two-phase destructive operation. |

Agents consuming registered HARP services SHOULD use `harp harness` instead of raw HTTP. The harness owns discovery refresh, OpenAPI operation resolution, auth references, request validation, idempotency keys, ETags, dry-run, two-phase commit, response envelope validation, and HARP error handling.

#### Reference middleware libraries

Drop-in, framework-native. Goal: 5 lines to bolt L1 onto an existing service; ~20 lines for L2.

- **Rust — `harp-axum`** (in `crates/harp-axum`). Tower middleware. Wraps responses in envelope, emits `trace_id`, mounts `/.well-known/harness/*`, auto-generates the discovery doc from the axum route registry. Ships dry-run / two-phase / idempotent / audited extractors and decorators. Idempotency cache pluggable (in-memory default; Redis adapter feature-gated).
- **Python — `harp.fastapi`** (in `py-harp/python/harp/fastapi`). ASGI middleware + dependency injectors + decorators (`@dry_run`, `@two_phase`, `@idempotent`, `@audited`). Pure-Python wrapper over PyO3 bindings to `harp-core` for envelope validation, discovery doc generation, vector replay assertions. Idempotency cache pluggable (in-memory default; Redis adapter optional).

#### Reference servers

- `ref-impl/rust-axum` — < 500 LOC service using `harp-axum` exercising every L1+L2+L3 feature.
- `ref-impl/python-fastapi` — < 500 LOC service using `harp.fastapi` exercising the same surface.

Both serve as conformance test targets and copy-paste starting points for adopters.

#### Skills (already covered in §17)

`~/.claude/skills/harness-api-design`, `harness-api-review`, `harness-conformance-test`, `harness-api-migrate`, and `harness-consumer`. The first four help service teams adopt HARP. `harness-consumer` helps an agent use registered HARP services through `harp harness`.

### 21.2 Tier 2 (post-v1.0 roadmap, NOT in scope for v1.0)

Listed for completeness; tracked in §20 as open questions.

- `harp` GitHub Action — drop-in workflow that runs lint on PR, runs conformance against ephemeral PR-preview deploy, comments compliance delta.
- OpenAPI client generator extensions — fork or contribute to `oapi-codegen` (Rust), `openapi-python-client`, `openapi-generator`. Generated clients honor `x-harness` natively (retry policy from `retry`, idempotency key auto-injection, etag handling, two-phase wrappers).
- VS Code / Cursor extension — autocomplete `x-harness` blocks, validate inline, surface tier warnings on save, run `harp lint` on save. Backed by an LSP shim wrapping `harp-lint`.
- Hosted conformance dashboard — submit URL, get tier verdict + violations, public README badge, catalog of compliant services.

### 21.3 Adoption math

Without tooling, ballpark cost per service: ~2 engineer-weeks for L1, ~6 for L2, ~12 for L3.

With Tier 1 tooling: ~2 days for L1, ~1 week for L2, ~3 weeks for L3.

~10x reduction. That is the difference between adoption and shelf-ware.

## 22. Approval Checkpoint

This document captures every locked decision from the brainstorm. Next step is the implementation plan via the `superpowers:writing-plans` skill, which decomposes §16-§18 into shippable PRs with file-level specifics.
