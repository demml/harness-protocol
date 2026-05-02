---
id: harp-openapi-extensions
status: draft
normative: true
tier: L1
version: 0.1
depends_on: [harp-envelope]
---

# HARP — Per-Operation OpenAPI Extension `x-harness`

## 7. Per-Operation OpenAPI Extension `x-harness`

```yaml
paths:
  /drift/profiles:
    post:
      summary: Register drift profile
      x-harness:
        semantics: write              # read | write | destructive | idempotent | long_running
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
- `examples_ref` MUST resolve to a JSON document conforming to the self-test-vector schema (see [Self-Test Vectors](./09-self-test-vectors.md)).
- `deprecation`, when non-null, MUST also surface as `Deprecation` and `Sunset` HTTP headers and a `Link: rel=successor-version` header on responses.
- `cost.p99_ms_budget` MAY override the discovery doc default for this op.
