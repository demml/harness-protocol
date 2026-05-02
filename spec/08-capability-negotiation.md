---
id: harp-capability-negotiation
status: draft
normative: true
tier: L3
version: 0.1
depends_on: [harp-envelope]
---

# HARP — Capability Negotiation

## 10. Capability Negotiation (L3)

### 10.1 Request Headers

| Header | Values | Purpose |
|---|---|---|
| `HARP-Client` | `<name>/<version> (tier=Lx)` | Agent identity + tier ceiling |
| `HARP-Verbosity` | `compact \| normal \| verbose` | Response shape selector |
| `HARP-Context-Budget` | `<int>` | Max tokens agent can spend on this response |
| `HARP-Format` | `json \| yaml \| json-compact` | Wire format pref |
| `HARP-Locale` | BCP-47 (e.g. `en-US`) | Language for human-facing strings only; codes always English |

Field-mask is out of v1.

### 10.2 Server Behavior

- `compact`: drop `_actions`, drop `_meta.cost`, drop optional `_meta` fields. MUST keep `data`, `error`, `code`, `trace_id`.
- `verbose`: expand `_actions` with inline examples, inline `failure_catalog` for current op, include `recipes_relevant`.
- Context-Budget enforced server-side. If projected response exceeds budget: server applies fallback projection in this order:
  1. Drop `_actions[].doc_url` and recipes.
  2. Drop `_meta.cost` and `_meta.adaptations`.
  3. Truncate `data` arrays. MUST set `_meta.truncated: { dropped: N, total: M }`.
- Server MUST confirm what was applied via response header `HARP-Verbosity-Applied` and `_meta.adaptations`:
  ```json
  "adaptations": { "verbosity": "compact", "truncated": false }
  ```

### 10.3 Full HARP Header Reference

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
