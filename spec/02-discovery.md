---
id: harp-discovery
status: draft
normative: true
tier: L2
version: 0.1
depends_on: [harp-envelope]
---

# HARP — Discovery Doc

## Why this exists

Without a discovery document, an agent integrating a new service must make at least five out-of-band calls before it can operate safely: one to fetch the OpenAPI spec, one to infer auth modes, one to check rate limits (usually from headers after the first failure), one to find the error catalog, and one to determine which operations exist. None of these calls are standardized. The agent ends up with service-specific bootstrap logic for every service it integrates.

Human developers face a slower version of the same problem: they navigate docs.service.com, find the authentication page, then the API reference, then the rate limits page, then the error codes page — four browser tabs before writing a line of code. Discovery collapses that to one GET.

Without machine-readable capability declarations, an agent sending `?dryRun=true` to a service that does not support dry-run gets either a 400 or a live mutation, with no prior signal that dry-run is unavailable. Without `capabilities.dry_run: false` in the discovery doc, the agent cannot gate its behavior before making the call.

## Mental model

The closest prior art is the OAuth2 Authorization Server Metadata endpoint (RFC 8414, `/.well-known/oauth-authorization-server`). That endpoint serves a machine-readable document declaring what the auth server supports — grant types, endpoints, signing algorithms. HARP's `/.well-known/harness` is the same pattern applied to the full API surface: capabilities, links, auth modes, budget defaults, and trace configuration in one cacheable document.

Where HARP diverges: OAuth2 metadata is auth-centric. HARP's discovery doc covers the full operational surface of the service — not just how to authenticate, but what the service can do, what it costs, and where everything lives. It is the service's machine-readable README, not just its auth card.

## Specification

### 5. Discovery Doc — `/.well-known/harness`

Single GET. Cacheable. Agent fetches once and knows everything else.

```yaml
harness_version: "0.1"
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

## Per-field rationale

### `harness_version`

Declares the HARP protocol version this discovery doc conforms to.

If absent, a client parsing the discovery doc cannot determine whether the field set it expects is present or whether absent fields are omitted by design. With `harness_version: "0.1"`, a client from a future HARP version knows whether to apply backwards-compat logic. MUST be present. Separate from `service.version` — the protocol version and the service version evolve independently.

### `service.name`

Identifies the service by a stable, lowercase name.

If absent, the discovery doc has no anchor for logging, tracing, or error attribution. Agents embedding multi-service pipelines need stable identifiers per service. MUST be present.

### `service.stability`

Declares the operational maturity of the service (`stable | beta | experimental`).

If absent, agents have no machine-readable signal that a service is pre-production. An agent routing production workloads to an `experimental` service does so knowingly if it reads this field; without it, the distinction requires reading human documentation. SHOULD match the stability declared per-operation in `x-harness.stability`.

### `service.max_tier`

Declares the highest HARP tier the service claims to implement.

If absent, agents cannot gate tier-dependent behavior. An agent trying dry-run on a service with no `max_tier` declaration either tries it speculatively (and gets a live mutation if unsupported) or refuses the operation entirely. `max_tier: L2` is the precise signal that dry-run (L3) is unavailable. MUST be present at L2+.

### `links`

A map of named URLs to service sub-resources.

If absent, agents must hardcode endpoint paths or attempt discovery via OpenAPI path parsing. With `links.openapi`, `links.errors`, `links.scopes`, and `links.audit`, a client can navigate the full service surface from one document. Individual `links` entries SHOULD be present when the corresponding sub-resource exists; they MUST be present when referenced by `capabilities` flags.

### `auth.modes`

Lists the authentication mechanisms the service accepts.

If absent, agents attempt authentication by trial and error — or assume bearer JWT, which fails for API-key-only services. `modes: [bearer_jwt, api_key]` tells the agent which mode to select before the first call. MUST be present.

### `auth.default_scope`

Declares the scope granted to unauthenticated or minimally-authenticated callers.

If absent, agents cannot determine which endpoints are publicly accessible without attempting a call and interpreting the 403 envelope. `default_scope: read:public` makes the baseline entitlement explicit. SHOULD be present if any scope-gated endpoint exists.

### `errors.code_prefix`

Declares the namespace prefix for service-specific error codes.

If absent, a client parsing error codes cannot distinguish service errors from protocol errors. `SCOUTER_DATACARD_NOT_FOUND` vs `HARP_ETAG_MISMATCH` — the prefix is the routing key. Agents that log errors by service need this to attribute correctly. MUST be present when the service emits custom error codes.

### `capabilities`

A boolean map of optional protocol features the service supports.

If absent, agents must speculatively probe each capability. `capabilities.dry_run: false` is a 1-byte instruction that saves a wasted call, an unexpected mutation, and a debugging session. Each capability flag gates a category of agent behavior. MUST be present at L2+ for the capabilities relevant to the declared tier.

### `budgets.default_p99_ms`

Declares the default latency budget for operations that do not override it in `x-harness.cost`.

If absent, agents building timeout policies have no signal from the service on what is normal. An agent setting a 100ms timeout on a service with a 500ms p99 will retry every call — burning quota. SHOULD be present; MAY be omitted if the service provides per-operation overrides for all operations.

### `budgets.rate_limit_per_min`

Declares the default rate limit.

If absent, agents have no prior signal on call rate; they discover the limit by hitting 429. SHOULD be present. Agents SHOULD respect this value proactively rather than waiting for 429.

### `trace.header`

Names the response header that carries the trace ID.

If absent, agents and observability tools cannot correlate requests to distributed traces without guessing the header name (`x-trace-id`, `x-request-id`, `x-b3-traceid`, etc.). MUST be present. SHOULD be `x-trace-id` per HARP convention but the field allows services with existing conventions to declare their actual header.

### `trace.propagation`

Declares the trace context propagation format.

If absent, agents that propagate trace context (for `HARP-Causality` audit chaining) cannot format the header correctly. `w3c_traceparent` is the standard; this field accommodates services using B3 or other formats. SHOULD be present when the service reads incoming trace context.

## Examples

**Good: minimal discovery doc that correctly declares an L1 service with no optional capabilities.**

```yaml
harness_version: "0.1"
service:
  name: my-service
  version: "1.2.0"
  stability: stable
  max_tier: L1
links:
  openapi: /openapi.json
  errors: /.well-known/harness/errors
auth:
  modes: [bearer_jwt]
  default_scope: read:public
errors:
  envelope_schema: /.well-known/harness/envelope.json
  code_prefix: MYSERVICE_
capabilities:
  dry_run: false
  two_phase_commit: false
  long_running: false
  idempotency: false
  optimistic_concurrency: false
  capability_negotiation: false
budgets:
  default_p99_ms: 200
  rate_limit_per_min: 300
trace:
  header: x-trace-id
  propagation: w3c_traceparent
```

**Bad: discovery doc that claims L2 but omits `links.audit` and has no `capabilities` block.**

```yaml
harness_version: "0.1"
service:
  name: my-service
  version: "1.2.0"
  max_tier: L2
links:
  openapi: /openapi.json
auth:
  modes: [api_key]
```

An agent reading this cannot determine whether idempotency, optimistic concurrency, or audit are supported — all of which are L2 requirements. It also cannot navigate to the audit endpoint because `links.audit` is missing. The service claims L2 but cannot be used as L2.

**Fix:** populate all `capabilities` flags honestly, add all `links` entries for declared-tier sub-resources, add `errors.code_prefix` and `budgets`.

## Cross-references

- [Envelope](./01-envelope.md) — `errors.envelope_schema` points to the envelope JSON Schema
- [Auth Scopes](./11-auth-scopes.md) — `links.scopes` points to `/.well-known/harness/scopes`
- [Recipes](./07-recipes.md) — `links.recipes` points to `/.well-known/harness/recipes`
- [Tiers](./12-tiers.md) — `service.max_tier` maps to tier definitions
- [Conformance](./13-conformance.md) — conformance runner reads `/.well-known/harness` as its first step

## Limitations and v0.1 caveats

The discovery doc is not versioned independently — `harness_version` tracks the HARP protocol version, not a document revision. Services that change their capability set between deployments without incrementing `service.version` will serve stale cached discovery docs to clients that respect HTTP caching. v0.1 does not mandate a `Cache-Control` header on the discovery response; implementors SHOULD set `Cache-Control: max-age=300` or shorter. Multi-region services with different capability sets per region (e.g., dry-run in one region, not another) are not addressed in v0.1 — the discovery doc is global.
