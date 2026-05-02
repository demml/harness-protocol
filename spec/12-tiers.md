---
id: harp-tiers
status: draft
normative: true
tier: null
version: 0.1
depends_on: []
---

# HARP — Tier Map (Normative)

## Why this exists

A protocol that requires full implementation before any compliance claim is possible creates an all-or-nothing adoption gate. Most services already exist — they have clients, API contracts, and operational history. Requiring them to implement dry-run, two-phase commit, recipe catalogs, and capability negotiation before they can claim any HARP compliance means the protocol never gets adopted. Teams assess the cost, compare it to their current ad-hoc approach, and defer indefinitely.

The tier system converts a one-time cliff into a staircase. Each step is independently valuable and independently verifiable. A service that reaches L1 already produces better errors, better retry signals, and better discoverability than 90% of existing APIs. A service at L2 can be navigated by an agent without human documentation. L3 adds the write safety and job management contracts that enable unattended autonomous operation.

For agents, tiers serve a different purpose: they are a capability declaration that the agent can read before making a call. An agent integrating a service at L1 knows not to attempt dry-run, not to look for `_actions[]`, and not to expect a recipe catalog. Without tier declaration, the agent probes capabilities speculatively and handles surprising failures. With tier declaration, the agent gates its behavior precisely.

## Mental model

The tier model is analogous to progressive enhancement in web development: L1 is the baseline that works everywhere, L2 adds richer interactivity, L3 adds full autonomy support. Each layer is backward-compatible with the layer below, and each layer degrades gracefully to the layer below when client capability is limited.

The key architectural constraint: tiers are cumulative, not modular. A service at L2 MUST implement all L1 requirements. There is no "L2-minus-etag" or "L1-plus-discovery" hybrid. This ensures that the tier label is a reliable predicate for agents: `max_tier: L2` means exactly the L2 capability set, no exceptions.

## Specification

### 4. Tier Map — Normative Restatement

Each tier compounds on the prior. A service declares its maximum tier in `/.well-known/harness`. Agents detect tier and downgrade gracefully.

#### L1 — Baseline

Cheap retrofit on any existing OpenAPI service. A service at L1 MUST implement:

| Capability | Letter | Normative Section |
|---|---|---|
| Error envelope | b | [Envelope](./01-envelope.md) §6.1 |
| Failure catalog per endpoint | n | [OpenAPI Extensions](./03-openapi-extensions.md) §7 |
| Worked examples in schema | o | [OpenAPI Extensions](./03-openapi-extensions.md) §7 |
| Op semantics tags (`read \| write \| destructive \| idempotent \| long_running`) | k | [OpenAPI Extensions](./03-openapi-extensions.md) §7 |
| `trace_id` on every response | s | [Envelope](./01-envelope.md) §6, [Audit](./10-audit.md) §11 |
| Auth scopes in OpenAPI | h | [Auth Scopes](./11-auth-scopes.md) §13 |
| Versioning headers | i | [OpenAPI Extensions](./03-openapi-extensions.md) §7 |

An L1-compliant service MUST meet all L1 requirements. There is no partial credit within a tier.

#### L2 — Agent-Ready

Response self-describes; agent navigates without prose. A service at L2 MUST implement all L1 requirements, plus:

| Capability | Letter | Normative Section |
|---|---|---|
| `/.well-known/harness` discovery doc | a | [Discovery](./02-discovery.md) §5 |
| Response metadata wrapper `{data, _meta}` | c | [Envelope](./01-envelope.md) §6.2 |
| Action affordances `_actions[]` | d | [Envelope](./01-envelope.md) §6.2 |
| Idempotency keys | e | [Write Correctness](./05-write-correctness.md) §9.1 |
| Cost + latency budget headers and `_meta.cost` | p | [Envelope](./01-envelope.md) §6.2, [OpenAPI Extensions](./03-openapi-extensions.md) §7 |
| Stability tier per op | q | [OpenAPI Extensions](./03-openapi-extensions.md) §7 |
| Optimistic concurrency (etag) | r | [Write Correctness](./05-write-correctness.md) §9.2 |
| Schema evolution signals (`Deprecation`, `Sunset`, `Link rel=successor`) | u | [OpenAPI Extensions](./03-openapi-extensions.md) §7 |
| Audit trail | j | [Audit](./10-audit.md) §11 |

#### L3 — Autonomous-Ready

Agent runs unattended. A service at L3 MUST implement all L1 and L2 requirements, plus:

| Capability | Letter | Normative Section |
|---|---|---|
| Dry-run | l | [Write Safety](./04-write-safety.md) §8.1 |
| Two-phase destructive commit | m | [Write Safety](./04-write-safety.md) §8.2 |
| Capability negotiation | f | [Capability Negotiation](./08-capability-negotiation.md) §10 |
| Long-running job pattern | g | [Long-Running Jobs](./06-long-running.md) §12 |
| Recipes catalog | t | [Recipes](./07-recipes.md) §14 |
| Self-test vectors | v | [Self-Test Vectors](./09-self-test-vectors.md) §15 |

#### Compliance Declaration

A service declares its tier in the discovery doc (see [Discovery](./02-discovery.md)):

```yaml
service:
  max_tier: L2
```

The `effective_tier` (output of conformance test run) MAY also be published in the discovery doc. `effective_tier` is the highest tier with zero conformance violations; `max_tier` is the service's self-declaration. They SHOULD match; divergence is a conformance failure.

## Per-field rationale (tiers)

### L1 capability set

The L1 requirements are the cheapest possible retrofit: they add metadata to existing responses (error envelopes, trace IDs) and add annotations to the existing OpenAPI spec (x-harness blocks, examples_ref). They do not require new endpoints, new state, or new infrastructure. A service that already returns structured errors and has an OpenAPI spec can reach L1 in a day with `harp init` and `harp lint`.

The choice of error envelope and semantics tags as the L1 floor is deliberate: errors and operation semantics are the minimum information needed for an agent to avoid catastrophic mistakes (retrying a non-retryable error, treating a destructive op as safe). Everything else (discovery, affordances, write safety) requires a higher floor.

### L2 capability set

L2 is the "agent doesn't need docs" milestone. The discovery doc (`/.well-known/harness`), action affordances (`_actions[]`), and response metadata wrapper (`{data, _meta}`) together make a response self-describing. An agent that receives an L2 response knows what the resource is, what it can do with it, what it costs, and how to navigate to related resources — from the response alone, without prior knowledge of the API.

Idempotency keys and optimistic concurrency land at L2 because they require durable server-side storage (Redis or Postgres for the idempotency cache, etag generation and storage). They are more expensive to implement than L1 — the tier placement reflects the implementation cost.

### L3 capability set

L3 is the "trust the agent to run unattended" milestone. Dry-run and two-phase commit address the safety requirements for autonomous destructive operations. Capability negotiation addresses the efficiency requirements for constrained agent environments. Long-running jobs and recipes address the workflow requirements for operations that cannot complete in a single HTTP call.

L3 is more expensive to implement because these capabilities require new infrastructure (job queues, HMAC signing, recipe catalog management, vector authorship) and new operational commitments (webhook retry, consumed-token cache, job result retention). The tier placement is honest about this cost.

## Examples

**Good: service correctly declares L2 with all L2 capabilities implemented.**

```yaml
service:
  max_tier: L2
  effective_tier: L2
```

Conformance test output: `{"L1": {"passed": 47, "failed": 0}, "L2": {"passed": 22, "failed": 0}, "L3": {"passed": 0, "skipped": 14}}`. `tier_attained: L2`. Declaration matches.

**Bad: service declares L3 but does not implement two-phase commit.**

```yaml
service:
  max_tier: L3
```

An agent sends `?phase=preview` on a DELETE. Gets 404 (endpoint doesn't exist). Agent has no recourse — it believed the service was L3 and routed destructive operations through the two-phase flow. The actual tier is L2 or L1.

Conformance output: `{"L3": {"failed": 1, "violations": [{"rule": "MUST implement two-phase destructive commit for ops with x-harness.two_phase: true"}]}}`. `tier_attained: L2`.

**Fix:** Either implement two-phase commit, or correct `max_tier` to `L2`. The discovery doc `effective_tier` field exists precisely for this: services can declare `max_tier: L3` (aspirational) and `effective_tier: L2` (current conformance result).

## Cross-references

- [Overview](./00-overview.md) — tier system rationale and adoption model
- [Envelope](./01-envelope.md) — `_meta.tier` declares which tier a specific response conforms to
- [Discovery](./02-discovery.md) — `service.max_tier` and `service.effective_tier` in the discovery doc
- [Conformance](./13-conformance.md) — `tier_attained` is the conformance runner's output; this file is the normative reference for what each tier requires
- [Tooling](./14-tooling.md) — `harp migrate --from L1 --to L2` uses this tier map to compute what is missing

## Limitations and v0.1 caveats

The tier model is binary within each tier: a service either meets all requirements or it does not. There is no partial credit, no "mostly L2" designation. This simplicity is intentional but means a service that implements 8 of 9 L2 requirements is declared L1 by the conformance runner. Teams should use `harp lint` to track their progress toward a tier before claiming it in the discovery doc. A future version may define a progress score (e.g., "L2 at 89%") for in-progress adoption tracking; v0.1 does not.
