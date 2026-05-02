---
id: harp-discovery
status: draft
normative: true
tier: L2
version: 0.1
depends_on: [harp-envelope]
---

# HARP — Discovery Doc

## 5. Discovery Doc — `/.well-known/harness`

Single GET. Cacheable. Agent fetches once and knows everything else.

```yaml
harness_version: "1.0"
service:
  name: scouter
  version: "0.10.2"
  stability: stable                 # stable | beta | experimental
  max_tier: L2                      # service compliance ceiling
links:
  openapi: /openapi.json
  recipes: /.well-known/harness/recipes
  examples: /openapi/examples
  errors: /.well-known/harness/errors
  scopes: /.well-known/harness/scopes
  doc_root: https://docs.scouter.ai
  health: /healthz
  audit: /audit
auth:
  modes: [bearer_jwt, api_key]
  default_scope: read:public
errors:
  envelope_schema: /.well-known/harness/envelope.json
  code_prefix: SCOUTER_              # service-specific code namespace
capabilities:
  dry_run: true
  two_phase_commit: false
  long_running: true
  idempotency: true
  optimistic_concurrency: true
  capability_negotiation: false
budgets:
  default_p99_ms: 250
  rate_limit_per_min: 600
trace:
  header: x-trace-id
  propagation: w3c_traceparent
```

`/.well-known/harness/errors`, `/.well-known/harness/scopes`, `/.well-known/harness/recipes`, and `/.well-known/harness/envelope.json` are sub-resources documented in their respective sections:

- Error envelope schema: see [Envelope](./01-envelope.md)
- Scopes: see [Auth Scopes](./11-auth-scopes.md)
- Recipes: see [Recipes](./07-recipes.md)
