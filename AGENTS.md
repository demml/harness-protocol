# AGENTS.md

Guidance for AI agents (Claude Code, Codex, Gemini CLI, etc.) working in this repository.

## What This Is

**HARP (Harness Agent-Ready Protocol)** — a vendor-neutral protocol layered on HTTP/OpenAPI that makes services equally usable by humans and AI coding agents.

Three compliance tiers:
- **L1 Baseline** — minimal discovery doc, canonical error envelope, namespaced error codes, trace IDs, OpenAPI `x-harness` operation semantics
- **L2 Agent-ready** — success envelope, `_actions[]`, idempotency, ETags, cost metadata, audit trail
- **L3 Autonomous-ready** — dry-run, two-phase destructive commits, recipes, capability negotiation, long-running job handles, self-test vectors

The finished repo will ship: the spec (markdown + JSON Schema), a Rust CLI tool (`harp`), reference Rust + Python middleware, two reference servers, and reusable Claude skills.

Current tree status: the workspace scaffold, rough-draft markdown spec, initial agent harness journey docs, and local dogfooding docs are present. Most implementation crates, schemas, examples, conformance fixtures, generated docs site, Python package, reference servers, and skills are still planned work.

## Planning Docs

Working docs live in `dev/plan/`:

| File | Contents |
|---|---|
| `dev/plan/protocol-design.md` | Full wire format spec, all decisions |
| `dev/plan/implementation.md` | 29-PR roadmap, early dogfood slice, and file-level task breakdown |

Read these before making protocol or architecture decisions. They are the source of truth for intent and rationale.

If `spec/` and `dev/plan/protocol-design.md` disagree, treat `spec/` as the current normative draft and update the planning docs to match. `dev/plan/protocol-design.md` captures rationale and wire-shape intent; `dev/plan/implementation.md` captures the PR roadmap.

## Current State

This repository is still pre-implementation.

- Workspace scaffold exists: `Cargo.toml`, `Makefile`, `README.md`, `CONTRIBUTING.md`, `LICENSE`, `.gitignore`, `rust-toolchain.toml`, `.github/workflows/rust.yml`.
- `crates/harp-core/` is a placeholder so `members = ["crates/*"]` has at least one real Cargo package. Real protocol types land in PR 3.
- `spec/` contains the rough-draft markdown source of truth: 15 section files plus generated `spec/index.json`.
- `dev/plan/protocol-design.md` and `dev/plan/implementation.md` are present and should be kept aligned with spec edits.
- `docs/agent-harness-user-journey.md` documents the draft client-side and agent-side HARP flow.
- `docs/local-dogfooding.md` documents the planned early CLI, Claude Code, and Codex feedback loop.
- `schemas/`, `examples/`, `conformance/`, generated Astro docs, `py-harp/`, `ref-impl/`, and `tools/skills/` are planned but not present yet.

## Current Protocol Decisions

These decisions are easy to regress. Keep them consistent across `spec/`, `dev/plan/protocol-design.md`, and future schemas/types.

- **Discovery is L1.** L1 services MUST serve a minimal `/.well-known/harness` document. L2+ adds richer capability, budget, audit, scopes, examples, and effective-tier fields.
- **Success envelopes are L2+.** L1 standardizes error envelopes and traceability. L1 services MAY wrap successful responses, but L2 is where every 2xx response becomes `{data, _meta}`.
- **Operation semantics are only `read | write | destructive`.** Do not put `idempotent` or `long_running` in the semantics enum. Those are separate booleans in `x-harness`.
- **Recipes use `operation_id`.** Recipe steps do not carry method/path strings. Agents resolve `operation_id` through `links.openapi` by indexing OpenAPI `operationId` values to method, path template, parameters, request body schema, and server URL.
- **Two-phase actions must be explicit.** Destructive `_actions[]` with `requires_two_phase: true` MUST include `preview_href` and `commit_href`; agents follow those hrefs and do not derive phase routes.
- **Compact responses must be honest.** L3 compact negotiation MAY omit `_actions`, `_meta.cost`, and optional metadata, but omitted fields MUST be listed in `_meta.adaptations.omitted_fields`.
- **Wire protocol version is `harness_version: "0.1"`.** Use MAJOR.MINOR only; no PATCH in wire payloads.
- **Local dogfooding lands early.** The first manual feedback loop is a tiny static HARP service plus a read-only `harp harness` path. Do not wait for full conformance or reference middleware before making HARP locally testable.
- **Agents consume services through `harp harness`.** Agent skills teach Claude Code or other agents what to do, but the local harness CLI owns registry, discovery, OpenAPI operation resolution, auth references, and safety policy.
- **Do not add MCP/A2A adapters.** HARP's premise is that HTTP/OpenAPI plus HARP metadata is the service contract; `harp harness` is the local client policy layer.

## PR Workflow

- Branch off `main` per PR, name `pr-N-short-description`
- Use **graphite** (`gt`) for stacked PR management — `gt` is installed at 1.8.5, trunk = `main`
  - `gt create <branch-name>` to create a branch
  - `gt submit --no-edit --publish` to push + open ready-for-review PR
  - Fallback if gt auth fails: `git push -u origin <branch>` + `gh pr create --base main`
- PRs opened as **ready-for-review** (not draft)
- Commit style: Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`, `ci:`)
- Git identity: `Thorrester / sjforrester32@gmail.com`. **Never run `git config`.** **Never add `Co-Authored-By`.** **Never set `GIT_AUTHOR_*` env vars.**

## Verification After Any Code Change

```bash
# Rust — workspace-wide
make lints                  # cargo clippy --workspace --all-targets --all-features -- -D warnings
make test.unit              # cargo test --workspace --all-features

# Python (once py-harp lands in PR 19)
cd py-harp && make lints
cd py-harp && make test.unit
```

Always use `--all-features` for cargo commands.

## Repository Layout

This is the intended layout. Some paths are planned and do not exist yet; check the working tree before editing.

```
harness-protocol/
├── Cargo.toml              ← workspace root
├── Makefile                ← format/lints/test/build targets
├── crates/
│   ├── harp-core/          ← present now as a stub; real protocol types in PR 3
│   ├── harp/               ← planned CLI binary (PR 8+)
│   ├── harp-openapi/       ← planned OpenAPI x-harness reader/writer (PR 4)
│   ├── harp-lint/          ← planned tier-rule engine (PRs 5–7)
│   ├── harp-conformance/   ← planned live URL test runner (PR 13)
│   ├── harp-migrate/       ← planned diff engine (PR 11)
│   ├── harp-codegen/       ← planned scaffold generators (PR 10)
│   ├── harp-axum/          ← planned Rust reference middleware (PRs 15–16)
│   └── harp-fixtures/      ← planned shared test fixtures (PR 3)
├── spec/                   ← present markdown spec source-of-truth
├── dev/plan/               ← present design + implementation roadmap
├── schemas/                ← planned JSON Schema 2020-12 (PR 2)
├── examples/               ← planned tested reference fixtures (PR 2)
├── conformance/            ← planned tier-graded test vectors (PR 13)
├── docs/                   ← present draft user/dogfood docs now; generated Astro site planned in PR 12
├── py-harp/                ← planned Python package (PyO3, PR 19+)
├── ref-impl/               ← planned tiny dogfood service plus Rust + Python reference servers
└── tools/skills/           ← planned Claude skill source (PRs 23–26)
```

## Key Conventions

- **Rust edition:** 2024, rust-version 1.85
- **Clippy:** `-D warnings` — all warnings are errors
- **No comments** on code you didn't touch. Comments only for non-obvious WHY, never WHAT.
- **No overbuilding.** YAGNI. No speculative abstractions.
- **Error handling:** `thiserror` for types, propagate with `?`
- **Async:** Tokio multi-threaded throughout
- **Python:** uv + maturin + PyO3 0.28, abi3-py310, features `[anyhow, chrono, serde, extension-module]`
- **Tests:** top-level `def test_*` only — never `class TestFoo:`
- **Cargo commands:** always `--all-features`
- **Schemas:** hand-written JSON Schema 2020-12. No derivation from Rust types in v0.1.
- **Protocol version in wire format:** `harness_version: "0.1"` — MAJOR.MINOR only, no PATCH

## Spec Writing Rules

When editing anything in `spec/`:
- Every attribute MUST earn its place: state what breaks without it
- Every section needs: Why this exists → Mental model → Specification (MUST/SHOULD/MAY) → Per-field rationale → Examples (good + bad) → Cross-references → Limitations/v0.1 caveats
- Keep `dev/plan/protocol-design.md` and `dev/plan/implementation.md` aligned when a spec decision changes
- RFC 2119 keywords (MUST, SHOULD, MAY, MUST NOT) MUST stay capitalized
- After editing spec files run `./scripts/regen-spec-index.sh` and verify `spec/index.json` is valid JSON with 15 sections
- No references to external paths outside this repo

## Commands

```bash
# Rust
cargo fmt --all
make lints
make test.unit
make build

# Graphite
gt create <branch-name>
gt submit --no-edit --publish
gt log
gt restack

# Spec
./scripts/regen-spec-index.sh
python3 -c "import json; data=json.load(open('spec/index.json')); assert len(data['sections'])==15; print('OK')"

# Schema validation (PR 2+)
./scripts/validate-examples.sh
```
