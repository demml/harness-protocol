---
id: harp-openapi-extensions
status: draft
normative: true
tier: L1
version: 0.1
depends_on: [harp-envelope]
---

# HARP — Per-Operation OpenAPI Extension `x-harness`

## Why this exists

OpenAPI 3.1 describes the shape of requests and responses. It does not describe what an operation _does_ — whether it is safe to retry, whether it mutates state, whether it accepts a dry-run, what it costs to call, which error codes it can emit, or when it will be removed. That information either lives in human prose (which agents cannot reliably parse) or is absent entirely.

Without `x-harness.semantics`, an agent cannot distinguish a `POST` that creates a resource from a `POST` that triggers a destructive batch job. Both look identical in OpenAPI. The agent must treat every `POST` as potentially dangerous or read the human summary string and guess.

Without `x-harness.possible_errors`, conformance testing of the error envelope requires running every conceivable invalid input and hoping to hit each error code. The failure catalog makes the contract explicit and testable.

Without `x-harness.examples_ref`, agents constructing their first call to an operation have no canonical example to pattern-match against. OpenAPI `examples` are useful but not machine-executable in the structured way HARP vectors define.

## Mental model

`x-harness` is an extension to the OpenAPI Specification object model, following OpenAPI 3.1's extension mechanism (vendor-prefix keys starting with `x-`). The closest prior art is Stripe's use of OpenAPI extensions to carry Stripe-specific operation metadata — they annotate operations with `x-stripeOperationId`, `x-stripeDocuments`, and similar fields that the OpenAPI Specification does not define but their tooling consumes.

HARP's divergence: the `x-harness` block is formally specified with a normative JSON Schema (`harness.schema.json`), so it is not just a private Stripe-style extension — it is a published contract that any HARP-compatible tool can validate and consume. The `harp lint` tool validates every `x-harness` block against this schema; the `harp test` tool uses `possible_errors` to drive conformance test coverage.

## Specification

### 7. Per-Operation OpenAPI Extension `x-harness`

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

## Per-field rationale

### `semantics`

Declares the operational category of this endpoint.

If absent, agents cannot distinguish safe reads from destructive mutations in the OpenAPI spec alone — they must parse the human `summary` string. `semantics: destructive` is the machine-readable signal that an operation requires additional precautions (two-phase, human confirmation, dry-run preview). The full vocabulary (`read | write | destructive | idempotent | long_running`) is the same used in `_actions[].semantics`, creating a consistent contract between the spec and the runtime response. MUST be set at L1+; no cost beyond authorship.

### `stability`

Declares whether this operation is safe for production use.

If absent, agents treating an `experimental` endpoint as `stable` will embed a dependency they cannot rely on. Agents reading `stability: beta` can include a warning in generated code. SHOULD be set on every operation; defaults to `stable` if omitted and the service does not otherwise signal instability.

### `idempotent`

Declares that this operation accepts an `Idempotency-Key` header.

If absent, clients must either always send `Idempotency-Key` speculatively (and handle the case where the service ignores it) or never send it (and accept duplicate-side-effect risk on retry). `idempotent: true` is the explicit contract that the server will honor the key. Costs nothing to declare. SHOULD be set to `true` for any non-read operation that is safe to replay.

### `requires_etag`

Declares that write operations on this resource require `If-Match`.

If absent, agents writing to a shared resource don't know whether to include `If-Match`. They omit it, the write succeeds, and they silently overwrite a concurrent modification. With `requires_etag: true`, agents know to capture the etag from the prior read and include it in the write. Prevents lost-update bugs with zero client-side guessing.

### `dry_run`

Declares that this operation accepts `?dryRun=true` or `HARP-Dry-Run: 1`.

If absent, agents cannot determine whether dry-run is supported before sending it. A false positive (sending dry-run to a service that ignores it) produces a live mutation the agent believes was a preview. This is one of the highest-impact correctness failures for autonomous agents. MUST be set to `true` only when the server fully implements the dry-run contract defined in [Write Safety](./04-write-safety.md).

### `two_phase`

Declares that destructive operations require the two-phase preview + commit sequence.

If absent on a destructive op, agents and humans have no machine-readable signal that a direct `DELETE` will be rejected. The field also gates `_actions[].requires_two_phase` in runtime responses. MUST be set for any operation declared `semantics: destructive` at L3.

### `two_phase_token_ttl_seconds`

Overrides the default 5-minute TTL for the HMAC confirmation token.

If absent, the default 300s applies. Set shorter for high-sensitivity operations where staleness is dangerous. Set longer for operations where the human or agent review cycle takes more than 5 minutes. MAY be omitted; default applies.

### `long_running`

Declares that this operation returns 202 and a job ID rather than a synchronous response.

If absent, clients that expect a synchronous 200 will time out waiting for a response that will never arrive synchronously. With `long_running: true`, clients know to follow the poll / webhook pattern defined in [Long-Running Jobs](./06-long-running.md). MUST be set for any operation that returns 202.

### `cost.p99_ms_budget`

Declares the expected p99 latency for this specific operation.

If absent, clients use the discovery doc default (`budgets.default_p99_ms`), which may be wrong for operations that are significantly faster or slower than average. A `POST /drift/profiles` that runs a background profiling job has a different p99 than `GET /drift/profiles/:id`. Per-op budgets let clients set appropriate timeouts. MAY omit if the discovery doc default is accurate.

### `cost.compute_units`

Declares the compute cost of this operation relative to a normalized unit.

If absent, clients with compute-budget constraints cannot pre-check whether they have budget before calling. This is especially relevant for agents running in constrained execution environments. MAY be omitted if the service does not track compute cost per operation.

### `scopes_required`

Lists the scope(s) required to call this operation.

If absent, agents cannot determine whether their current token is sufficient before making the call. A 403 `HARP_INSUFFICIENT_SCOPE` after a write attempt is more expensive than checking `scopes_required` against the token's `granted_scopes` before the call. MUST be set at L1+.

### `possible_errors`

Exhaustive list of error codes this operation can return.

If absent, conformance testing of the error envelope requires brute-force injection rather than targeted replay. Agents building fallback logic cannot enumerate the failure modes without reading human documentation. MUST be exhaustive at L1+. "Exhaustive" means every code that the server can return from this endpoint is listed — not just common cases.

### `examples_ref`

URL to the canonical self-test vectors for this operation.

If absent, agents constructing their first call have no structured example to pattern-match against, and the conformance runner cannot locate the vectors for this op. MUST resolve to a valid vector document. The vector document format is defined in [Self-Test Vectors](./09-self-test-vectors.md).

### `deprecation`

Carries the deprecation signal for this operation.

If absent when an operation is being retired, callers have no machine-readable signal before the endpoint is removed. `deprecation.since` marks when the deprecation began; `deprecation.sunset` is the removal date; `deprecation.successor` is the replacement operation ID. When non-null, MUST also appear as `Deprecation` and `Sunset` headers on every response from this endpoint.

### `related_recipes`

Lists recipe IDs that use this operation.

If absent, agents navigating from an error on this endpoint cannot discover that a multi-step recovery workflow exists. `related_recipes: [register_drift_workflow]` connects the single-operation contract to the multi-step workflow. MAY be omitted if no recipes reference this operation.

## Examples

**Good: fully annotated write operation.**

```yaml
paths:
  /drift/profiles:
    post:
      summary: Register drift profile
      x-harness:
        semantics: write
        stability: stable
        idempotent: true
        requires_etag: false
        dry_run: true
        two_phase: false
        long_running: false
        cost:
          p99_ms_budget: 300
          compute_units: 1
        scopes_required: [drift:write]
        possible_errors:
          - SCOUTER_VALIDATION
          - SCOUTER_DUPLICATE_PROFILE
          - SCOUTER_AUTH_FORBIDDEN
        examples_ref: /openapi/examples/register_profile
        deprecation: null
        related_recipes: [register_drift_workflow]
```

**Bad: `semantics` missing, `possible_errors` incomplete.**

```yaml
paths:
  /drift/profiles:
    post:
      summary: Register drift profile
      x-harness:
        dry_run: true
        scopes_required: [drift:write]
```

An agent reading this does not know whether this is a safe write or a destructive operation. The conformance test cannot verify error envelope coverage because `possible_errors` is absent. `harp lint` will exit non-zero on both violations.

**Fix:** Add `semantics: write` and enumerate every error code the endpoint can emit in `possible_errors`.

## Cross-references

- [Envelope](./01-envelope.md) — `_actions[].semantics` vocabulary is the same as `x-harness.semantics`
- [Write Safety](./04-write-safety.md) — `dry_run` and `two_phase` fields enable the flows defined there
- [Write Correctness](./05-write-correctness.md) — `idempotent` and `requires_etag` fields enable the flows defined there
- [Long-Running Jobs](./06-long-running.md) — `long_running: true` triggers the 202 + poll pattern
- [Self-Test Vectors](./09-self-test-vectors.md) — `examples_ref` points to vector documents
- [Auth Scopes](./11-auth-scopes.md) — `scopes_required` uses the scope grammar defined there
- [Recipes](./07-recipes.md) — `related_recipes` references recipe IDs from the recipes catalog

## Limitations and v0.1 caveats

`x-harness` is validated by `harp lint` but is not enforced by the OpenAPI toolchain itself — OpenAPI 3.1 passes unknown extension keys through without validation. Services MUST integrate `harp lint` into their CI pipeline to catch missing or malformed `x-harness` blocks. The `compute_units` field is defined but no normalization baseline is specified in v0.1; services may use service-relative units. A cross-service unit standard is deferred to v0.2.
