---
id: harp-tiers
status: draft
normative: true
tier: null
version: 0.1
depends_on: []
---

# HARP — Tier Map (Normative)

## 4. Tier Map — Normative Restatement

Each tier compounds on the prior. A service declares its maximum tier in `/.well-known/harness`. Agents detect tier and downgrade gracefully.

### L1 — Baseline

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

### L2 — Agent-Ready

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

### L3 — Autonomous-Ready

Agent runs unattended. A service at L3 MUST implement all L1 and L2 requirements, plus:

| Capability | Letter | Normative Section |
|---|---|---|
| Dry-run | l | [Write Safety](./04-write-safety.md) §8.1 |
| Two-phase destructive commit | m | [Write Safety](./04-write-safety.md) §8.2 |
| Capability negotiation | f | [Capability Negotiation](./08-capability-negotiation.md) §10 |
| Long-running job pattern | g | [Long-Running Jobs](./06-long-running.md) §12 |
| Recipes catalog | t | [Recipes](./07-recipes.md) §14 |
| Self-test vectors | v | [Self-Test Vectors](./09-self-test-vectors.md) §15 |

### Compliance Declaration

A service declares its tier in the discovery doc (see [Discovery](./02-discovery.md)):

```yaml
service:
  max_tier: L2
```

The `effective_tier` (output of conformance test run) MAY also be published in the discovery doc. `effective_tier` is the highest tier with zero conformance violations; `max_tier` is the service's self-declaration. They SHOULD match; divergence is a conformance failure.
