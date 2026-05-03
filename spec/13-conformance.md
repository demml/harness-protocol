---
id: harp-conformance
status: draft
normative: true
tier: null
version: 0.1
depends_on: [harp-self-test-vectors]
---

# HARP — Conformance Test Suite

## Why this exists

A protocol without a conformance suite is a wish list. Without machine-executable conformance tests, every service that claims a tier is self-reporting with no verification. "We support L2" from a service team means their engineers believe they implemented it — not that it actually works under the conditions agents depend on.

The cost of undiscovered non-conformance is asymmetric: it's cheap for the service team to miss a rule ("we didn't know HARP_ETAG_MISMATCH needed `_meta.current_etag`") and expensive for every agent that integrates the service expecting L2 semantics. One missed rule can silently break dozens of independent integrations.

The conformance suite also serves as a forcing function for completeness: a service team that runs `harp test --url` against their staging deployment before declaring a tier gets precise violation reports rather than discovering gaps when an agent integration fails in production. The test is cheap to run and catches the problems that are invisible to manual review.

For agents, the conformance suite outputs a machine-readable tier verdict and violation list that the service can publish in its discovery doc. An agent reading `effective_tier: L2, violations: []` has a stronger guarantee than one reading `max_tier: L2` (self-declared, unverified).

## Mental model

The conformance suite is a black-box test harness: it treats the service as an external dependency and tests it purely through its public HTTP interface. It does not require access to the service's source code, database, or internal metrics. This is the right model for a vendor-neutral protocol: any service in any language can be tested by the same runner.

The test categories map directly to tier requirements. Each category corresponds to a normative rule in the spec. A violation links back to the specific section and rule that failed — so the service team knows exactly what to fix.

This is closest to API conformance testing tools like Dredd (which tests OpenAPI specs against live servers) or Schemathesis (which generates test cases from OpenAPI schemas). HARP's conformance suite goes further: it tests not just schema conformance but semantic behavior (dry-run does not mutate, idempotency replay returns cached response, etag mismatch returns `_meta.current_etag`).

## Specification

### 18. Conformance Test Suite

Lives in `harness-protocol/conformance/`. Generic harness in any language; reference impl in Rust + Python.

#### 18.1 Inputs

- Service base URL.
- Auth credentials (service's choice of mode).
- Declared tier from `/.well-known/harness`.

#### 18.2 Test Categories

| Category | Tier | Scope |
|---|---|---|
| Discovery doc shape | L1+ | Validate against `discovery.json` schema |
| Error envelope on synthetic errors | L1+ | Trigger every `possible_errors` entry per op via vector replay |
| Success envelope on synthetic happy path | L2+ | Validate `data`, `_meta` presence, `_meta.trace_id` consistency |
| Action affordances correctness | L2+ | Follow `_actions[]` rels, verify reachable, verify required preconditions match |
| Idempotency replay semantics | L2+ | Replay same key + same body, replay + different body |
| Etag concurrency | L2+ | Stale `If-Match` returns 412 + envelope |
| Cost headers + body mirror | L2+ | Header / body parity |
| Audit trail correctness | L2+ | Write op produces audit row reachable via `/audit/trace/{trace_id}` |
| Dry-run no-mutation | L3 | Dry-run + immediate read shows no state change |
| Two-phase token semantics | L3 | Expired token rejected; reused token rejected; replay rejected |
| Long-running poll-to-completion | L3 | Submit, poll to terminal, fetch result, cancel |
| Capability negotiation adaptation | L3 | `compact` strips correctly; `verbose` expands; budget enforces; `HARP-Verbosity-Applied` echoes |
| Self-test vector roundtrip | L3 | Every vector replayable against the live service |
| Recipe DAG executability | L3 | Each recipe DAG `operation_id` resolvable via OpenAPI ops; `body_template` interpolation parseable |

#### 18.3 Output

```json
{
  "service": "scouter",
  "declared_tier": "L2",
  "results": {
    "L1": { "passed": 47, "failed": 0, "skipped": 0 },
    "L2": { "passed": 22, "failed": 1, "skipped": 0 },
    "L3": { "passed": 0,  "failed": 0, "skipped": 14 }
  },
  "violations": [
    {
      "section": "harp-audit",
      "rule": "MUST audit every write op",
      "evidence": "trace_id=01HV7P... not found in /audit/trace endpoint"
    }
  ],
  "tier_attained": "L1"
}
```

`tier_attained` is the highest tier with zero failures. Service MAY publish this in the discovery doc as `effective_tier`.

#### 18.4 Self-Test Vector Conformance

The conformance runner MUST:

- Fetch `/.well-known/harness` to determine declared tier.
- For each op with `x-harness.examples_ref`, fetch the referenced vector file.
- Replay every vector against the live service with fixture substitution (`$TOKEN`, `$UUID`, `$NOW`, `$ETAG_FROM_STEP_<n>`).
- Assert response status, body shape, and required headers match vector expectations.
- Report per-vector pass/fail in the structured output.

Coverage minimums enforced by the runner (see [Self-Test Vectors](./09-self-test-vectors.md) §15.2):

- L1+: at least one success vector per op
- L2+: at least one vector per `possible_errors` entry
- L3: one dry-run vector if op supports it; one two-phase preview+commit pair if applicable

## Per-field rationale

### Test inputs: base URL + auth credentials

The minimum set of inputs to test a real deployed service.

If the conformance runner required internal access (database, source code), it could not be run by an independent third party. Black-box testing via URL + credentials is the model that enables vendor-neutral conformance claims. The runner authenticates using the service's declared `auth.modes` from the discovery doc.

### Test categories: tier-scoped

Tests are grouped by tier so the runner only executes tests relevant to the declared tier.

If all tests ran for all services regardless of tier, an L1 service would fail L3 tests and produce a noisy report with false violations. Tier-scoped categories produce clean reports: L1 tests pass/fail for L1 services, L2 tests are run only for services claiming L2+, etc. The `skipped` count in the output makes the tier scoping visible.

### `violations[].section`

Names the spec section whose rule was violated.

If absent, a service engineer receiving a violation report must trace through all MUST rules across all 15 spec files to find the relevant one. With `section: "harp-audit"`, they can go directly to `10-audit.md` and find the rule. MUST reference a valid spec section ID.

### `violations[].evidence`

Provides the concrete evidence the runner observed.

If absent, the violation is a claim without proof. "MUST audit every write op" as a violation with no evidence is uncheckable. "trace_id=01HV7P... not found in /audit/trace endpoint" is a reproducible observation. The service engineer can replay the exact trace ID and verify. MUST contain enough information to reproduce the failure.

### `tier_attained`

The highest tier with zero failures.

If this field were omitted, the consumer of the conformance report would need to scan the `results` map and compute it themselves. `tier_attained` is the single actionable value from the report — it answers "what tier can this service claim?" The computation rule is strict: any failure in L1 means `tier_attained: none`; failures in L2 mean `tier_attained: L1`; failures in L3 mean `tier_attained: L2`.

## Examples

**Good: conformance run output for a correctly implemented L2 service.**

```json
{
  "service": "my-service",
  "declared_tier": "L2",
  "results": {
    "L1": { "passed": 47, "failed": 0, "skipped": 0 },
    "L2": { "passed": 22, "failed": 0, "skipped": 0 },
    "L3": { "passed": 0, "failed": 0, "skipped": 14 }
  },
  "violations": [],
  "tier_attained": "L2"
}
```

`tier_attained` matches `declared_tier`. Service can publish `effective_tier: L2` in the discovery doc.

**Bad: service declares L2, has one L2 violation (audit trail missing), `tier_attained` drops to L1.**

```json
{
  "service": "my-service",
  "declared_tier": "L2",
  "results": {
    "L1": { "passed": 47, "failed": 0, "skipped": 0 },
    "L2": { "passed": 21, "failed": 1, "skipped": 0 },
    "L3": { "passed": 0, "failed": 0, "skipped": 14 }
  },
  "violations": [
    {
      "section": "harp-audit",
      "rule": "MUST persist audit row for every write/destructive op",
      "evidence": "POST /drift/profiles with trace_id=01HV7P... produced no audit row at GET /audit/trace/01HV7P..."
    }
  ],
  "tier_attained": "L1"
}
```

Service team knows exactly what to fix: audit persistence is not wired up for `POST /drift/profiles`. The fix is in one place (audit middleware), not spread across the codebase.

**Good: `harp test` command invocation.**

```bash
harp test --url https://staging.my-service.com \
  --auth "Bearer $TOKEN" \
  --format json \
  > conformance-report.json
```

Output is the structured JSON above. CI pipeline asserts `tier_attained == declared_tier` or fails the build.

## Cross-references

- [Self-Test Vectors](./09-self-test-vectors.md) — the conformance runner's vector replay logic is defined there; coverage minimums are enforced by the runner
- [Tiers](./12-tiers.md) — normative tier requirements that the conformance categories test
- [Discovery](./02-discovery.md) — conformance runner reads `/.well-known/harness` as its first step; `effective_tier` MAY be published there
- [Tooling](./14-tooling.md) — `harp test` command wraps the conformance runner; same `harp-conformance` crate used by both

## Limitations and v0.1 caveats

The conformance suite is defined normatively in v0.1 but the reference implementation is not yet complete. Services can write their own conformance runners against this specification; the reference implementation in `harness-protocol/conformance/` will be the canonical tool when shipped. Destructive operation tests (dry-run, two-phase commit, delete) require a test resource to operate on; the runner creates and tears down a test resource per test run, which requires write credentials. Services that cannot provide write credentials to the conformance runner will have incomplete L2/L3 coverage. The runner does not test concurrent scenarios (multiple simultaneous writes with the same etag) due to the complexity of coordination in a black-box test; race condition conformance is expected to be covered by service-level unit tests.
