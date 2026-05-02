---
id: harp-write-correctness
status: draft
normative: true
tier: L2
version: 0.1
depends_on: [harp-envelope]
---

# HARP — Write Correctness

## 9. Write Correctness

### 9.1 Idempotency Keys

Applies to ops with `x-harness.idempotent: true`.

Client sends `Idempotency-Key: <uuid>` header. Server MUST:

- Cache `(requestor, op, key) → response` for TTL (default 24h).
- Replay with same body: return cached response (status, body, etag identical).
- Replay with different body: 409 + `HARP_IDEMPOTENCY_KEY_REUSED` envelope; include body hash mismatch detail in `_meta`.
- Scope keys per-(service, requestor, op). Not per-resource: same key on different resources by the same requestor for the same op IS treated as a replay; clients are responsible for choosing fresh keys (UUIDv4 recommended).

Storage MUST be persistent (Redis, Postgres, or equivalent).

### 9.2 Optimistic Concurrency

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
