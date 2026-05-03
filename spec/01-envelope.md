---
id: harp-envelope
status: draft
normative: true
tier: L1
version: 0.1
depends_on: []
---

# HARP — Canonical Envelope

## Why this exists

Without a canonical error shape, every error a service emits is a bespoke artifact. An agent encountering a 400 from Service A parses a `{"message": "..."}` blob. The same agent encountering a 400 from Service B parses `{"errors": [{"field": "...", "code": "..."}]}`. Neither is machine-actionable in a consistent way — the agent must maintain per-service error parsers, and any service not in its training data requires a new parser before the agent can recover from failures.

Human developers face the same problem in operational context: "bad request" as the full error body means opening docs, finding the endpoint, reading parameter descriptions, and guessing which field violated which constraint. At 2am this is expensive. With a HARP envelope it is a lookup.

Without a success envelope, agents navigating multi-step workflows must either hardcode follow-on URLs or parse human documentation to discover them. Without `_actions`, an agent that creates a resource cannot determine how to update or delete it without prior knowledge of the API surface. Without `_meta.cost`, agents operating within token or compute budgets have no feedback loop for rate-limiting their own calls.

The canonical envelope is the single most load-bearing piece of HARP: every other capability (discovery, write safety, recipes, conformance testing) depends on responses speaking a consistent shape.

## Mental model

The closest prior art is RFC 7807 (Problem Details for HTTP APIs), which standardizes the error response shape. HARP's error envelope is a strict superset of RFC 7807: it adds `retry`, `suggested_action`, and `trace_id` fields that RFC 7807 leaves as extensions.

The success envelope is closest to HAL (Hypertext Application Language) with `_links`, but HARP uses `_actions` rather than `_links` because actions carry preconditions (`requires_etag`, `requires_two_phase`, `semantics`) that hypermedia link relations do not encode. An agent reading `_actions` knows not just _where_ to go but _whether_ it is safe to go there and under what conditions.

The `_meta` wrapper is analogous to HTTP response headers that carry protocol metadata, but placed in the body where agents reliably read it. This is deliberate: headers are frequently stripped by proxies, logged selectively, and absent from serialized response examples. Body metadata survives all of these.

## Specification

### 6.1 Error Envelope (every non-2xx response)

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

### 6.2 Success Envelope (L2+ every 2xx response)

```json
{
  "data": { },
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
- `_actions[].semantics` MUST use the same vocabulary as `x-harness.semantics` (see [OpenAPI Extensions](./03-openapi-extensions.md)).
- `_actions[].requires_etag` and `requires_two_phase` flag client preconditions inline.
- `_actions[].preview_href` and `_actions[].commit_href` MUST be present when `requires_two_phase: true`.
- List responses use `data: [...]` with `_meta.pagination: { next_cursor, total }`.
- `_meta.cost` is the body-side mirror of the `HARP-Cost-Units` and `HARP-Actual-Ms` headers; both header and body MUST be present at L2+. See [Capability Negotiation](./08-capability-negotiation.md) for the full header set.

## Per-field rationale

### `error.code`

Carries a stable, namespaced identifier for the failure condition.

If absent, clients must branch on `message` strings, which are prose and unstable across releases. A code like `SCOUTER_DATACARD_NOT_FOUND` is a stable lookup key; "DataCard 'foo/bar/1.0' not found" is a display string that may change with a documentation rewrite. Costs nothing to populate — it is set at the throw site. MUST always be present.

### `error.field`

Names the specific field that caused the failure.

If absent, a validation error returns "bad request" and the client must retry with permutations to find the offending field. JSON-pointer format (`/model_uid`, `/features/0/name`) is unambiguous and machine-navigable. SHOULD be set whenever a specific field is implicated; null is correct for non-field errors (auth failure, rate limit).

### `error.hint`

A one-sentence corrective instruction for the caller.

If absent, the client reads `message` (which describes what happened) and has no signal on what to do differently. Hint is not a prose essay — it is a single actionable sentence. SHOULD be populated when the recovery action is deterministic (register the dependency, re-fetch with correct etag, check scope).

### `error.doc_url`

A URL to the canonical documentation for this error code.

If absent, agents that cannot recover from the error have no escalation path. The URL SHOULD resolve to a page that explains the error in full, lists common causes, and shows a recovery example. MAY be omitted only when no stable doc URL exists (e.g. experimental endpoints).

### `error.retry`

Carries the retry policy for this specific failure.

If absent, clients apply either a blanket retry (wrong for non-retryable errors — causes duplicate side effects) or no retry (wrong for transient 503s). The `retryable` flag is the decision gate. `after_ms` gives the minimum wait before retry; if null, client chooses. `max_attempts` bounds the retry loop. Together they eliminate the retry policy from harness code and put it in the response.

### `error.suggested_action`

Points to the operation and example that resolves the failure.

If absent, the agent knows a precondition failed but not which API call satisfies it. With `suggested_action.operation = "POST /datacards"` and `example_url = "/openapi/examples/create_datacard"`, an agent can navigate to the resolution without parsing prose. SHOULD be populated when recovery requires a specific API call.

### `error.trace_id`

Correlates this error to the distributed trace for the request.

If absent, support engineers cannot find the server-side log entry for a failure report. Must match `x-trace-id` response header — they are the same trace, surfaced in two places because headers are sometimes stripped in transit. MUST always be present.

### `_meta.schema_ref`

Points to the JSON Schema that validates the `data` field.

If absent, agents validating the response shape must hardcode schema paths or skip validation entirely. A resolvable schema ref enables programmatic validation without prior knowledge of the service's schema layout. MUST be present in L1 error envelopes and L2+ success envelopes.

### `_meta.tier`

Declares which HARP tier this response conforms to.

If absent, agents cannot verify that the response they received matches the tier they expect. Useful when a service partially implements a tier — the response itself declares what is guaranteed. MUST be present in L1 error envelopes and L2+ success envelopes.

### `_meta.cost`

Reports the actual latency and compute cost of the call, alongside the declared budget.

If absent, agents operating under budget constraints have no feedback loop. A call that consumes 800ms against a 250ms budget signals that the service is under load or the request was expensive; the agent can back off. `actual_ms` compared to `p99_ms_budget` is an inline SLO signal. MUST be present at L2+; SHOULD be omitted at L1 where cost tracking is not required.

### `_meta.etag`

Carries the resource version for optimistic concurrency.

If absent from the success envelope, clients must parse the `ETag` response header to get this value. Headers are stripped by some proxies and HTTP clients. Body placement guarantees delivery. MUST match the `ETag` header when both are present. See [Write Correctness](./05-write-correctness.md).

### `_meta.deprecation`

Carries the deprecation signal for this response's schema version.

If absent, agents and developers have no machine-readable signal that an operation is being retired. With `deprecation.since`, `deprecation.sunset`, and `deprecation.successor`, a client can emit a warning, log the sunset date, and migrate proactively. Null when not deprecated. When non-null, MUST also appear as `Deprecation` and `Sunset` headers.

### `_actions[].rel`

Names the relationship of this action to the current resource.

If absent, `_actions` is a list of anonymous URLs with no semantic meaning. With `rel = "update"`, `"delete"`, `"alerts"`, an agent selects the action it needs without hardcoding position. Standard relation names SHOULD follow IANA link relation registry where a relation exists; service-specific relations are allowed.

### `_actions[].requires_etag`

Signals that the client MUST supply `If-Match` to execute this action.

If absent, an agent attempting an update without `If-Match` receives a 428 (or service-defined error) and must retry with the etag — burning a round trip. With `requires_etag: true`, the agent knows to extract the etag from `_meta.etag` and include it before making the call. Set this wherever the operation is guarded by optimistic concurrency.

### `_actions[].requires_two_phase`

Signals that the client MUST execute a preview + commit sequence for this action.

If absent on a destructive action, an agent may attempt a direct `DELETE`, which will fail at L3 or execute permanently at a non-L3 service. `requires_two_phase: true` is the machine-readable instruction to route through the two-phase flow defined in [Write Safety](./04-write-safety.md). When true, `preview_href` and `commit_href` remove URL derivation from client code; agents follow those hrefs literally.

## Examples

**Good error (recoverable, field named, action provided):**

```json
{
  "error": {
    "message": "DataCard 'foo/bar/1.0' not found",
    "code": "SCOUTER_DATACARD_NOT_FOUND",
    "field": "datacard_uid",
    "hint": "Register DataCard before linking from ModelCard",
    "doc_url": "https://docs.scouter.ai/errors/SCOUTER_DATACARD_NOT_FOUND",
    "retry": { "retryable": false, "after_ms": null, "max_attempts": 0 },
    "suggested_action": {
      "operation": "POST /datacards",
      "example_url": "/openapi/examples/create_datacard"
    },
    "trace_id": "01HV7P...",
    "occurred_at": "2026-05-02T19:14:00Z"
  },
  "_meta": { "schema_ref": "/.well-known/harness/envelope.json", "tier": "L1", "service_version": "0.10.2" }
}
```

**Bad error (non-HARP, no code, no field, no action, no trace):**

```json
{
  "message": "Not found"
}
```

The agent receives this, has no stable code to branch on, no field to correct, no suggested action, and no trace ID to report in a support ticket. Recovery requires human intervention or a hardcoded service-specific parser.

**Fix:** Emit the full HARP error envelope at every non-2xx path. "Not found" becomes `SCOUTER_DATACARD_NOT_FOUND` with field, hint, and suggested action populated.

**Bad success (flat body, no envelope):**

```json
{
  "uid": "abc123",
  "model_uid": "foo/bar/1.0",
  "status": "active"
}
```

The agent has the data but does not know how to update or delete it, does not know the etag for concurrency control, and cannot verify the response tier. A subsequent write will fail with a 428 because the agent did not know to capture the etag.

**Fix:**

```json
{
  "data": { "uid": "abc123", "model_uid": "foo/bar/1.0", "status": "active" },
  "_meta": { "schema_ref": "...", "tier": "L2", "etag": "W/\"v1\"", "trace_id": "...", "occurred_at": "..." },
  "_actions": [
    { "rel": "update", "method": "PUT", "href": "/drift/profiles/abc123", "requires_etag": true, "semantics": "write" },
    {
      "rel": "delete",
      "method": "DELETE",
      "href": "/drift/profiles/abc123",
      "requires_two_phase": true,
      "preview_href": "/drift/profiles/abc123/delete?phase=preview",
      "commit_href": "/drift/profiles/abc123/delete?phase=commit&confirmation_token={confirmation_token}",
      "semantics": "destructive"
    }
  ]
}
```

## Cross-references

- [OpenAPI Extensions](./03-openapi-extensions.md) — `possible_errors` and `semantics` referenced from `_actions`
- [Write Safety](./04-write-safety.md) — `_meta.dry_run` and `_meta.effects` added to success envelope for dry-run responses
- [Write Correctness](./05-write-correctness.md) — `_meta.etag` and `If-Match` / `ETag` header alignment
- [Capability Negotiation](./08-capability-negotiation.md) — `HARP-Cost-Units`, `HARP-Actual-Ms` headers that mirror `_meta.cost`
- [Audit](./10-audit.md) — `trace_id` and `_meta.trace_id` correlation
- [Auth Scopes](./11-auth-scopes.md) — `HARP_INSUFFICIENT_SCOPE` error code uses this envelope; `_meta.required_scopes` added on 403

## Limitations and v0.1 caveats

`_actions` at L2+ covers resource-returning responses only. List responses include `_actions` at the collection level, not per-item. Per-item actions in paginated lists require a second GET per item, which is not addressed in v0.1. The `_meta.cost.compute_units` field is defined in the OpenAPI extension but the body-side field in `_meta.cost` only carries `p99_ms_budget` and `actual_ms` in this version; compute unit tracking in the body is deferred to v0.2.
