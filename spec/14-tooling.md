---
id: harp-tooling
status: draft
normative: false
tier: null
version: 0.1
depends_on: [harp-envelope]
---

# HARP — Tooling — Friction Reduction

## Why this exists

A protocol specification without tooling describes the destination but provides no vehicle. Teams that adopt HARP manually must read 15 spec sections, annotate every OpenAPI operation, write error envelopes, build a discovery doc, author self-test vectors, and wire up audit middleware — all before shipping their first compliant endpoint. That is weeks of work, and most of it is mechanical repetition of rules already in the spec.

Without `harp init`, the first step — annotating an existing OpenAPI spec with `x-harness` blocks — requires reading the spec, understanding the field semantics, and applying them one operation at a time. With `harp init`, the same result is a 30-second command that scaffolds all fields with safe defaults and flags only the fields that require human judgment (cost budgets, related recipes).

Without `harp lint`, non-conformance is discovered at runtime by agents that encounter unexpected behavior. With `harp lint` in CI, non-conformance is caught at commit time with a precise, actionable error message pointing to the specific rule and field that failed.

Without `harp test`, a service team's tier claim is unverified self-reporting. With `harp test`, the claim is backed by a reproducible machine test that any external party can run.

The tooling is not optional scaffolding around the protocol — it is the mechanism that makes the adoption cost low enough to justify adopting at all.

## Mental model

The tooling architecture follows the same separation used by Rust's compiler toolchain: a core library (`harp-lint`, `harp-codegen`, `harp-conformance`) that contains all validation and generation logic, wrapped by a thin CLI (`harp`) that delegates to these libraries. This means the same lint engine that powers `harp lint` can be embedded in an IDE extension, a GitHub Action, or an LSP server — without dragging the CLI dependency or duplicating logic.

The reference middleware libraries (`harp-axum`, `harp.fastapi`) follow the same philosophy: they wrap the core protocol behavior (envelope generation, discovery doc serving, dry-run handling) in idiomatic framework middleware. The middleware is not a framework lock-in — it is a reference implementation that demonstrates how to wire HARP contracts into a real service, copy-pasteable as a starting point.

## Specification

### 21. Tooling — Friction Reduction

Spec without tooling = paper. v1.0 ships the toolchain below to push adoption cost from "engineer-weeks per service" down to "days for L1, ~week for L2, ~3 weeks for L3."

#### 21.1 Tier 1 (must ship with v1.0)

##### `harp` Rust Binary CLI

Two-layer architecture: thin clap shell (`crates/harp/src/cli/*`) delegates to per-command orchestrator (`crates/harp/src/actions/*`), which calls into pure-logic core crates. Core crates are reusable from a future LSP server, GH Action binary, or IDE extension without dragging clap.

| Subcommand | Purpose | Backed by crate |
|---|---|---|
| `harp init` | Bootstrap. Takes existing OpenAPI doc → scaffolds `x-harness` blocks with safe defaults, creates `harness.yaml`, emits human-review TODOs for fields that cannot be inferred (cost budgets, scopes, related_recipes). | `harp-codegen` |
| `harp scaffold` | Generate ancillary files (JSON Schemas, error catalog, discovery doc template, vector skeletons) from existing `x-harness` annotations. Run after `init` or after editing extensions. | `harp-codegen` |
| `harp lint` | Static tier compliance check. No network. Reads OpenAPI doc, `harness.yaml`, schemas, vectors, recipes. Validates: every op has `semantics` (L1); `possible_errors` codes are namespaced and resolve to catalog (L1); `examples_ref` resolves to a valid vector file (L1); discovery doc shape valid against `discovery.json` schema (L2); response schemas declare `_meta` (L2); `_actions[]` rels reference real op IDs (L2); idempotency / etag flags consistent (L2); recipe DAGs reference real ops, `body_template` parseable (L3); vector coverage matches tier minimum (one success vector per op at L1; one failure vector per `possible_errors` entry at L2; one dry-run vector and one two-phase preview+commit pair at L3, when applicable); all cross-refs (discovery → openapi → x-harness → schemas) resolve. Exits non-zero on violations. | `harp-lint` |
| `harp test --url <base>` | Live conformance. Runs `harp lint` first (static), then dynamic conformance suite (see [Conformance](./13-conformance.md)) against the deployed service. Replays vectors. Outputs structured `tier_attained` + violations JSON. | `harp-conformance` |
| `harp migrate --from L1 --to L2` | Diff current state against target tier. Emits patch suggestions. `--apply` writes them; default = dry-run. | `harp-migrate` |
| `harp docs build` | Render docs site from spec + OpenAPI + recipes + vectors. Astro Starlight template. Service ships docs for free. | `harp-codegen` + Starlight |
| `harp serve-refs --lang rust\|python` | Boot a reference server locally for poking and agent demos. | `harp-axum` (Rust) or shells out to `ref-impl/python-fastapi` |

Shared CLI flags across all subcommands: `--format json|human` (default human), `--config <path>`, `--quiet`, `--verbose`, `-v|-vv`. Exit codes: 0 ok, 1 violation, 2 error.

Lint engine is the same crate (`harp-lint`) consumed by `harp lint`, `harp test` (static prepass), the planned LSP, and a future GitHub Action binary. Single source of compliance truth.

##### Reference Middleware Libraries

Drop-in, framework-native. Goal: 5 lines to bolt L1 onto an existing service; ~20 lines for L2.

- **Rust — `harp-axum`** (in `crates/harp-axum`). Tower middleware. Wraps responses in envelope, emits `trace_id`, mounts `/.well-known/harness/*`, auto-generates the discovery doc from the axum route registry. Ships dry-run / two-phase / idempotent / audited extractors and decorators. Idempotency cache pluggable (in-memory default; Redis adapter feature-gated).
- **Python — `harp.fastapi`** (in `py-harp/python/harp/fastapi`). ASGI middleware + dependency injectors + decorators (`@dry_run`, `@two_phase`, `@idempotent`, `@audited`). Pure-Python wrapper over PyO3 bindings to `harp-core` for envelope validation, discovery doc generation, vector replay assertions. Idempotency cache pluggable (in-memory default; Redis adapter optional).

##### Reference Servers

- `ref-impl/rust-axum` — < 500 LOC service using `harp-axum` exercising every L1+L2+L3 feature.
- `ref-impl/python-fastapi` — < 500 LOC service using `harp.fastapi` exercising the same surface.

Both serve as conformance test targets and copy-paste starting points for adopters.

##### Skills

`~/.claude/skills/harness-api-design`, `harness-api-review`, `harness-conformance-test`, `harness-api-migrate`. Each enforces process; canonical content lives in the spec repo.

| Skill | When invoked | What it does |
|---|---|---|
| `harness-api-design` | New API design or significant feature add | Walks Claude through tier checklist, error envelope, OpenAPI extensions. Flags gaps. Proposes target tier. |
| `harness-api-review` | PR review on any API surface | Audits diff against tier requirements. Reports compliance gap with specific MUST/SHOULD violations. |
| `harness-conformance-test` | Standing up test infra for a HARP-claiming service | Generates conformance test scaffold per declared tier. |
| `harness-api-migrate` | Existing OpenAPI service wants to adopt HARP | Progressive lift L1 → L2 → L3. Each phase a separate PR. |

#### 21.2 Tier 2 (post-v1.0 roadmap)

Listed for completeness; not in scope for v1.0.

- `harp` GitHub Action — drop-in workflow that runs lint on PR, runs conformance against ephemeral PR-preview deploy, comments compliance delta.
- OpenAPI client generator extensions — fork or contribute to `oapi-codegen` (Rust), `openapi-python-client`, `openapi-generator`. Generated clients honor `x-harness` natively (retry policy from `retry`, idempotency key auto-injection, etag handling, two-phase wrappers).
- VS Code / Cursor extension — autocomplete `x-harness` blocks, validate inline, surface tier warnings on save, run `harp lint` on save. Backed by an LSP shim wrapping `harp-lint`.
- Hosted conformance dashboard — submit URL, get tier verdict + violations, public README badge, catalog of compliant services.

#### 21.3 Adoption Math

Without tooling, ballpark cost per service: ~2 engineer-weeks for L1, ~6 for L2, ~12 for L3.

With Tier 1 tooling: ~2 days for L1, ~1 week for L2, ~3 weeks for L3.

~10x reduction. That is the difference between adoption and shelf-ware.

## Per-field rationale (tools)

### `harp init`

Scaffolds `x-harness` blocks for every operation in an existing OpenAPI spec.

Without `harp init`, the first step of HARP adoption requires reading all `x-harness` field definitions and manually annotating every operation. For a service with 30 operations, that is 30 × (14 fields) = 420 manual field decisions, most of which have obvious safe defaults (`long_running: false`, `two_phase: false`). `harp init` automates all safe-default fields and emits TODO comments only where human judgment is required. The remaining manual work is typically 5–10 decisions per service, not 420.

### `harp scaffold`

Generates ancillary files (JSON Schemas, error catalog, vector skeletons) from `x-harness` annotations.

Without `harp scaffold`, a service team must manually create the `/.well-known/harness/errors` catalog, the envelope JSON Schema, and vector file stubs for each operation. These files are mechanical derivations of the `x-harness` annotations that already exist — `scaffold` makes the derivation automatic. Running it after `harp init` or after editing extensions regenerates all derived files, keeping them in sync with the source annotations.

### `harp lint`

Validates spec conformance statically, with no network call.

Without `harp lint`, non-conformance is discovered at runtime — either by the conformance test suite or by agents encountering unexpected behavior in production. `harp lint` catches the same violations in CI, before deployment, with precise error messages like "operation POST /drift/profiles: `possible_errors` is missing SCOUTER_DUPLICATE_PROFILE which is returned by the handler at line 42". Exits non-zero on violations, blocking merges that introduce non-conformance.

### `harp test`

Runs `harp lint` followed by the live conformance suite against a deployed service.

Without `harp test`, tier claims are unverified. `harp test` is the source of the `tier_attained` value that MAY be published in the discovery doc as `effective_tier`. The combination of static lint (catches schema issues) and live conformance (catches behavioral issues that linting can't see, like audit persistence not being wired up) provides full coverage.

### `harp migrate`

Diffs the current service state against a target tier and emits a prioritized patch list.

Without `harp migrate`, upgrading from L1 to L2 requires manual comparison of the current service state against the L2 requirement table. `harp migrate --from L1 --to L2` produces an ordered list of what is missing, with `--apply` to write safe patches automatically and human-review items flagged. This converts a week-long gap analysis into a day of targeted implementation.

### `harp docs build`

Renders a documentation site from the spec, OpenAPI spec, recipes, and vectors.

Without `harp docs build`, API documentation requires a separate documentation system (e.g., Stoplight, Redoc, custom Docusaurus). `harp docs build` uses the Astro Starlight template to generate a documentation site that includes error catalogs, recipe examples, and vector previews automatically from the HARP artifacts that already exist. The service gets documentation as a side effect of HARP compliance, not as a separate investment.

### Reference middleware (`harp-axum`, `harp.fastapi`)

Drop-in middleware that handles protocol mechanics, leaving the service to focus on business logic.

Without reference middleware, every service implementing HARP must solve the same mechanical problems: how to wrap responses in the envelope, how to mount `/.well-known/harness`, how to implement the dry-run no-op path, how to wire up idempotency key handling. These are solved problems — `harp-axum` and `harp.fastapi` solve them once, correctly, and let service teams bolt HARP onto their framework in 5–20 lines.

## Examples

**Good: L1 adoption path using tooling.**

```bash
# Step 1: scaffold x-harness annotations onto existing OpenAPI spec
harp init --openapi openapi.yaml --target-tier L1

# Step 2: generate derived files (error catalog, vector stubs)
harp scaffold --openapi openapi.yaml

# Step 3: verify no lint violations before committing
harp lint --openapi openapi.yaml --tier L1
# Output: "47 checks passed. 0 violations."

# Step 4 (after deploying): verify live conformance
harp test --url https://staging.my-service.com --auth "Bearer $TOKEN"
# Output: {"tier_attained": "L1", "violations": []}
```

Total time: ~2 hours for a service with 20 operations, most of which is filling in the TODO annotations that `harp init` flagged (cost budgets, scope declarations, related recipes).

**Bad: manual L1 adoption without tooling.**

Service engineer reads spec, opens OpenAPI file, manually adds `x-harness` to 20 operations. Misses `possible_errors` on 3 operations (didn't realize it was required). Omits `examples_ref` on 5 operations (didn't understand the vector requirement). Ships. First conformance test reveals 8 violations.

**Fix:** Run `harp init` to scaffold defaults. Run `harp lint` in CI to catch violations before shipping. The violations are found at commit time, not at agent integration time.

## Cross-references

- [OpenAPI Extensions](./03-openapi-extensions.md) — `harp init` and `harp lint` operate on `x-harness` blocks
- [Self-Test Vectors](./09-self-test-vectors.md) — `harp scaffold` generates vector stubs; `harp test` replays them
- [Conformance](./13-conformance.md) — `harp test` wraps the conformance runner defined there; `harp-lint` and `harp-conformance` are the backing crates
- [Discovery](./02-discovery.md) — `harp scaffold` generates the discovery doc; `harp lint` validates it
- [Tiers](./12-tiers.md) — `harp migrate --from L1 --to L2` uses the tier requirement table as its input

## Limitations and v0.1 caveats

The Tier 1 tooling is defined normatively in v0.1 but implementation completeness at the time of spec publication varies by component. `harp lint` and `harp init` are the highest-priority implementations; `harp migrate` and `harp docs build` are lower priority and may lag behind the spec. The reference middleware (`harp-axum`, `harp.fastapi`) are reference implementations — production use requires review of the idempotency cache and dry-run simulation logic for the specific service's requirements. The skills (`harness-api-design`, `harness-api-review`, etc.) are agent skills for Claude Code and are not portable to other agent frameworks without adaptation.
