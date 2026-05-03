---
id: harp-self-test-vectors
status: draft
normative: true
tier: null
version: 0.1
depends_on: [harp-envelope]
---

# HARP — Self-Test Vectors

## Why this exists

OpenAPI examples show what a request or response _looks like_. They are not executable: they contain placeholder values, they don't declare expected status codes, and they don't pair a request with its response. An agent that reads OpenAPI examples knows the shape of the data but cannot verify that it is calling the API correctly without making a live call and interpreting the result.

Without self-test vectors, agents constructing their first call to an operation must either guess (by reading the schema and filling in values) or make a test call against a live service. Both approaches fail: schema-derived guesses omit semantic constraints not expressible in JSON Schema (e.g., the model must exist before the profile can be registered), and live test calls produce real side effects.

Conformance testing without vectors requires brute-force injection: a test tool must generate all possible error conditions from first principles, which is slow, incomplete, and service-specific. Vectors give the conformance runner exact inputs and expected outputs — a complete, executable specification of every declared behavior.

The distinction from OpenAPI examples is deliberate: vectors are paired (request + response), versioned with the service, executable against a live instance with fixture substitution, and carry coverage requirements per tier. An OpenAPI example is documentation. A self-test vector is a contract.

## Mental model

Self-test vectors are the API equivalent of snapshot tests in a unit test suite. A snapshot test captures the expected output of a function and asserts that future runs produce the same output. A self-test vector captures the expected response to a specific request and asserts that the live service produces the same response.

The fixture substitution mechanism (`$TOKEN`, `$UUID`, `$NOW`, `$ETAG_FROM_STEP_<n>`) is analogous to test fixtures in testing frameworks — environment-specific values that are injected at runtime but are not part of the vector's normative content.

Where vectors differ from contract tests (e.g., Pact): Pact tests are generated from consumer-provider interactions and verified against both sides. Vectors are server-authored, single-source-of-truth contracts. The server publishes the vectors; any consumer (agent, conformance runner, documentation system) executes them. There is no consumer-side negotiation.

## Specification

### 15. Self-Test Vectors

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
        "body": { "uid": "...", "status": "active" }
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

## Per-field rationale

### `operation_id`

Links the vector document to the OpenAPI operation it tests.

If absent, the conformance runner cannot resolve the vector file to an operation in the OpenAPI spec. `operation_id` MUST match the `operationId` field in the OpenAPI spec. The `harp lint` tool validates this link.

### `version`

The service version that generated this vector set.

If absent, consumers cannot determine whether the vectors are stale relative to the deployed service. A version mismatch (vectors from `0.9.0`, service at `0.10.2`) is a conformance warning — not necessarily a failure if the operation is backwards-compatible. SHOULD be updated whenever the operation's contract changes.

### `vectors[].name`

A stable human-readable identifier for this vector within the operation.

If absent, test output refers to vectors by index — "vector 3 failed" — which requires counting to find the vector in the source file. Named vectors produce output like "failure_duplicate failed", which is immediately actionable. MUST be unique within the vector set.

### `vectors[].request`

The full request definition including method, path, headers, and body.

If absent, the vector is a response-only snapshot with no replay capability. A vector without a request can be used for documentation but not for conformance testing or agent self-validation. MUST be present on every vector intended for replay.

### `vectors[].response`

The expected response including status code, required headers, and body shape.

If absent, the vector is a request template with no assertion target. A conformance runner cannot assert correctness without knowing what the expected response is. MUST be present on every conformance vector. Body shape assertions MAY be partial (subset match) rather than exact — this allows the service to add response fields without breaking vector compatibility.

### `vectors[].tier_required`

The minimum service tier required to replay this vector.

If absent, a conformance runner cannot skip vectors that require capabilities the service does not implement. A `dry_run_psi` vector replayed against an L1 service fails with a "not supported" response — not a conformance violation, but a false failure in the report. `tier_required: "L3"` tells the runner to skip this vector for L1 and L2 services. SHOULD be set on every vector; defaults to `"L1"` if omitted.

### Placeholder names (`$TOKEN`, `$UUID`, `$NOW`, `$ETAG_FROM_STEP_<n>`)

Canonical names for fixture values that are environment-specific.

If non-canonical names are used (e.g., `$MY_TOKEN`, `$RANDOM_ID`), conformance runners built against the `harp-fixtures` convention cannot resolve them. Canonical names ensure interoperability between vectors authored by service teams and runners built by independent tooling. MUST use the canonical set; services MUST NOT define custom placeholder names.

## Examples

**Good: complete vector set for a write operation, covering success, duplicate error, and dry-run.**

```json
{
  "operation_id": "register_drift_profile",
  "version": "0.10.2",
  "vectors": [
    {
      "name": "success_psi_basic",
      "tier_required": "L1",
      "request": {
        "method": "POST",
        "path": "/drift/profiles",
        "headers": { "Authorization": "Bearer $TOKEN", "Idempotency-Key": "$UUID", "Content-Type": "application/json" },
        "body": { "model_uid": "$UUID", "features": ["f1", "f2"], "drift_type": "psi" }
      },
      "response": {
        "status": 201,
        "headers": { "ETag": "W/\"v1\"", "x-trace-id": "$ANY" },
        "body": { "uid": "$ANY", "status": "active" }
      }
    },
    {
      "name": "failure_duplicate",
      "tier_required": "L1",
      "request": {
        "method": "POST",
        "path": "/drift/profiles",
        "headers": { "Authorization": "Bearer $TOKEN", "Content-Type": "application/json" },
        "body": { "model_uid": "$EXISTING_MODEL_UID", "features": ["f1"], "drift_type": "psi" }
      },
      "response": {
        "status": 409,
        "body": { "error": { "code": "SCOUTER_DUPLICATE_PROFILE", "retry": { "retryable": false } } }
      }
    },
    {
      "name": "dry_run_psi",
      "tier_required": "L3",
      "request": {
        "method": "POST",
        "path": "/drift/profiles?dryRun=true",
        "headers": { "Authorization": "Bearer $TOKEN", "Content-Type": "application/json" },
        "body": { "model_uid": "$UUID", "features": ["f1"], "drift_type": "psi" }
      },
      "response": {
        "status": 200,
        "body": { "_meta": { "dry_run": true, "effects": "$NON_EMPTY_ARRAY" } }
      }
    }
  ]
}
```

**Bad: vector with no request, no tier, non-canonical placeholder.**

```json
{
  "operation_id": "register_drift_profile",
  "vectors": [
    {
      "name": "success",
      "response": { "status": 201, "body": { "data": { "uid": "$MY_PROFILE_ID" } } }
    }
  ]
}
```

This vector has no request — it cannot be replayed. The placeholder `$MY_PROFILE_ID` is not canonical — conformance runners will not resolve it. `tier_required` is absent — the runner cannot skip it appropriately. `version` is absent — consumers cannot detect staleness.

**Fix:** Add a complete `request` block, use `$ANY` for any value the runner should not match exactly, set `tier_required`, add `version`.

## Cross-references

- [Envelope](./01-envelope.md) — vectors assert response body shape against the HARP envelope
- [OpenAPI Extensions](./03-openapi-extensions.md) — `x-harness.examples_ref` points to the vector document for each operation
- [Write Safety](./04-write-safety.md) — dry-run and two-phase vectors are required at L3
- [Recipes](./07-recipes.md) — recipes use `examples_ref` pointing to recipe-specific vector documents; recipe vectors have the same format
- [Conformance](./13-conformance.md) — the conformance runner fetches and replays vectors; coverage minimums are enforced by the runner

## Limitations and v0.1 caveats

Vector body assertions in v0.1 are subset-match only — the runner checks that declared fields are present with the expected values but does not fail if additional fields appear in the response. This means a response that adds an undeclared field does not fail any vector. Exact-match assertions are deferred to v0.2. The `$ANY` placeholder (used in the examples above) is a convenience for the conformance runner to accept any value for that field; it is not defined in the `harp-fixtures` canonical set as of v0.1 and MUST be defined before it can be used in normative vectors. Vector file hosting is at the service's discretion — `x-harness.examples_ref` resolves to a URL the service controls; there is no CDN or caching requirement specified.
