---
id: harp-capability-negotiation
status: draft
normative: true
tier: L3
version: 0.1
depends_on: [harp-envelope]
---

# HARP — Capability Negotiation

## Why this exists

A response that is optimal for a human reading a browser UI is often wasteful for an agent reading a structured response: `_actions[].doc_url` fields, expanded failure catalogs, and verbose `_meta` annotations consume tokens the agent does not need. Conversely, a response that is minimal for an agent may be frustrating for a developer debugging at the CLI: collapsed `_actions`, omitted examples, and missing context make the response opaque.

Without per-request negotiation, the server must choose one response shape for all callers. Any choice optimizes for one audience and imposes unnecessary cost on the other. An agent that receives a verbose response with 40 `_actions` entries, inline failure catalogs, and expanded recipe references will pay context cost for content it will never use.

Context budget enforcement addresses a harder problem: agents operating in constrained execution environments (limited token budgets, size-limited tool outputs) have no mechanism to bound response size before making a call. A service that returns a 50KB response to a context-constrained agent either causes a truncation error or forces the agent to spend its entire context budget on a single response.

## Mental model

The closest prior art is HTTP content negotiation (`Accept`, `Accept-Encoding`, `Accept-Language`), which lets clients express response format preferences. HARP extends this model to cover response _verbosity_ and _size_ — dimensions that HTTP content negotiation does not address.

`HARP-Verbosity` is analogous to `Accept` but for information density rather than media type. `HARP-Context-Budget` is analogous to `Range` (byte-range requests) but for response token count rather than byte offset. The key difference: HTTP range requests are about retrieving a slice of a resource; context budget enforcement is about the server computing a response projection that fits within a constraint.

Where HARP diverges from GraphQL's field selection: GraphQL requires the client to specify exactly which fields it wants. HARP's verbosity tiers specify a _density level_ and let the server decide which fields to include or exclude at that level — this is appropriate for agents that don't know the schema in advance and can't write a field-selection query without prior knowledge.

## Specification

### 10. Capability Negotiation (L3)

#### 10.1 Request Headers

| Header | Values | Purpose |
|---|---|---|
| `HARP-Client` | `<name>/<version> (tier=Lx)` | Agent identity + tier ceiling |
| `HARP-Verbosity` | `compact \| normal \| verbose` | Response shape selector |
| `HARP-Context-Budget` | `<int>` | Max tokens agent can spend on this response |
| `HARP-Format` | `json \| yaml \| json-compact` | Wire format pref |
| `HARP-Locale` | BCP-47 (e.g. `en-US`) | Language for human-facing strings only; codes always English |

Field-mask is out of v1.

#### 10.2 Server Behavior

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

#### 10.3 Full HARP Header Reference

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

## Per-field rationale

### `HARP-Client`

Identifies the agent and its tier ceiling to the server.

If absent, the server cannot distinguish a human browser from a constrained agent or apply agent-specific response shaping. The tier ceiling (`tier=L3`) tells the server the maximum tier the client understands — a server at L3 responding to an L1 client SHOULD fall back to L1 response shape. The format `<name>/<version> (tier=Lx)` is human-readable and parseable. MAY be omitted by human clients; SHOULD be sent by any HARP-aware agent.

### `HARP-Verbosity`

Selects the response information density.

If absent, the server applies `normal` (default). If the client is a constrained agent, the default `normal` response may include `_actions`, cost metadata, and deprecation signals that consume tokens the agent won't use. `compact` strips optional fields and reduces response size. `verbose` is intended for humans and developer tools that want all available context. MUST be respected by L3 servers.

### `HARP-Verbosity-Applied`

Response header confirming which verbosity level the server actually applied.

If absent, the client cannot verify that its verbosity preference was honored. A server that ignores `HARP-Verbosity: compact` but does not set `HARP-Verbosity-Applied` leaves the client unable to detect the non-compliance. MUST be present on every L3 response where `HARP-Verbosity` was sent in the request.

### `HARP-Context-Budget`

Maximum token count the agent can spend on this response.

If absent, the server has no bound on response size for the request. If present and the projected response exceeds the budget, the server applies the fallback projection sequence. The unit is tokens (estimated by the server using a tokenizer consistent with the agent identified in `HARP-Client`); the spec does not mandate a specific tokenizer. MAY be omitted by agents with no token constraint.

### `_meta.adaptations`

Declares what the server actually changed about the response.

If absent, a client that requested a compact response cannot verify which fields were dropped. An agent that needs `_meta.cost` for budget tracking but sent `HARP-Verbosity: compact` (which may drop it) needs to know `cost` was dropped so it can make a second call at `normal` verbosity if needed. `adaptations.verbosity`, `adaptations.truncated`, and `adaptations.omitted_fields` give the client this signal. MUST be present when the server modified the response shape.

### `_meta.truncated`

Declares how many array items were dropped due to context budget enforcement.

If absent when truncation occurred, the client receives a partial list and has no signal that it is incomplete. `_meta.truncated: { dropped: N, total: M }` tells the client exactly how many items were omitted and the total count — enabling pagination or a follow-up call with a higher budget. MUST be present whenever `data` arrays were truncated.

### `HARP-Causality`

Carries the parent trace ID for audit chain construction.

If absent, multi-step agent operations appear as disconnected requests in the audit trail. An agent executing a 5-step recipe generates 5 audit rows with no shared ancestry. With `HARP-Causality: <parent_trace_id>`, all 5 rows link to the same origin — enabling full causal reconstruction from a single trace ID. SHOULD be sent by agents on all calls after the first in a workflow.

### `HARP-Cost-Units`

Response header carrying the compute units consumed by this call.

If absent, agents tracking their compute budget against a service quota have no per-call feedback. `HARP-Cost-Units: 3` combined with `HARP-Actual-Ms: 87` gives the agent both compute and latency signals in a single response. MUST be present at L2+.

### `HARP-Actual-Ms`

Response header carrying the wall-clock latency of this call.

If absent, agents calibrating their timeout policies have no server-side latency signal. Client-side measurement includes network round-trip; `HARP-Actual-Ms` is the server-side processing time only, which is the relevant number for SLO comparison against `_meta.cost.p99_ms_budget`. MUST be present at L2+.

### `Retry-After`

Standard RFC 7231 header indicating when the client may retry.

If absent on a 429 or 503, clients applying exponential backoff have no server guidance on the minimum retry interval. A client that retries too aggressively on a rate-limited endpoint worsens the overload condition. `Retry-After: <seconds>` is a direct instruction. MUST be present on 429 and SHOULD be present on 503 and non-terminal job poll responses.

## Examples

**Good: agent sends compact verbosity, server confirms and returns minimal response.**

Request:
```http
GET /drift/profiles/abc123
Authorization: Bearer $TOKEN
HARP-Client: claude-code/0.42 (tier=L3)
HARP-Verbosity: compact
HARP-Context-Budget: 500
```

Response headers:
```http
HARP-Verbosity-Applied: compact
HARP-Cost-Units: 1
HARP-Actual-Ms: 23
x-trace-id: 01HV7P...
```

Response body (compact — no `_actions`, no `_meta.cost`):
```json
{
  "data": { "uid": "abc123", "model_uid": "foo/bar/1.0", "status": "active" },
  "_meta": {
    "tier": "L3",
    "trace_id": "01HV7P...",
    "adaptations": {
      "verbosity": "compact",
      "truncated": false,
      "omitted_fields": ["_actions", "_meta.cost"]
    }
  }
}
```

**Bad: server ignores `HARP-Verbosity: compact`, returns full verbose response, sets no `HARP-Verbosity-Applied`.**

Response body (1200 tokens):
```json
{
  "data": { ... },
  "_meta": { "cost": { ... }, "stability": "stable", "deprecation": null, "etag": "W/\"v5\"" },
  "_actions": [ ... 8 entries with doc_urls and inline examples ... ]
}
```

Agent's context budget was 500 tokens. It receives 1200. The tool output is truncated by the agent runtime. The agent sees partial JSON, fails to parse it, and retries — producing another 1200-token response. The loop continues until context is exhausted.

**Fix:** Honor `HARP-Verbosity: compact` by dropping `_actions`, `_meta.cost`, and non-essential `_meta` fields. Set `HARP-Verbosity-Applied: compact` and declare dropped fields in `_meta.adaptations.omitted_fields`. If the response still exceeds `HARP-Context-Budget`, apply the truncation fallback and set `_meta.truncated`.

## Cross-references

- [Envelope](./01-envelope.md) — `_meta.adaptations` and `_meta.truncated` are fields in the success envelope
- [Write Safety](./04-write-safety.md) — `HARP-Dry-Run` header is part of the header set defined here
- [Long-Running Jobs](./06-long-running.md) — `Retry-After` header guidance applies to job poll responses
- [Audit](./10-audit.md) — `HARP-Causality` header links to audit causality chain
- [Conformance](./13-conformance.md) — capability negotiation adaptation is a mandatory L3 conformance test category

## Limitations and v0.1 caveats

Token counting for `HARP-Context-Budget` enforcement is not standardized: different tokenizers produce different counts for the same JSON body. The spec requires the server to make a best-effort estimate; clients that send `HARP-Context-Budget` MUST tolerate responses slightly above or below the requested budget. Field-mask (selective field projection by the client) is explicitly deferred to v0.2. Compact projection can omit L2 fields, but those omissions MUST be declared in `_meta.adaptations.omitted_fields`; clients that require omitted fields should retry at `normal` or `verbose`. The `HARP-Format: yaml` and `HARP-Format: json-compact` options allow the server to return alternative wire formats, but the spec does not guarantee that all fields round-trip identically in YAML encoding — callers SHOULD prefer `json` for machine consumption.
