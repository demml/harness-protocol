---
id: harp-write-safety
status: draft
normative: true
tier: L3
version: 0.1
depends_on: [harp-envelope, harp-openapi-extensions]
---

# HARP — Write Safety

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

### 8.2 Two-phase Destructive Commit

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
