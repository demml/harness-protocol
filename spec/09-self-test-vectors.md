---
id: harp-self-test-vectors
status: draft
normative: true
tier: null
version: 0.1
depends_on: [harp-envelope]
---

# HARP — Self-Test Vectors

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
        "body": { "data": {}, "_meta": {}, "_actions": [] }
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

**Substitution grammar inside vectors:** vectors use bare `$NAME` placeholders (distinct from recipes' `${...}` interpolation in [Recipes](./07-recipes.md), which executes at agent runtime against captured state). Vector placeholders are filled by a test runner from a fixture environment (`$TOKEN`, `$UUID`, `$NOW`, `$ETAG_FROM_STEP_<n>`). Conformance test runners MUST resolve these before replay; the spec ships canonical fixture-name conventions in `schemas/vector.json`.

### 15.1 Use Cases

- **Agent self-validation**: agent generates client code, replays vectors against its own client, asserts response shape matches. Catches drift.
- **Conformance testing**: a test suite replays vectors against any server claiming tier compliance.
- **Pattern matching**: agent reads vectors before constructing first call. Beats parsing OpenAPI.
- **Doc generation**: Swagger UI / docs site renders vectors as live examples.

### 15.2 Coverage Requirements

| Tier | Mandatory coverage |
|---|---|
| L1+ | At least one success vector per op |
| L2+ | At least one vector per `possible_errors` entry |
| L3 | One dry-run vector if op supports it; one two-phase preview+commit pair if applicable |

Fixture conventions, including canonical placeholder names (`$TOKEN`, `$UUID`, `$NOW`, `$ETAG_FROM_STEP_<n>`) and shared assets across crate tests, live in the `harp-fixtures` crate. Vector authors and conformance runners both depend on `harp-fixtures` for the canonical names.
