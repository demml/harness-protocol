---
id: harp-write-safety
status: draft
normative: true
tier: L3
version: 0.1
depends_on: [harp-envelope, harp-openapi-extensions]
---

# HARP — Write Safety

## Why this exists

An autonomous agent that executes destructive operations without a preview mechanism has no way to discover a mistake before it is permanent. Without dry-run, an agent that calls `DELETE /drift/profiles/foo/bar/1.0` either succeeds (permanent loss) or fails with a validation error — there is no middle path where it can inspect what would happen and decide whether to proceed. In an automated pipeline running at 3am with no human in the loop, the absence of a dry-run path means every destructive operation is a one-shot bet.

The two-phase destructive commit problem is distinct: even when the agent knows what it is deleting, the gap between "agent decided to delete" and "deletion executes" can be exploited by a concurrent modification. Without a signed commitment token, nothing prevents an agent from being tricked (by a malicious caller or a race condition) into confirming a deletion of a different resource than it previewed.

Both mechanisms exist to answer the same question: can this service be trusted to run unattended on destructive operations? L3 compliance means yes — dry-run and two-phase provide the audit surface and the commitment contract that make unattended destructive operations safe.

## Mental model

Dry-run is the same pattern used by `terraform plan`: execute all validation logic, compute the full effect set, return a structured diff — but do not commit. The value is that the caller sees exactly what would change before authorizing the change.

Two-phase destructive commit is analogous to SQL's `BEGIN ... COMMIT` but stateless and HTTP-native. Phase 1 (preview) returns a signed token encoding the operation's identity and a hash of the request body. Phase 2 (commit) submits the token; the server verifies the signature and body hash before executing. This is closest to how payment processors use idempotency tokens with HMAC signing — the token is a time-limited cryptographic commitment to a specific operation on a specific resource.

HARP's divergence from both: the token is stateless (no server-side token store required beyond a small consumed-token cache for replay protection). The server signs the token with its own key, so it can verify it without a database lookup.

## Specification

### 8. Write Safety

#### 8.1 Dry-run

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

#### 8.2 Two-phase Destructive Commit

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
    "effects": []
  }
}
```

Token is a HMAC-signed value:

```
ct_<base32(payload)>.<base32(hmac)>
```

`payload` includes (resource, op, requestor, request_body_hash, expiry_unix).

`hmac` uses a service-secret signing key.

Token TTL default: 5 minutes. Configurable per-op via `x-harness.two_phase_token_ttl_seconds` (see [OpenAPI Extensions](./03-openapi-extensions.md)).

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

## Per-field rationale

### `_meta.dry_run`

Confirms to the caller that this response is a preview, not a committed result.

If absent, a caller cannot determine whether the 200 response it received reflects a real mutation or a dry-run simulation. The flag is the explicit confirmation that no state was changed. MUST be `true` when the request included `?dryRun=true` or `HARP-Dry-Run: 1`.

### `_meta.effects`

An itemized list of state changes the operation would (or did) make.

If absent, dry-run returns a simulated post-state in `data` but does not enumerate what changed to produce it. An agent reviewing a dry-run result needs to know: which resources would be created, updated, or deleted? Which side-effects (cron jobs, notifications, downstream triggers) would fire? Without `effects`, the agent must diff the pre-state and post-state itself — which requires a prior GET. With `effects`, the server performs the diff and returns it atomically. MUST be populated on dry-run responses.

### `confirmation_token`

A cryptographically signed commitment to a specific destructive operation.

If absent (or unsigned), there is nothing preventing the phase-2 commit from being submitted with a modified body — the agent that previewed deletion of profile `foo/bar/1.0` could be tricked into committing deletion of `foo/bar/2.0`. The HMAC binding of (resource, op, requestor, body_hash) makes the token inseparable from the exact operation it authorizes. MUST be present in the phase-1 response.

### `expires_at`

Declares when the confirmation token expires.

If absent, agents do not know whether they have time to complete a human or automated review before the token expires. An agent that delays 10 minutes and then submits a commit for a 5-minute token gets a confusing 410 with no prior warning. `expires_at` gives the agent a deadline it can enforce proactively. MUST be present in the phase-1 response.

## Examples

**Good: dry-run call with full effects list.**

```http
POST /drift/profiles?dryRun=true
Authorization: Bearer $TOKEN
Content-Type: application/json

{ "model_uid": "foo/bar/1.0", "features": ["f1", "f2"], "drift_type": "psi" }
```

```json
{
  "data": { "uid": "preview-only", "status": "would_create" },
  "_meta": {
    "dry_run": true,
    "effects": [
      { "kind": "create", "resource": "drift/profiles/foo/bar/1.0", "summary": "would create new PSI profile with 2 features" },
      { "kind": "side_effect", "resource": "scheduler/cron", "summary": "would register hourly drift scan" }
    ],
    "tier": "L3",
    "trace_id": "01HV7P..."
  }
}
```

**Bad: server ignores `?dryRun=true`, mutates state, returns 201 without `_meta.dry_run`.**

```http
POST /drift/profiles?dryRun=true
```

Response:
```json
{ "data": { "uid": "real-uid-abc123", "status": "created" }, "_meta": { "tier": "L3" } }
```

The agent has no way to tell this is a real creation, not a preview. It proceeds believing no mutation occurred. The profile now exists permanently.

**Fix:** Honor `?dryRun=true` by skipping the database write, setting `_meta.dry_run: true`, and populating `_meta.effects`. If dry-run is not supported, return 400 with `code: HARP_DRY_RUN_NOT_SUPPORTED` and set `x-harness.dry_run: false` in the OpenAPI spec.

**Good: two-phase commit flow.**

Phase 1:
```http
POST /drift/profiles/foo/bar/1.0/delete?phase=preview
Authorization: Bearer $TOKEN
```

```json
{
  "data": {
    "confirmation_token": "ct_AABBCC.DDEEFF",
    "expires_at": "2026-05-02T19:19:00Z"
  },
  "_meta": { "preview": true, "effects": [{ "kind": "delete", "resource": "drift/profiles/foo/bar/1.0", "summary": "would permanently delete profile and 14 associated alert configs" }] }
}
```

Phase 2 (after agent reviews effects):
```http
POST /drift/profiles/foo/bar/1.0/delete?phase=commit&confirmation_token=ct_AABBCC.DDEEFF
Authorization: Bearer $TOKEN
```

**Bad: direct DELETE without two-phase on an L3 service.**

```http
DELETE /drift/profiles/foo/bar/1.0
Authorization: Bearer $TOKEN
```

Response: 405 or service-specific error — the direct DELETE route does not exist at L3 for `two_phase: true` operations. The agent wasted a call and has no confirmation token to proceed with.

## Cross-references

- [Envelope](./01-envelope.md) — `_meta.dry_run` and `_meta.effects` extend the success envelope
- [OpenAPI Extensions](./03-openapi-extensions.md) — `x-harness.dry_run` and `x-harness.two_phase` declare support; `x-harness.two_phase_token_ttl_seconds` sets token lifetime
- [Capability Negotiation](./08-capability-negotiation.md) — `HARP-Dry-Run` request header
- [Conformance](./13-conformance.md) — dry-run no-mutation and two-phase token semantics are mandatory L3 conformance tests

## Limitations and v0.1 caveats

The dry-run contract requires the server to simulate all effects, including side-effects to external systems (cron registration, notifications, downstream triggers). Services with deep side-effect graphs may find `_meta.effects` difficult to populate completely. v0.1 does not require effects to be exhaustive — they MUST be present and non-empty but MAY omit effects the server cannot safely simulate without actually executing them. Partial effects lists SHOULD be annotated with `_meta.effects_partial: true`. The consumed-token cache required for replay protection is mandated by the spec but the cache implementation is left to the service. In-process memory caches do not survive restart; services MUST use durable storage (Redis, Postgres) for the consumed-token cache in production deployments.
