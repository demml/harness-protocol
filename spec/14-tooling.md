---
id: harp-tooling
status: draft
normative: false
tier: null
version: 0.1
depends_on: [harp-envelope]
---

# HARP — Tooling — Friction Reduction

## 21. Tooling — Friction Reduction

Spec without tooling = paper. v1.0 ships the toolchain below to push adoption cost from "engineer-weeks per service" down to "days for L1, ~week for L2, ~3 weeks for L3."

### 21.1 Tier 1 (must ship with v1.0)

#### `harp` Rust Binary CLI

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

#### Reference Middleware Libraries

Drop-in, framework-native. Goal: 5 lines to bolt L1 onto an existing service; ~20 lines for L2.

- **Rust — `harp-axum`** (in `crates/harp-axum`). Tower middleware. Wraps responses in envelope, emits `trace_id`, mounts `/.well-known/harness/*`, auto-generates the discovery doc from the axum route registry. Ships dry-run / two-phase / idempotent / audited extractors and decorators. Idempotency cache pluggable (in-memory default; Redis adapter feature-gated).
- **Python — `harp.fastapi`** (in `py-harp/python/harp/fastapi`). ASGI middleware + dependency injectors + decorators (`@dry_run`, `@two_phase`, `@idempotent`, `@audited`). Pure-Python wrapper over PyO3 bindings to `harp-core` for envelope validation, discovery doc generation, vector replay assertions. Idempotency cache pluggable (in-memory default; Redis adapter optional).

#### Reference Servers

- `ref-impl/rust-axum` — < 500 LOC service using `harp-axum` exercising every L1+L2+L3 feature.
- `ref-impl/python-fastapi` — < 500 LOC service using `harp.fastapi` exercising the same surface.

Both serve as conformance test targets and copy-paste starting points for adopters.

#### Skills

`~/.claude/skills/harness-api-design`, `harness-api-review`, `harness-conformance-test`, `harness-api-migrate`. Each enforces process; canonical content lives in the spec repo.

| Skill | When invoked | What it does |
|---|---|---|
| `harness-api-design` | New API design or significant feature add | Walks Claude through tier checklist, error envelope, OpenAPI extensions. Flags gaps. Proposes target tier. |
| `harness-api-review` | PR review on any API surface | Audits diff against tier requirements. Reports compliance gap with specific MUST/SHOULD violations. |
| `harness-conformance-test` | Standing up test infra for a HARP-claiming service | Generates conformance test scaffold per declared tier. |
| `harness-api-migrate` | Existing OpenAPI service wants to adopt HARP | Progressive lift L1 → L2 → L3. Each phase a separate PR. |

### 21.2 Tier 2 (post-v1.0 roadmap)

Listed for completeness; not in scope for v1.0.

- `harp` GitHub Action — drop-in workflow that runs lint on PR, runs conformance against ephemeral PR-preview deploy, comments compliance delta.
- OpenAPI client generator extensions — fork or contribute to `oapi-codegen` (Rust), `openapi-python-client`, `openapi-generator`. Generated clients honor `x-harness` natively (retry policy from `retry`, idempotency key auto-injection, etag handling, two-phase wrappers).
- VS Code / Cursor extension — autocomplete `x-harness` blocks, validate inline, surface tier warnings on save, run `harp lint` on save. Backed by an LSP shim wrapping `harp-lint`.
- Hosted conformance dashboard — submit URL, get tier verdict + violations, public README badge, catalog of compliant services.

### 21.3 Adoption Math

Without tooling, ballpark cost per service: ~2 engineer-weeks for L1, ~6 for L2, ~12 for L3.

With Tier 1 tooling: ~2 days for L1, ~1 week for L2, ~3 weeks for L3.

~10x reduction. That is the difference between adoption and shelf-ware.
