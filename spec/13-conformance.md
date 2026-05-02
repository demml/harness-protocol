---
id: harp-conformance
status: draft
normative: true
tier: null
version: 0.1
depends_on: [harp-self-test-vectors]
---

# HARP — Conformance Test Suite

## 18. Conformance Test Suite

Lives in `harness-protocol/conformance/`. Generic harness in any language; reference impl in Rust + Python.

### 18.1 Inputs

- Service base URL.
- Auth credentials (service's choice of mode).
- Declared tier from `/.well-known/harness`.

### 18.2 Test Categories

| Category | Tier | Scope |
|---|---|---|
| Discovery doc shape | L1+ | Validate against `discovery.json` schema |
| Error envelope on synthetic errors | L1+ | Trigger every `possible_errors` entry per op via vector replay |
| Success envelope on synthetic happy path | L1+ | Validate `_meta` presence, `trace_id` consistency |
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
| Recipe DAG executability | L3 | Each recipe DAG resolvable via OpenAPI ops; `body_template` interpolation parseable |

### 18.3 Output

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

### 18.4 Self-Test Vector Conformance

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
