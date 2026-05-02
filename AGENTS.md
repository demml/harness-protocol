# AGENTS.md

Guidance for AI agents (Claude Code, Codex, Gemini CLI, etc.) working in this repository.

## What This Is

**HARP (Harness Agent-Ready Protocol)** — a vendor-neutral protocol layered on HTTP/OpenAPI that makes services equally usable by humans and AI coding agents.

Three compliance tiers:
- **L1 Baseline** — canonical error/success envelopes, namespaced error codes
- **L2 Agent-ready** — discovery doc, idempotency, ETags, hypermedia actions, cost metadata
- **L3 Autonomous-ready** — dry-run, two-phase destructive commits, recipes, capability negotiation, long-running job handles

The repo ships: the spec (markdown, JSON Schema), a Rust CLI tool (`harp`), reference Rust + Python middleware, two reference servers, and four reusable Claude skills.

## Planning Docs

Working docs live in `dev/plan/`:

| File | Contents |
|---|---|
| `dev/plan/protocol-design.md` | Full wire format spec, all decisions |
| `dev/plan/implementation.md` | 29-PR roadmap with file-level task breakdown |

Read these before making protocol or architecture decisions. They are the source of truth for intent and rationale.

## Current State (as of session hand-off)

### Merged to `main`
- **PR 0** (`8fe4e9c`) — workspace scaffold: `Cargo.toml`, `Makefile`, `README.md`, `CONTRIBUTING.md`, `LICENSE`, `.gitignore`, `rust-toolchain.toml`, `.github/workflows/rust.yml`
  - Deviation: stub `crates/harp-core/` added because `members = ["crates/*"]` with no real packages is a Cargo hard error, not a warning. Will be replaced by real implementation in PR 3.
  - Deviation: `[workspace.dev-dependencies]` is not a valid Cargo key — dev deps folded into `[workspace.dependencies]`. Correct Cargo pattern.

### Open PRs

| PR | Branch | Needs |
|---|---|---|
| [#1](https://github.com/demml/harness-protocol/pull/1) | `pr-1-spec-md` | **Enrichment pass** — 15 spec md files + index.json are structurally correct but thin. Each file has MUST/SHOULD rules + JSON examples but no rationale. Missing: "Why this exists", per-field justification, concrete failure modes prevented, examples of wrong usage and how to fix. Every attribute must earn its place. |
| [#2](https://github.com/demml/harness-protocol/pull/2) | `chore/vendor-planning-docs` | Ready to merge — adds `dev/plan/` docs |

### PRs 3–28
Not started. Full details in `dev/plan/implementation.md`.

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

```
harness-protocol/
├── Cargo.toml              ← workspace root
├── Makefile                ← format/lints/test/build targets
├── crates/
│   ├── harp/               ← CLI binary (PR 8+)
│   ├── harp-core/          ← protocol types (stub now; real impl PR 3)
│   ├── harp-openapi/       ← OpenAPI x-harness reader/writer (PR 4)
│   ├── harp-lint/          ← tier-rule engine (PRs 5–7)
│   ├── harp-conformance/   ← live URL test runner (PR 13)
│   ├── harp-migrate/       ← diff engine (PR 11)
│   ├── harp-codegen/       ← scaffold generators (PR 10)
│   ├── harp-axum/          ← Rust reference middleware (PRs 15–16)
│   └── harp-fixtures/      ← shared test fixtures (PR 3)
├── py-harp/                ← Python package (PyO3, PR 19+)
├── ref-impl/
│   ├── rust-axum/          ← Rust reference server (PR 17)
│   └── python-fastapi/     ← Python reference server (PR 22)
├── spec/                   ← markdown spec source-of-truth (PR 1)
├── schemas/                ← JSON Schema 2020-12 (PR 2)
├── examples/               ← tested reference fixtures (PR 2)
├── conformance/            ← tier-graded test vectors (PR 13)
├── docs/                   ← Astro Starlight site (PR 12)
├── tools/skills/           ← Claude skill source (PRs 23–26)
└── dev/plan/               ← working docs (not part of protocol surface)
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
