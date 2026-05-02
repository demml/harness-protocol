---
id: harp-envelope
status: draft
normative: true
tier: L1
version: 0.1
depends_on: []
---

# HARP — Canonical Envelope

## 6.1 Error Envelope (every non-2xx response)

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

## 6.2 Success Envelope (every 2xx response)

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

- `data` MUST be present on every 2xx. Empty response: `{"data": null}`.
- `_meta` MUST be present at L1+.
- `_actions` MUST be present at L2+ for ops returning a resource. MAY be empty.
- `_actions[].semantics` MUST use the same vocabulary as `x-harness.semantics` (see [OpenAPI Extensions](./03-openapi-extensions.md)).
- `_actions[].requires_etag` and `requires_two_phase` flag client preconditions inline.
- List responses use `data: [...]` with `_meta.pagination: { next_cursor, total }`.
- `_meta.cost` is the body-side mirror of the `HARP-Cost-Units` and `HARP-Actual-Ms` headers; both header and body MUST be present at L2+. See [Capability Negotiation](./08-capability-negotiation.md) for the full header set.
