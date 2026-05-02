---
id: harp-write-correctness
status: draft
normative: true
tier: L2
version: 0.1
depends_on: [harp-envelope]
---

# HARP — Write Correctness

## Why this exists

Network calls fail. Agents retry. Without idempotency keys, a retry that succeeds after an invisible timeout produces a duplicate: two drift profiles registered, two alert configs created, two billing events emitted. The caller cannot distinguish "first call succeeded, I just didn't see the response" from "first call failed, retry required." The result is either under-retry (accepting data loss) or over-retry (accepting duplicates). Both outcomes are wrong, and the correct behavior — replay the operation safely — requires server support.

Optimistic concurrency (etag) solves a different problem: two concurrent writers on the same resource. Without it, the last write wins silently. An agent that reads a profile, modifies it, and writes it back will silently overwrite any change that occurred between the read and the write. At low traffic this is rare; in a multi-agent or multi-user environment it is a consistent source of data loss.

Both mechanisms exist because they solve different temporal problems. Idempotency keys prevent duplicate effects from retry. ETags prevent silent overwrites from concurrent writes. A correct API needs both.

## Mental model

Idempotency keys are the HTTP-native version of a database upsert keyed on a client-chosen ID. Stripe popularized this pattern for payment APIs — if you send the same `Idempotency-Key` twice, you get the same result, and the second call costs nothing beyond the cache lookup. HARP standardizes the same contract for any write operation.

ETags are HTTP's built-in optimistic concurrency mechanism, defined in RFC 7232. HARP does not invent a new mechanism — it mandates that services which have concurrent write scenarios use the existing HTTP standard correctly. The only HARP-specific addition is mirroring the `ETag` header value into `_meta.etag` in the response body, so agents that miss headers (due to proxy stripping or client library limitations) can still extract the version token.

Where HARP adds a rule RFC 7232 does not: what to put in the error envelope when an `If-Match` fails. RFC 7232 mandates a 412 status code. HARP mandates a 412 with `HARP_ETAG_MISMATCH` code and `_meta.current_etag` so the agent knows the current version and can re-fetch without an additional GET.

## Specification

### 9. Write Correctness

#### 9.1 Idempotency Keys

Applies to ops with `x-harness.idempotent: true`.

Client sends `Idempotency-Key: <uuid>` header. Server MUST:

- Cache `(requestor, op, key) → response` for TTL (default 24h).
- Replay with same body: return cached response (status, body, etag identical).
- Replay with different body: 409 + `HARP_IDEMPOTENCY_KEY_REUSED` envelope; include body hash mismatch detail in `_meta`.
- Scope keys per-(service, requestor, op). Not per-resource: same key on different resources by the same requestor for the same op IS treated as a replay; clients are responsible for choosing fresh keys (UUIDv4 recommended).

Storage MUST be persistent (Redis, Postgres, or equivalent).

#### 9.2 Optimistic Concurrency

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

#### 9.3 Interaction

When both `Idempotency-Key` and `If-Match` are present and the request is a replay: the cached response is served and the etag check is skipped. Original semantics preserved.

## Per-field rationale

### `Idempotency-Key` (request header)

A client-chosen UUID that identifies this logical operation.

If absent on a retried request, the server processes the request as a new operation, producing a duplicate side-effect. With the key present, the server detects the replay and returns the cached result. The cost is a cache lookup — negligible compared to the cost of debugging a duplicate. MUST be a UUID (UUIDv4 recommended); other formats are not guaranteed to be handled correctly.

### Idempotency cache TTL (24h default)

How long the server retains the cached response for a given key.

If too short, retries that arrive after the TTL expire are treated as new requests. If too long, the cache grows unboundedly. 24 hours is the HARP default because it covers the longest reasonable retry window for a network partition event. Services with very high write volume MAY lower this to 1h if storage constraints require it; they MUST document the reduced TTL in the discovery doc.

### `HARP_IDEMPOTENCY_KEY_REUSED`

Error code for a key submitted with a different body than the original.

If the server silently accepted the different body, a race condition could reuse a key to submit a different operation under the original operation's cached identity. The 409 with body-hash mismatch detail tells the client exactly what went wrong — it chose a non-unique key for a different operation, and MUST generate a fresh key.

### `ETag` / `_meta.etag`

A version token for the resource.

If absent from the response, clients performing concurrent writes have no token to include in `If-Match`. Without a token, the server cannot enforce optimistic concurrency — it accepts all writes unconditionally. MUST be present on every read response for resources that support concurrent writes.

### `If-Match` (request header)

The version token the client believes is current.

If absent on a write to a resource that requires etag, the server MUST reject the write (428 Precondition Required) rather than accepting it — accepting writes without `If-Match` on etag-guarded resources would mean the etag contract is not enforced. The only exception is idempotency replay (§9.3), where the etag check is skipped because the cached response is returned.

### `_meta.current_etag` in 412 response

The version token currently on the resource, included in the etag-mismatch error.

If absent, a client that receives 412 must make a GET request to retrieve the current etag before retrying the write. With `current_etag` in the error response, the client has everything it needs to retry in a single round trip. Costs nothing to populate — the server already read the current etag to perform the comparison.

## Examples

**Good: idempotent POST with key, duplicate safely handled.**

First call:
```http
POST /drift/profiles
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
Authorization: Bearer $TOKEN
Content-Type: application/json

{ "model_uid": "foo/bar/1.0", "drift_type": "psi" }
```

Response: 201 Created, `data.uid = "abc123"`.

Retry (network timeout, client unsure if first succeeded):
```http
POST /drift/profiles
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
Authorization: Bearer $TOKEN
Content-Type: application/json

{ "model_uid": "foo/bar/1.0", "drift_type": "psi" }
```

Response: 201 Created, same body, same `data.uid = "abc123"`. No duplicate profile created.

**Bad: retry without idempotency key.**

```http
POST /drift/profiles
Authorization: Bearer $TOKEN
Content-Type: application/json

{ "model_uid": "foo/bar/1.0", "drift_type": "psi" }
```

First call creates profile `abc123`. Network times out. Client retries. Second call creates profile `def456`. Client now has two profiles for the same model. Downstream drift analysis attaches to one; alerts fire from the other.

**Good: optimistic concurrency prevents lost update.**

Read:
```http
GET /drift/profiles/abc123
```
Response: `_meta.etag: W/"v5"`.

Write (another agent modified the resource, etag is now `v6`):
```http
PUT /drift/profiles/abc123
If-Match: W/"v5"
```
Response: 412 + `{ "error": { "code": "HARP_ETAG_MISMATCH" }, "_meta": { "current_etag": "W/\"v6\"" } }`.

Client re-fetches with `current_etag`, merges changes, retries with `If-Match: W/"v6"`. No data lost.

**Bad: write without `If-Match` on a concurrent-write resource.**

```http
PUT /drift/profiles/abc123
Authorization: Bearer $TOKEN
Content-Type: application/json

{ "model_uid": "foo/bar/1.0", "alert_threshold": 0.2 }
```

Server accepts. If another writer changed `alert_threshold` to 0.15 between the read and this write, that change is silently overwritten. No error, no trace in the response.

## Cross-references

- [Envelope](./01-envelope.md) — `_meta.etag` field in the success envelope; `HARP_ETAG_MISMATCH` and `HARP_IDEMPOTENCY_KEY_REUSED` error codes
- [OpenAPI Extensions](./03-openapi-extensions.md) — `x-harness.idempotent` and `x-harness.requires_etag` declare support
- [Write Safety](./04-write-safety.md) — §9.3 interaction: idempotency replay skips etag check
- [Capability Negotiation](./08-capability-negotiation.md) — `Idempotency-Key` and `If-Match` headers appear in the full header reference
- [Conformance](./13-conformance.md) — idempotency replay and etag concurrency are mandatory L2 conformance tests

## Limitations and v0.1 caveats

Idempotency key scoping is per-(service, requestor, op) — not per-resource. This means a client that accidentally reuses a UUID across two different resources on the same op will trigger `HARP_IDEMPOTENCY_KEY_REUSED`. This is intentional (keys MUST be unique per logical operation) but can surprise clients that generate keys from resource IDs rather than random UUIDs. v0.1 does not define a key rotation or expiry notification mechanism — clients learn the TTL only from the discovery doc's implied behavior. Persistent storage for the idempotency cache is REQUIRED but the implementation is left to the service; in-memory caches invalidated on restart violate the contract.
