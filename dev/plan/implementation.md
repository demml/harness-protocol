# HARP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the HARP (Harness Agent-Ready Protocol) v0.1.0 reference implementation: a standalone repo containing the protocol spec, JSON Schemas, a Cargo workspace with CLI tooling and reference middleware, a Python sub-package, two reference servers, and four reusable Claude skills.

**Architecture:** Cargo workspace mirroring opsml's `crates/<name>` convention. Thin clap CLI binary delegates to per-command orchestrators which call into pure-logic core crates. Python sub-package wraps Rust via PyO3 (mirrors py-scouter / py-opsml). Spec markdown source-of-truth with hand-written JSON Schema 2020-12 normative artifacts. Reference servers ground every protocol claim with executable code.

**Tech Stack:** Rust 2024 edition, clap v4 (derive), tokio, axum 0.7, tower 0.5, openapiv3 v2, jsonschema 0.18, reqwest 0.12, serde 1, hmac+sha2 for signatures, uuid v4. Python via uv + maturin + PyO3, FastAPI 0.115+. Astro Starlight for docs. JSON Schema 2020-12 throughout.

**Spec reference:** `dev/plan/protocol-design.md` (in this repo)

**Repo:** this repo — `demml/harness-protocol`. PR 0 (commit `8fe4e9c`) created the workspace skeleton.

---

## §20 Resolutions (locked entering plan)

The spec's §20 Open Questions are resolved as follows. These decisions are inputs to the plan, not deliverables.

| # | Question | Resolution |
|---|---|---|
| 1 | Decomposition order | Spec markdown + JSON Schemas + `harp-core` first (PRs 0-3), then static analysis (`harp-lint`, PRs 4-7), CLI (PRs 8-12), conformance runner (PRs 13-14), reference middleware (PRs 15-18), Python (PRs 19-22), skills (PRs 23-26), release polish (PRs 27-28) |
| 2 | Repo bootstrap content | PR 0 ships `Cargo.toml`, `Makefile`, `README.md`, `CONTRIBUTING.md`, MIT `LICENSE`, `.gitignore`, `.github/workflows/{rust,python,schemas,conformance}.yml`, `rust-toolchain.toml` |
| 3 | Schema authoring | Hand-written JSON Schema 2020-12 in `schemas/`. No derivation from Rust types in v0.1.0 (avoids tight coupling between schema layout and serde structure). Automation deferred to v0.2 |
| 4 | Reference impl strategy | Spec repo ships `ref-impl/rust-axum` and `ref-impl/python-fastapi` as the canonical conformance targets. They MUST attain tier L3 in CI on every PR |
| 5 | Skill packaging | Skills live in `~/.claude/skills/harness-*/` as standalone files. They reference canonical material via pinned commit hash in skill frontmatter. First-use fetch from GitHub raw URL with on-disk cache at `~/.claude/skills/harness-*/.cache/` |
| 6 | Versioning policy | **Protocol semver, MAJOR.MINOR only** (no PATCH on the wire). v0.1.0 of repo ships `harness_version: "0.1"` in discovery docs. Breaking wire-format changes bump MAJOR. New tier additions or new optional fields bump MINOR. Repo crates use full semver independently. Pre-1.0 protocol status is signaled in `service.stability` as `experimental`. |

---

## File Structure (locked layout — informs all PR tasks)

```
~/Documents/GitHub/harness-protocol/
├── Cargo.toml                      ← workspace root [PR 0]
├── Cargo.lock                      ← committed [PR 0]
├── Makefile                        ← lints/test/format targets [PR 0]
├── README.md                       ← project overview [PR 0]
├── CONTRIBUTING.md                 ← contributor guide [PR 0]
├── LICENSE                         ← MIT [PR 0]
├── .gitignore                      ← rust + python + tooling [PR 0]
├── rust-toolchain.toml             ← pin rust 1.85+ for edition 2024 [PR 0]
├── .github/workflows/
│   ├── rust.yml                    ← cargo fmt + clippy + test [PR 0]
│   ├── python.yml                  ← uv lint + pytest + maturin [PR 19]
│   ├── schemas.yml                 ← schema validation + index drift [PR 2]
│   └── conformance.yml             ← ref-impl conformance run [PR 17, 22]
│
├── crates/
│   ├── harp/                       ← binary crate; bin name "harp"
│   │   ├── Cargo.toml              [PR 8]
│   │   └── src/
│   │       ├── main.rs             [PR 8]
│   │       ├── lib.rs              [PR 8]
│   │       ├── error.rs            [PR 8]
│   │       ├── cli/
│   │       │   ├── mod.rs          [PR 8]
│   │       │   ├── init.rs         [PR 10]
│   │       │   ├── scaffold.rs     [PR 10]
│   │       │   ├── lint.rs         [PR 9]
│   │       │   ├── test.rs         [PR 14]
│   │       │   ├── migrate.rs      [PR 11]
│   │       │   ├── docs.rs         [PR 12]
│   │       │   └── serve_refs.rs   [PR 18]
│   │       └── actions/
│   │           ├── mod.rs          [PR 8]
│   │           ├── init.rs         [PR 10]
│   │           ├── scaffold.rs     [PR 10]
│   │           ├── lint.rs         [PR 9]
│   │           ├── conformance.rs  [PR 14]
│   │           ├── migrate.rs      [PR 11]
│   │           └── docs.rs         [PR 12]
│   │
│   ├── harp-core/                  ← protocol types
│   │   ├── Cargo.toml              [PR 3]
│   │   └── src/
│   │       ├── lib.rs              [PR 3]
│   │       ├── error.rs            [PR 3]
│   │       ├── codes.rs            ← HARP_* canonical codes [PR 3]
│   │       ├── envelope.rs         ← success + error envelopes [PR 3]
│   │       ├── discovery.rs        ← /.well-known/harness/* shapes [PR 3]
│   │       ├── extension.rs        ← x-harness deserialize/validate [PR 3]
│   │       ├── recipe.rs           [PR 3]
│   │       ├── vector.rs           [PR 3]
│   │       └── tier.rs             [PR 3]
│   │
│   ├── harp-openapi/               ← OpenAPI 3.1 + x-harness reader/writer
│   │   ├── Cargo.toml              [PR 4]
│   │   └── src/
│   │       ├── lib.rs              [PR 4]
│   │       ├── reader.rs           [PR 4]
│   │       ├── writer.rs           [PR 4]
│   │       └── error.rs            [PR 4]
│   │
│   ├── harp-lint/                  ← tier-rule engine; pure logic
│   │   ├── Cargo.toml              [PR 5]
│   │   └── src/
│   │       ├── lib.rs              [PR 5]
│   │       ├── error.rs            [PR 5]
│   │       ├── violation.rs        ← violation type [PR 5]
│   │       ├── rules/
│   │       │   ├── mod.rs          [PR 5]
│   │       │   ├── l1.rs           [PR 5]
│   │       │   ├── l2.rs           [PR 6]
│   │       │   └── l3.rs           [PR 7]
│   │       └── runner.rs           ← orchestrator [PR 5]
│   │
│   ├── harp-conformance/           ← live URL test runner
│   │   ├── Cargo.toml              [PR 13]
│   │   └── src/
│   │       ├── lib.rs              [PR 13]
│   │       ├── runner.rs           [PR 13]
│   │       ├── replay.rs           ← vector replay engine [PR 13]
│   │       ├── report.rs           ← tier_attained + violations JSON [PR 13]
│   │       └── error.rs            [PR 13]
│   │
│   ├── harp-migrate/               ← diff engine
│   │   ├── Cargo.toml              [PR 11]
│   │   └── src/
│   │       ├── lib.rs              [PR 11]
│   │       ├── differ.rs           [PR 11]
│   │       ├── patch.rs            [PR 11]
│   │       └── error.rs            [PR 11]
│   │
│   ├── harp-codegen/               ← scaffold generators
│   │   ├── Cargo.toml              [PR 10]
│   │   └── src/
│   │       ├── lib.rs              [PR 10]
│   │       ├── init.rs             ← scaffolds x-harness blocks [PR 10]
│   │       ├── scaffold.rs         ← schemas/catalog/discovery/vectors [PR 10]
│   │       ├── docs.rs             ← Astro Starlight emitter [PR 12]
│   │       └── error.rs            [PR 10]
│   │
│   ├── harp-axum/                  ← reference Rust middleware
│   │   ├── Cargo.toml              [PR 15]
│   │   └── src/
│   │       ├── lib.rs              [PR 15]
│   │       ├── middleware.rs       ← envelope wrap, trace_id [PR 15]
│   │       ├── discovery.rs        ← mounts /.well-known/harness/* [PR 15]
│   │       ├── extractors/
│   │       │   ├── mod.rs          [PR 16]
│   │       │   ├── dry_run.rs      [PR 16]
│   │       │   ├── two_phase.rs    [PR 16]
│   │       │   ├── idempotency.rs  [PR 16]
│   │       │   └── audit.rs        [PR 16]
│   │       └── error.rs            [PR 15]
│   │
│   └── harp-fixtures/              ← shared test fixtures
│       ├── Cargo.toml              [PR 3]
│       └── src/
│           ├── lib.rs              [PR 3]
│           ├── envelopes.rs        [PR 3]
│           ├── discovery.rs        [PR 3]
│           └── vectors.rs          [PR 3]
│
├── py-harp/                        ← Python package
│   ├── Cargo.toml                  ← cdylib, pyo3 bindings [PR 19]
│   ├── pyproject.toml              ← uv + maturin [PR 19]
│   ├── Makefile                    ← format/lints/test/setup [PR 19]
│   ├── src/
│   │   └── lib.rs                  ← PyO3 module registration [PR 19]
│   ├── python/harp/
│   │   ├── __init__.py             [PR 19]
│   │   ├── _harp.pyi               ← generated stub [PR 19]
│   │   ├── fastapi/
│   │   │   ├── __init__.py         [PR 20]
│   │   │   ├── middleware.py       [PR 20]
│   │   │   └── decorators.py       [PR 21]
│   │   └── cli/
│   │       └── __init__.py         [PR 19]
│   └── tests/                      [PR 19+]
│
├── ref-impl/
│   ├── rust-axum/                  ← Rust reference server
│   │   ├── Cargo.toml              [PR 17]
│   │   └── src/main.rs             [PR 17]
│   └── python-fastapi/             ← Python reference server
│       ├── pyproject.toml          [PR 22]
│       └── app.py                  [PR 22]
│
├── spec/                           ← markdown source-of-truth
│   ├── index.json                  ← machine-readable section index [PR 1]
│   ├── 00-overview.md              [PR 1]
│   ├── 01-envelope.md              [PR 1]
│   ├── 02-discovery.md             [PR 1]
│   ├── 03-openapi-extensions.md    [PR 1]
│   ├── 04-write-safety.md          [PR 1]
│   ├── 05-write-correctness.md     [PR 1]
│   ├── 06-long-running.md          [PR 1]
│   ├── 07-recipes.md               [PR 1]
│   ├── 08-capability-negotiation.md [PR 1]
│   ├── 09-self-test-vectors.md     [PR 1]
│   ├── 10-audit.md                 [PR 1]
│   ├── 11-auth-scopes.md           [PR 1]
│   ├── 12-tiers.md                 [PR 1]
│   ├── 13-conformance.md           [PR 1]
│   └── 14-tooling.md               [PR 1]
│
├── schemas/                        ← JSON Schema 2020-12
│   ├── envelope-error.json         [PR 2]
│   ├── envelope-success.json       [PR 2]
│   ├── discovery.json              [PR 2]
│   ├── openapi-extension.json      [PR 2]
│   ├── recipe.json                 [PR 2]
│   └── vector.json                 [PR 2]
│
├── examples/                       ← tested reference fixtures
│   ├── envelopes/                  [PR 2]
│   ├── discovery/                  [PR 2]
│   ├── recipes/                    [PR 2]
│   └── vectors/                    [PR 2]
│
├── conformance/                    ← tier-graded scaffolds
│   └── (per-tier test vectors and rules) [PR 13]
│
├── docs/                           ← Astro Starlight site (generated) [PR 12]
│
└── tools/skills/                   ← skill source-of-truth, versioned in repo
    ├── install.sh                  ← symlinks into ~/.claude/skills/ [PR 23]
    ├── harness-api-design/
    │   ├── SKILL.md                [PR 23]
    │   └── references/             [PR 23]
    ├── harness-api-review/
    │   ├── SKILL.md                [PR 24]
    │   └── references/             [PR 24]
    ├── harness-conformance-test/
    │   ├── SKILL.md                [PR 25]
    │   └── references/             [PR 25]
    └── harness-api-migrate/
        ├── SKILL.md                [PR 26]
        └── references/             [PR 26]
```

---

## PR Map

| Phase | PR | Title | Depends on |
|---|---|---|---|
| **A — Foundation** | 0 | Repo bootstrap | — |
| | 1 | Spec markdown + index.json | 0 |
| | 2 | JSON Schemas + tested examples | 0 |
| | 3 | `harp-core` + `harp-fixtures` crates | 0, 2 |
| **B — Static analysis** | 4 | `harp-openapi` crate | 3 |
| | 5 | `harp-lint` L1 rules | 3, 4 |
| | 6 | `harp-lint` L2 rules | 5 |
| | 7 | `harp-lint` L3 rules | 6 |
| **C — CLI** | 8 | `harp` binary skeleton + clap | 3 |
| | 9 | `harp lint` subcommand | 5, 8 |
| | 10 | `harp-codegen` + `harp init`/`scaffold` | 8 |
| | 11 | `harp-migrate` + `harp migrate` | 8 |
| | 12 | `harp docs build` (Astro Starlight) | 10 |
| **D — Conformance** | 13 | `harp-conformance` crate | 4, 5 |
| | 14 | `harp test` subcommand | 13 |
| **E — Reference middleware** | 15 | `harp-axum` core middleware | 3 |
| | 16 | `harp-axum` extractors | 15 |
| | 17 | `ref-impl/rust-axum` server | 15, 16 |
| | 18 | `harp serve-refs` subcommand | 17 |
| **F — Python** | 19 | `py-harp` PyO3 setup | 3 |
| | 20 | `harp.fastapi` middleware | 19 |
| | 21 | `harp.fastapi` decorators | 20 |
| | 22 | `ref-impl/python-fastapi` server | 21 |
| **G — Skills** | 23 | `harness-api-design` skill | 1 |
| | 24 | `harness-api-review` skill | 1, 7 |
| | 25 | `harness-conformance-test` skill | 1, 14 |
| | 26 | `harness-api-migrate` skill | 1, 11 |
| **H — Polish** | 27 | End-to-end smoke + ref-impl conformance CI | 17, 22 |
| | 28 | v0.1.0 release prep | all |

29 PRs. Critical path: 0 → 1, 2, 3 → 4, 5, 8 → 6 → 7 → 9 → 14, 17. Everything else parallelizes after PR 3.

---

## Phase A — Foundation

### PR 0: Repo bootstrap

**Goal:** Create `~/Documents/GitHub/harness-protocol/` with workspace skeleton, Make targets, CI, and contributor docs. No code — just structure.

**Files:**
- Create: `Cargo.toml` (workspace root)
- Create: `Makefile`
- Create: `README.md`
- Create: `CONTRIBUTING.md`
- Create: `LICENSE` (MIT)
- Create: `.gitignore`
- Create: `rust-toolchain.toml`
- Create: `.github/workflows/rust.yml`
- Create: `.github/workflows/schemas.yml` (stub — fully implemented in PR 2)

- [ ] **Step 1: Initialize repo**

```bash
cd ~/Documents/GitHub
mkdir harness-protocol && cd harness-protocol
git init
git remote add origin git@github.com:demml/harness-protocol.git
```

- [ ] **Step 2: Write workspace `Cargo.toml`**

```toml
[workspace]
resolver = "2"
members = ["crates/*"]
default-members = ["crates/*"]

[workspace.package]
version = "0.1.0"
authors = ["Steven Forrester <sjforrester32@gmail.com>"]
edition = "2024"
license = "MIT"
repository = "https://github.com/demml/harness-protocol"
rust-version = "1.85"

[workspace.dependencies]
# internal — populated as crates land
harp = { path = "crates/harp" }
harp-core = { path = "crates/harp-core" }
harp-openapi = { path = "crates/harp-openapi" }
harp-lint = { path = "crates/harp-lint" }
harp-conformance = { path = "crates/harp-conformance" }
harp-migrate = { path = "crates/harp-migrate" }
harp-codegen = { path = "crates/harp-codegen" }
harp-axum = { path = "crates/harp-axum" }
harp-fixtures = { path = "crates/harp-fixtures" }

# external
clap = { version = "4", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
serde_yaml = "0.9"
openapiv3 = "2"
jsonschema = "0.18"
reqwest = { version = "0.12", default-features = false, features = ["json", "rustls-tls"] }
tokio = { version = "1", features = ["full"] }
tower = "0.5"
tower-http = { version = "0.6", features = ["trace"] }
axum = "0.7"
thiserror = "1"
anyhow = "1"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
tabled = "0.16"
chrono = { version = "0.4", features = ["serde"] }
hmac = "0.12"
sha2 = "0.10"
uuid = { version = "1", features = ["v4", "serde"] }
base64 = "0.22"
url = "2"

[workspace.dev-dependencies]
mockito = "1"
tempfile = "3"
pretty_assertions = "1"
```

- [ ] **Step 3: Write `rust-toolchain.toml`**

```toml
[toolchain]
channel = "1.85"
components = ["rustfmt", "clippy"]
```

- [ ] **Step 4: Write `Makefile` mirroring opsml conventions**

```makefile
.PHONY: format lints test test.unit build clean

format:
	cargo fmt --all

lints:
	cargo clippy --workspace --all-targets --all-features -- -D warnings

test.unit:
	cargo test --workspace --all-features -- --nocapture --test-threads=1

test:
	$(MAKE) test.unit

build:
	cargo build --workspace --all-features --release

clean:
	cargo clean
```

- [ ] **Step 5: Write `.gitignore`**

```
/target
/Cargo.lock.bak
.DS_Store
*.swp
.idea/
.vscode/
__pycache__/
*.pyc
.venv/
.pytest_cache/
.mypy_cache/
.ruff_cache/
docs/dist/
docs/.astro/
docs/node_modules/
node_modules/
.cache/
```

- [ ] **Step 6: Write MIT `LICENSE`** (standard MIT text, copyright Steven Forrester)

- [ ] **Step 7: Write `README.md`** — minimal: project name, one-paragraph pitch, link to spec, link to CONTRIBUTING, install/quickstart placeholder ("coming with v0.1.0").

- [ ] **Step 8: Write `CONTRIBUTING.md`** — branch model, commit style (Conventional Commits), how to run lints/tests, PR review expectations.

- [ ] **Step 9: Write `.github/workflows/rust.yml`**

```yaml
name: rust
on: [push, pull_request]
jobs:
  rust:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@1.85
        with:
          components: rustfmt, clippy
      - uses: Swatinem/rust-cache@v2
      - run: cargo fmt --all -- --check
      - run: cargo clippy --workspace --all-targets --all-features -- -D warnings
      - run: cargo test --workspace --all-features
```

- [ ] **Step 10: Verify workspace builds (no crates yet, but `cargo metadata` succeeds)**

Run: `cargo metadata --format-version 1 > /dev/null && echo OK`
Expected: `OK`

- [ ] **Step 11: Initial commit**

```bash
git add .
git commit -m "chore: initial repo scaffold"
git push -u origin main
```

**Acceptance:** Repo exists, CI green on push (rust workflow runs but skips since no crates yet — `cargo test --workspace` exits 0 with no targets). Schema CI workflow not added until PR 2 (no vacuous green job).

---

### PR 1: Spec markdown + `spec/index.json`

**Goal:** Vendor the spec content into 15 markdown files with frontmatter + machine-readable index, copied and split from the design doc at `docs/superpowers/specs/2026-05-02-harp-protocol-design.md`.

**Files:**
- Create: `spec/00-overview.md` through `spec/14-tooling.md` (15 files)
- Create: `spec/index.json`
- Create: `scripts/regen-spec-index.sh` (regenerates `index.json` from frontmatter)

- [ ] **Step 1: Author `spec/00-overview.md`** with frontmatter + content from design doc §1-§4:

```markdown
---
id: harp-overview
status: draft
normative: false
tier: null
version: 0.1
depends_on: []
---

# HARP — Harness Agent-Ready Protocol — Overview

[content from design doc §1 Problem, §2 Goals/Non-Goals, §4 Tier Map]
```

- [ ] **Step 2: Author `spec/01-envelope.md`** from design doc §6 + frontmatter:

```yaml
---
id: harp-envelope
status: draft
normative: true
tier: L1
version: 0.1
depends_on: []
---
```

- [ ] **Step 3: Author `spec/02-discovery.md`** from §5 (tier L1, depends_on `[harp-envelope]`).
- [ ] **Step 4: Author `spec/03-openapi-extensions.md`** from §7 (L1, depends_on `[harp-envelope]`).
- [ ] **Step 5: Author `spec/04-write-safety.md`** from §8 (L3).
- [ ] **Step 6: Author `spec/05-write-correctness.md`** from §9 (L2).
- [ ] **Step 7: Author `spec/06-long-running.md`** from §12 (L3).
- [ ] **Step 8: Author `spec/07-recipes.md`** from §14 (L3).
- [ ] **Step 9: Author `spec/08-capability-negotiation.md`** from §10 (L3).
- [ ] **Step 10: Author `spec/09-self-test-vectors.md`** from §15 (cross-tier).
- [ ] **Step 11: Author `spec/10-audit.md`** from §11 (L2).
- [ ] **Step 12: Author `spec/11-auth-scopes.md`** from §13 (L1).
- [ ] **Step 13: Author `spec/12-tiers.md`** from §4 (cross-tier, normative — defines compliance thresholds).
- [ ] **Step 14: Author `spec/13-conformance.md`** from §18 (cross-tier).
- [ ] **Step 15: Author `spec/14-tooling.md`** from §21 (non-normative).

- [ ] **Step 16: Write `scripts/regen-spec-index.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
out="spec/index.json"
echo '{"harp_version": "0.1", "sections": [' > "$out"
first=1
for f in spec/[0-9]*.md; do
  id=$(awk '/^id:/ {print $2; exit}' "$f")
  status=$(awk '/^status:/ {print $2; exit}' "$f")
  normative=$(awk '/^normative:/ {print $2; exit}' "$f")
  tier=$(awk '/^tier:/ {print $2; exit}' "$f")
  must=$(grep -c '\bMUST\b' "$f" || true)
  [[ $first -eq 0 ]] && echo "," >> "$out"
  first=0
  printf '  {"id": "%s", "file": "%s", "status": "%s", "normative": %s, "tier": %s, "must_count": %d}' \
    "$id" "${f#spec/}" "$status" "$normative" "$tier" "$must" >> "$out"
done
echo "" >> "$out"
echo ']}' >> "$out"
chmod 0644 "$out"
```

- [ ] **Step 17: Run script and verify `spec/index.json` valid JSON**

```bash
chmod +x scripts/regen-spec-index.sh
./scripts/regen-spec-index.sh
python3 -c "import json; json.load(open('spec/index.json'))"
```

- [ ] **Step 18: Add CI step to `.github/workflows/schemas.yml`** ensuring `index.json` matches regen output (drift detection).

- [ ] **Step 19: Commit**

```bash
git add spec/ scripts/regen-spec-index.sh .github/workflows/schemas.yml
git commit -m "feat(spec): vendor markdown spec + index.json regeneration"
```

**Acceptance:** All 15 markdown files have valid frontmatter; `spec/index.json` is valid JSON listing all 15 sections; CI fails if frontmatter and index drift.

---

### PR 2: JSON Schemas + tested examples

**Goal:** Hand-write JSON Schema 2020-12 for every normative wire structure. Ship matching examples that validate via CI.

**Files:**
- Create: `schemas/envelope-error.json`
- Create: `schemas/envelope-success.json`
- Create: `schemas/discovery.json`
- Create: `schemas/openapi-extension.json`
- Create: `schemas/recipe.json`
- Create: `schemas/vector.json`
- Create: `examples/envelopes/error-not-found.json`
- Create: `examples/envelopes/error-validation.json`
- Create: `examples/envelopes/success-resource.json`
- Create: `examples/envelopes/success-list.json`
- Create: `examples/discovery/scouter-l2.yaml`
- Create: `examples/recipes/register-drift-workflow.yaml`
- Create: `examples/vectors/register-drift-profile.json`
- Create: `scripts/validate-examples.sh`
- Create: `.github/workflows/schemas.yml` (full validation; not stubbed in PR 0)

- [ ] **Step 1: Author `schemas/envelope-error.json`** matching design doc §6.1 exactly. Required fields: `error.message`, `error.code`, `error.retry`, `error.trace_id`, `error.occurred_at`, `_meta.schema_ref`, `_meta.tier`, `_meta.service_version`. `error.field`, `error.hint`, `error.doc_url`, `error.suggested_action` optional.

- [ ] **Step 2: Author `schemas/envelope-success.json`** matching §6.2. Required: `data` (any), `_meta.schema_ref`, `_meta.tier`, `_meta.service_version`, `_meta.trace_id`, `_meta.occurred_at`. `_actions[]`, `_meta.etag`, `_meta.deprecation`, `_meta.cost` optional.

- [ ] **Step 3: Author `schemas/discovery.json`** matching §5 exactly: L1 requires `harness_version`, `service`, `links.openapi`, `links.errors`, `auth.modes`, `errors.envelope_schema`, and `trace.header`; L2+ adds `capabilities`, `budgets`, and richer `links`.

- [ ] **Step 4: Author `schemas/openapi-extension.json`** for the `x-harness` block (§7) including `two_phase_token_ttl_seconds`.

- [ ] **Step 5: Author `schemas/recipe.json`** matching §14: `id`, `title`, `description`, `when_to_use`, `inputs[]`, `outputs[]`, `steps[].operation_id`, `failure_modes[]`, `examples_ref`, `tier`.

- [ ] **Step 6: Author `schemas/vector.json`** matching §15. Document substitution placeholders (`$TOKEN`, `$UUID`, `$NOW`, `$ETAG_FROM_STEP_<n>`) in schema description fields.

- [ ] **Step 7: Author each example file** — content matches its schema, exercises every field at least once across the example set.

- [ ] **Step 8: Write `scripts/validate-examples.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
fail=0
validate() { python3 -c "import json,sys,jsonschema; jsonschema.validate(json.load(open(sys.argv[1])), json.load(open(sys.argv[2])))" "$1" "$2" || { echo "FAIL: $1 vs $2"; fail=1; }; }
validate examples/envelopes/error-not-found.json schemas/envelope-error.json
validate examples/envelopes/error-validation.json schemas/envelope-error.json
validate examples/envelopes/success-resource.json schemas/envelope-success.json
validate examples/envelopes/success-list.json schemas/envelope-success.json
# YAML examples — convert via `yq`
yq -o=json examples/discovery/scouter-l2.yaml | python3 -c "import json,sys,jsonschema; jsonschema.validate(json.loads(sys.stdin.read()), json.load(open('schemas/discovery.json')))" || { echo "FAIL: discovery"; fail=1; }
yq -o=json examples/recipes/register-drift-workflow.yaml | python3 -c "import json,sys,jsonschema; jsonschema.validate(json.loads(sys.stdin.read()), json.load(open('schemas/recipe.json')))" || { echo "FAIL: recipe"; fail=1; }
validate examples/vectors/register-drift-profile.json schemas/vector.json
exit $fail
```

- [ ] **Step 9: Run validation locally**

```bash
pip install jsonschema
brew install yq  # or apt
chmod +x scripts/validate-examples.sh
./scripts/validate-examples.sh && echo "all examples valid"
```

- [ ] **Step 10: Create `.github/workflows/schemas.yml`** (new file; PR 0 did not stub this) — installs jsonschema + yq and runs `scripts/validate-examples.sh` and `scripts/regen-spec-index.sh` (drift check via `git diff --exit-code spec/index.json`).

```yaml
name: schemas
on: [push, pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - run: pip install jsonschema
      - run: sudo apt-get update && sudo apt-get install -y yq
      - run: ./scripts/validate-examples.sh
      - run: ./scripts/regen-spec-index.sh
      - run: git diff --exit-code spec/index.json
```

- [ ] **Step 11: Verify CI green by running locally**

```bash
./scripts/validate-examples.sh
./scripts/regen-spec-index.sh
git diff --exit-code spec/index.json
```

- [ ] **Step 12: Commit**

```bash
git add schemas/ examples/ scripts/validate-examples.sh .github/workflows/schemas.yml
git commit -m "feat(schemas): JSON Schemas for envelope/discovery/extension/recipe/vector + tested examples"
```

**Acceptance:** Every example validates against its schema in CI. `spec/index.json` regenerates without drift. CI fails on schema or example breakage.

---

### PR 3: `harp-core` + `harp-fixtures` crates

**Goal:** Pure-Rust serde types for every protocol structure; canonical HARP_* error code constants; shared test fixtures.

**Files:**
- Create: `crates/harp-core/Cargo.toml`
- Create: `crates/harp-core/src/lib.rs`, `error.rs`, `codes.rs`, `envelope.rs`, `discovery.rs`, `extension.rs`, `recipe.rs`, `vector.rs`, `tier.rs`
- Create: `crates/harp-core/tests/envelope_test.rs`, `discovery_test.rs`, `extension_test.rs`
- Create: `crates/harp-fixtures/Cargo.toml`
- Create: `crates/harp-fixtures/src/lib.rs`, `envelopes.rs`, `discovery.rs`, `vectors.rs`

- [ ] **Step 1: Write `crates/harp-core/Cargo.toml`**

```toml
[package]
name = "harp-core"
version = { workspace = true }
edition = { workspace = true }
license = { workspace = true }
repository = { workspace = true }
description = "HARP protocol core types"

[dependencies]
serde = { workspace = true }
serde_json = { workspace = true }
serde_yaml = { workspace = true }
chrono = { workspace = true }
thiserror = { workspace = true }
url = { workspace = true }

[dev-dependencies]
harp-fixtures = { workspace = true }
pretty_assertions = { workspace = true }
```

- [ ] **Step 2: Write the failing test for error envelope deserialization**

`crates/harp-core/tests/envelope_test.rs`:

```rust
use harp_core::envelope::ErrorEnvelope;

#[test]
fn deserializes_canonical_error_envelope() {
    let json = harp_fixtures::envelopes::ERROR_NOT_FOUND;
    let env: ErrorEnvelope = serde_json::from_str(json).expect("deserialize");
    assert_eq!(env.error.code, "SCOUTER_DATACARD_NOT_FOUND");
    assert_eq!(env.error.field.as_deref(), Some("datacard_uid"));
    assert!(!env.error.retry.retryable);
    assert_eq!(env._meta.tier, harp_core::tier::Tier::L1);
}
```

- [ ] **Step 3: Run test — expected fail (`harp-core` types don't exist)**

```bash
cargo test -p harp-core --test envelope_test
```

Expected: compile error, types missing.

- [ ] **Step 4: Implement minimal `harp-core` types in `envelope.rs`, `tier.rs`, `lib.rs`** sufficient to make the test compile and pass. Types follow design doc §6 exactly. All `#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]`. Use `chrono::DateTime<Utc>` for timestamps. `field` is `Option<String>` (JSON-pointer string).

- [ ] **Step 5: Run test, expect pass**

```bash
cargo test -p harp-core --test envelope_test -- --nocapture
```

Expected: `test deserializes_canonical_error_envelope ... ok`.

- [ ] **Step 6: Repeat TDD cycle for `success-resource.json` and `success-list.json`** (with pagination).

- [ ] **Step 7: Repeat TDD cycle for `discovery.json` deserialization** in `tests/discovery_test.rs`.

- [ ] **Step 8: Repeat TDD cycle for `x-harness` extension deserialization** in `tests/extension_test.rs` covering all fields including `two_phase_token_ttl_seconds`.

- [ ] **Step 9: Implement `codes.rs` — canonical HARP_* constants**

```rust
pub const HARP_ETAG_MISMATCH: &str = "HARP_ETAG_MISMATCH";
pub const HARP_INSUFFICIENT_SCOPE: &str = "HARP_INSUFFICIENT_SCOPE";
pub const HARP_IDEMPOTENCY_KEY_REUSED: &str = "HARP_IDEMPOTENCY_KEY_REUSED";
pub const HARP_TOKEN_CONSUMED: &str = "HARP_TOKEN_CONSUMED";
pub const HARP_TOKEN_BINDING_MISMATCH: &str = "HARP_TOKEN_BINDING_MISMATCH";
pub const HARP_TOKEN_EXPIRED: &str = "HARP_TOKEN_EXPIRED";
pub const HARP_DRY_RUN_NOT_SUPPORTED: &str = "HARP_DRY_RUN_NOT_SUPPORTED";
pub const HARP_TWO_PHASE_NOT_SUPPORTED: &str = "HARP_TWO_PHASE_NOT_SUPPORTED";
pub const HARP_LONG_RUNNING_NOT_SUPPORTED: &str = "HARP_LONG_RUNNING_NOT_SUPPORTED";
pub const HARP_VECTOR_PLACEHOLDER_UNRESOLVED: &str = "HARP_VECTOR_PLACEHOLDER_UNRESOLVED";
```

- [ ] **Step 10: Implement `recipe.rs` and `vector.rs` types** with full serde round-trip tests using example files from PR 2.

- [ ] **Step 11: Write `crates/harp-fixtures/Cargo.toml` and `src/`** — `include_str!` the example JSON files into `pub const` strings:

```rust
// crates/harp-fixtures/src/envelopes.rs
pub const ERROR_NOT_FOUND: &str = include_str!("../../../examples/envelopes/error-not-found.json");
pub const ERROR_VALIDATION: &str = include_str!("../../../examples/envelopes/error-validation.json");
pub const SUCCESS_RESOURCE: &str = include_str!("../../../examples/envelopes/success-resource.json");
pub const SUCCESS_LIST: &str = include_str!("../../../examples/envelopes/success-list.json");
```

- [ ] **Step 12: Run full test suite for both crates**

```bash
cargo test -p harp-core --all-features -- --nocapture --test-threads=1
cargo test -p harp-fixtures --all-features -- --nocapture --test-threads=1
```

Expected: all green.

- [ ] **Step 13: Commit**

```bash
git add crates/harp-core crates/harp-fixtures
git commit -m "feat(harp-core,harp-fixtures): protocol types + shared fixtures"
```

**Acceptance:** All canonical wire shapes round-trip via serde. Fixture crate centralizes example JSON used by every downstream test. `cargo test --workspace --all-features` passes.

---

## Phase B — Static Analysis

### PR 4: `harp-openapi` crate

**Goal:** Read OpenAPI 3.1 documents (JSON or YAML); deserialize `x-harness` extensions; provide a typed AST for downstream lint rules.

**Files:**
- Create: `crates/harp-openapi/Cargo.toml`
- Create: `crates/harp-openapi/src/lib.rs`, `reader.rs`, `writer.rs`, `error.rs`
- Create: `crates/harp-openapi/tests/reader_test.rs`
- Create: `crates/harp-fixtures/openapi/scouter-l1.yaml` (sample OpenAPI doc with `x-harness` annotations)

- [ ] **Step 1: Cargo.toml depends on `openapiv3`, `harp-core`, `serde_yaml`, `serde_json`, `thiserror`.**

- [ ] **Step 2: Write the failing test for reading an OpenAPI doc and extracting `x-harness` per-op**

```rust
#[test]
fn reads_x_harness_per_operation() {
    let doc = harp_openapi::reader::read_yaml_str(harp_fixtures::openapi::SCOUTER_L1).unwrap();
    let op = doc.find_op("registerDriftProfile").unwrap();
    let harness = op.x_harness().unwrap();
    assert_eq!(harness.semantics, harp_core::extension::Semantics::Write);
    assert_eq!(harness.possible_errors.len(), 3);
}
```

- [ ] **Step 3: Run test (fail).**
- [ ] **Step 4: Implement `reader.rs`** wrapping `openapiv3::OpenAPI` with helpers: `read_yaml_str`, `read_json_str`, `read_path`. Provide `find_op(operation_id) -> Option<OperationView>`. `OperationView::x_harness()` deserializes the vendor extension into `harp_core::extension::XHarness`.
- [ ] **Step 5: Implement `writer.rs`** with `to_yaml_string`, `to_json_string`, preserving extension keys.
- [ ] **Step 6: Run test (pass).**
- [ ] **Step 7: Add round-trip test** (read → write → read) verifying no data loss.
- [ ] **Step 8: Commit.**

**Acceptance:** OpenAPI YAML/JSON reads to typed AST; `x-harness` accessible per op; round-trip lossless.

---

### PR 5: `harp-lint` L1 rules

**Goal:** Tier-rule engine + L1 rules. Pure logic, no IO.

**Files:**
- Create: `crates/harp-lint/Cargo.toml`
- Create: `crates/harp-lint/src/lib.rs`, `error.rs`, `violation.rs`, `runner.rs`, `rules/mod.rs`, `rules/l1.rs`
- Create: `crates/harp-lint/tests/l1_test.rs`
- Create: `crates/harp-fixtures/openapi/missing-semantics.yaml`
- Create: `crates/harp-fixtures/openapi/orphan-error-code.yaml`

- [ ] **Step 1: Define `Violation` type**

```rust
pub struct Violation {
    pub rule_id: String,           // e.g. "L1.semantics-required"
    pub tier: Tier,
    pub severity: Severity,        // Error | Warning
    pub location: Location,        // file path, json-pointer, op_id
    pub message: String,
    pub spec_section: String,      // e.g. "harp-openapi-extensions"
}
```

- [ ] **Step 2: Define `Rule` trait**

```rust
pub trait Rule {
    fn id(&self) -> &'static str;
    fn tier(&self) -> Tier;
    fn check(&self, ctx: &LintContext) -> Vec<Violation>;
}
```

- [ ] **Step 3: Define `LintContext`** holding parsed OpenAPI doc, parsed harness.yaml, schemas dir path, examples dir path, vectors dir path.

- [ ] **Step 4: Write the failing test for "every op MUST have semantics"**

```rust
#[test]
fn flags_op_without_semantics() {
    let ctx = LintContext::from_yaml_str(harp_fixtures::openapi::MISSING_SEMANTICS).unwrap();
    let violations = harp_lint::run_tier(Tier::L1, &ctx);
    assert!(violations.iter().any(|v| v.rule_id == "L1.semantics-required"));
}
```

- [ ] **Step 5: Implement `rules/l1.rs` rules:**
  - `L1.semantics-required` — every op has `x-harness.semantics`
  - `L1.error-code-namespaced` — codes match `^[A-Z][A-Z0-9_]+_[A-Z0-9_]+$`
  - `L1.examples-ref-resolves` — `examples_ref` URL points to a vector file existing on disk
  - `L1.discovery-doc-shape` — minimal discovery doc validates against `schemas/discovery.json`
  - `L1.trace-id-header-declared` — discovery doc declares `trace.header`
  - `L1.scopes-declared` — every op with mutating semantics has `scopes_required`
  - `L1.versioning-headers-documented` — OpenAPI declares `Deprecation`, `Sunset` as response header refs

- [ ] **Step 6: Implement `runner.rs`** — `run_tier(tier, &ctx) -> Vec<Violation>` runs all rules of that tier. `run_up_to(tier, &ctx)` runs all rules at and below.

- [ ] **Step 7: Run tests (pass for each rule).**
- [ ] **Step 8: Commit.**

**Acceptance:** All seven L1 rules fire on crafted negative fixtures and pass on positive fixtures.

---

### PR 6: `harp-lint` L2 rules

**Files:**
- Modify: `crates/harp-lint/src/rules/l2.rs` (new file)
- Modify: `crates/harp-lint/src/rules/mod.rs`
- Create: tests + negative fixtures

- [ ] **Step 1-N: TDD per rule (one rule per cycle):**
  - `L2.discovery-rich-fields` — `harness.yaml` includes and validates L2 discovery fields (`capabilities`, `budgets`, and required richer links)
  - `L2.meta-required-on-success` — every 2xx response schema declares `_meta`
  - `L2.actions-resolve` — `_actions[].rel` references exist as ops in OpenAPI; actions with `requires_two_phase: true` include `preview_href` and `commit_href`
  - `L2.idempotency-key-header-documented` — ops with `idempotent: true` declare `Idempotency-Key` parameter
  - `L2.etag-required-on-mutating-reads` — ops returning resources used by `requires_etag: true` writes return `ETag` header
  - `L2.cost-headers-declared` — `HARP-Cost-Units`, `HARP-Actual-Ms` declared as response headers
  - `L2.audit-endpoints-present` — `/audit/trace/{id}`, `/audit?resource=...`, `/audit/causality/{id}` present
  - `L2.deprecation-headers-paired` — non-null `deprecation` produces `Deprecation` + `Sunset` + `Link rel=successor` headers in OpenAPI

- [ ] **Final: Commit.**

**Acceptance:** Eight L2 rules with positive + negative fixtures.

---

### PR 7: `harp-lint` L3 rules

**Files:**
- Create: `crates/harp-lint/src/rules/l3.rs` + tests + fixtures

- [ ] **TDD per rule:**
  - `L3.dry-run-vector-coverage` — every op with `dry_run: true` has a dry-run vector
  - `L3.two-phase-vector-coverage` — every op with `two_phase: true` has preview + commit vector pair
  - `L3.long-running-jobs-endpoints` — `/jobs/{id}`, `/jobs/{id}/result`, `DELETE /jobs/{id}`, `GET /jobs?...` present
  - `L3.recipe-dag-references-real-ops` — every recipe step `operation_id` resolves to real OpenAPI operation
  - `L3.recipe-template-parseable` — `body_template` parses with `${...}` grammar (only `inputs.X` and `steps.<id>.<captured>` namespaces allowed)
  - `L3.failure-vector-per-error` — every `possible_errors` entry has a failure vector at L2+ (rule registered at L2 but enforced via vector-coverage logic that also runs in L3 context). **Implementer note:** add a doc comment in `rules/l2.rs` explicitly stating this rule's tier assignment is intentional and that the L3-context enforcement is by design — prevents a future contributor from "fixing" the placement.
  - `L3.capability-negotiation-headers-documented` — `HARP-Verbosity`, `HARP-Context-Budget`, etc. declared
  - `L3.callback-secret-not-echoed` — job poll response schemas omit `callback_secret`

- [ ] **Final: Commit.**

**Acceptance:** Eight L3 rules; full lint suite (L1 + L2 + L3) green on the canonical scouter-L3 fixture (added in this PR).

---

## Phase C — CLI

### PR 8: `harp` binary skeleton + clap

**Goal:** `harp` binary that parses subcommands but does nothing yet (each subcommand is a `todo!()` action). Delivers shared flags, output formatting, exit codes.

**Files:**
- Create: `crates/harp/Cargo.toml`
- Create: `crates/harp/src/main.rs`, `lib.rs`, `error.rs`, `cli/mod.rs`, `actions/mod.rs`
- Create: stub files for each subcommand: `cli/{init,scaffold,lint,test,migrate,docs,serve_refs}.rs`, mirror in `actions/`

- [ ] **Step 1: Cargo.toml**

```toml
[package]
name = "harp"
version = { workspace = true }
edition = { workspace = true }
license = { workspace = true }

[[bin]]
name = "harp"
path = "src/main.rs"

[dependencies]
clap = { workspace = true }
serde = { workspace = true }
serde_json = { workspace = true }
serde_yaml = { workspace = true }
anyhow = { workspace = true }
thiserror = { workspace = true }
tracing = { workspace = true }
tracing-subscriber = { workspace = true }
tabled = { workspace = true }
harp-core = { workspace = true }
```

- [ ] **Step 2: Write `cli/mod.rs` with the top-level `Cli` struct (clap derive)**

```rust
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "harp", version, about = "HARP — Harness Agent-Ready Protocol")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
    #[arg(long, global = true, default_value = "human")]
    pub format: OutputFormat,
    #[arg(long, global = true)]
    pub config: Option<std::path::PathBuf>,
    #[arg(short, long, global = true, action = clap::ArgAction::Count)]
    pub verbose: u8,
    #[arg(long, global = true)]
    pub quiet: bool,
}

#[derive(Subcommand)]
pub enum Command {
    Init(crate::cli::init::Args),
    Scaffold(crate::cli::scaffold::Args),
    Lint(crate::cli::lint::Args),
    Test(crate::cli::test::Args),
    Migrate(crate::cli::migrate::Args),
    Docs { #[command(subcommand)] action: crate::cli::docs::DocsAction },
    ServeRefs(crate::cli::serve_refs::Args),
}

#[derive(clap::ValueEnum, Clone, Debug)]
pub enum OutputFormat { Human, Json }
```

- [ ] **Step 3: Each `cli/<cmd>.rs` defines its `Args` struct (clap derive) and a `run(&Args, &GlobalCtx)` that calls `actions::<cmd>::run`.**
- [ ] **Step 4: Each `actions/<cmd>.rs` is `pub fn run(...) -> Result<()>` body = `todo!("PR N")`.**
- [ ] **Step 5: `main.rs` parses CLI, sets up tracing per `--verbose`/`--quiet`, dispatches to subcommand `run`. Maps result to exit code (0 ok, 1 violation, 2 error).**
- [ ] **Step 6: Smoke test**

```bash
cargo run -p harp -- --help
cargo run -p harp -- lint --help
```

- [ ] **Step 7: Commit.**

**Acceptance:** `harp --help` prints the full subcommand surface.

---

### PR 9: `harp lint` subcommand

**Goal:** Wire `harp-lint` runner into the CLI. Single shipping subcommand.

**Files:**
- Modify: `crates/harp/src/cli/lint.rs`, `actions/lint.rs`
- Modify: `crates/harp/Cargo.toml` (add `harp-lint`, `harp-openapi` deps)
- Create: `crates/harp/tests/lint_smoke.rs`

- [ ] **Step 1: `cli/lint.rs::Args`**

```rust
#[derive(clap::Args)]
pub struct Args {
    #[arg(long, default_value = "openapi.yaml")]
    pub openapi: std::path::PathBuf,
    #[arg(long, default_value = "harness.yaml")]
    pub harness: std::path::PathBuf,
    #[arg(long, value_enum)]
    pub tier: Option<crate::cli::lint::Tier>,    // None = up-to declared max
    #[arg(long)]
    pub schemas_dir: Option<std::path::PathBuf>,
}
```

- [ ] **Step 2: Failing integration test using harp-fixtures fixture set; expect violations on missing-semantics fixture.**
- [ ] **Step 3: `actions/lint.rs::run` reads files via `harp-openapi`, builds `LintContext`, calls `harp_lint::run_up_to`, formats output (human table or JSON via `--format`).**
- [ ] **Step 4: Test passes.**
- [ ] **Step 5: Commit.**

**Acceptance:** `harp lint --openapi <bad>.yaml` exits 1 with formatted violations; `harp lint --openapi <good>.yaml` exits 0.

---

### PR 10: `harp-codegen` + `harp init` / `harp scaffold`

**Goal:** Bootstrap an OpenAPI doc with `x-harness` skeletons (`init`); generate ancillary files from existing annotations (`scaffold`).

**Files:**
- Create: `crates/harp-codegen/Cargo.toml`, `src/{lib,init,scaffold,error}.rs`
- Modify: `crates/harp/Cargo.toml`, `cli/init.rs`, `cli/scaffold.rs`, `actions/init.rs`, `actions/scaffold.rs`
- Create: tests for both

- [ ] **Step 1: TDD `harp-codegen::init::scaffold_x_harness(openapi) -> ModifiedDoc`** — for each op without `x-harness`, insert a default block with `semantics: read` (safe default), `stability: experimental`, `possible_errors: []` (with TODO comment), `examples_ref: null`. Operations with HTTP method != GET get `semantics: write`; destructive methods get `semantics: destructive` only when inferred from DELETE or explicitly configured. Idempotent and long-running behavior remain separate flags.
- [ ] **Step 2: TDD `harp-codegen::scaffold::generate_all(openapi, harness, out_dir)`** — emits `harness.yaml`, `errors.yaml`, `discovery.yaml` skeleton, `vectors/<op_id>.json` skeletons.
- [ ] **Step 3: Wire to CLI; confirm `harp init --openapi foo.yaml --target-tier L1` writes a modified doc + harness.yaml in-place (`--dry-run` prints diff instead).**
- [ ] **Step 4: Commit.**

**Acceptance:** Running `harp init` then `harp lint --tier L1` on a virgin OpenAPI doc reduces violations; running `harp scaffold` after manual edits regenerates dependent files.

---

### PR 11: `harp-migrate` + `harp migrate`

**Goal:** Diff current state against target tier; emit patch suggestions.

**Files:**
- Create: `crates/harp-migrate/Cargo.toml`, `src/{lib,differ,patch,error}.rs`
- Modify: CLI wiring

- [ ] **Step 1: `Differ::diff(current_tier, target_tier, &ctx) -> Vec<Patch>`** where each `Patch` is a structured suggestion: file path, JSON-pointer, before, after, justification.
- [ ] **Step 2: Patches drive both `--dry-run` output (human-readable diff) and `--apply` (writes changes via `harp-openapi::writer`).**
- [ ] **Step 3: TDD: scoring fixture progresses L1 → L2 → L3 across multiple `harp migrate --apply` calls.**
- [ ] **Step 4: Commit.**

**Acceptance:** `harp migrate --from L1 --to L2` on the canonical L1 fixture emits actionable patches.

---

### PR 12: `harp docs build`

**Goal:** Generate a branded Astro Starlight site from `spec/`, OpenAPI, recipes, vectors.

**Files:**
- Create: `crates/harp-codegen/src/docs.rs`
- Create: `docs/template/` (Astro Starlight scaffold checked in)
- Modify: CLI wiring

- [ ] **Step 1: Create `.tool-versions`** at repo root pinning node + pnpm so docs builds are reproducible:

```
nodejs 22.11.0
pnpm 9.12.0
```

- [ ] **Step 2: `harp-codegen::docs::generate(spec_dir, openapi, harness_yaml, out_dir)`** copies `docs/template/` + writes generated `.md` pages from spec content + emits `astro.config.mjs` populated with sidebar based on `spec/index.json`.
- [ ] **Step 3: `harp docs build --out docs/dist` runs codegen then shells out to `pnpm build` inside the output dir.** Implementation MUST detect missing `pnpm` and surface a friendly error pointing at `.tool-versions`.
- [ ] **Step 4: Commit.**

**Acceptance:** `harp docs build` produces a static site; CI runs the build step on every PR.

---

## Phase D — Conformance

### PR 13: `harp-conformance` crate

**Goal:** Replay vectors against a live URL; emit structured tier verdict.

**Files:**
- Create: `crates/harp-conformance/Cargo.toml`, `src/{lib,runner,replay,report,error}.rs`
- Create: integration tests using mockito

- [ ] **Step 1: TDD vector replay engine.**
  - Reads vector file via `harp-core`
  - Resolves placeholder substitutions from a `FixtureEnv` (auth tokens, UUID generator, NOW)
  - Performs HTTP call via `reqwest`
  - Asserts response status, header presence, body schema match
  - Returns `VectorResult { vector_id, passed, mismatch: Option<Mismatch> }`
- [ ] **Step 2: TDD conformance runner per tier — runs lint static prepass + replays all vectors + checks tier-specific dynamic rules:**
  - L1: minimal discovery doc reachable + valid, error envelope shape, trace_id header presence, examples-as-vectors replay
  - L2: rich discovery fields valid, success envelope shape, action affordances reachable, idempotency replay semantics, etag mismatch yields 412, cost headers + body parity
  - L3: dry-run produces no mutation (read-after-write check), two-phase token semantics (expired, reused, replay), long-running poll-to-completion + cancel, capability negotiation adaptation, every recipe DAG resolvable, every vector replayable
- [ ] **Step 3: `Report` JSON shape matches design doc §18.3 exactly.**
- [ ] **Step 4: Commit.**

**Acceptance:** mockito-driven integration tests exercise all three tiers; report JSON serializes to match `examples/conformance-report.json` (added in this PR as a tested example).

---

### PR 14: `harp test` subcommand

**Files:**
- Modify: `crates/harp/src/cli/test.rs`, `actions/conformance.rs`

- [ ] **Step 1: `cli/test.rs::Args` with `--url`, `--tier`, `--vectors-dir`, `--report`.**
- [ ] **Step 2: `actions/conformance::run` invokes `harp_conformance::runner`, writes JSON report if `--report`, prints human summary otherwise. Exit 0 if `tier_attained >= --tier`, else exit 1.**
- [ ] **Step 3: Smoke test against a mockito server in tests/.**
- [ ] **Step 4: Commit.**

**Acceptance:** End-to-end `harp test --url http://localhost:8080 --tier L2` against the rust ref-impl returns L2 attained.

---

## Phase E — Reference Middleware

### PR 15: `harp-axum` core middleware

**Goal:** Tower middleware that wraps every response in a HARP envelope, emits `trace_id`, mounts `/.well-known/harness/*`, generates discovery doc from axum's route registry.

**Files:**
- Create: `crates/harp-axum/Cargo.toml`, `src/{lib,middleware,discovery,error}.rs`

- [ ] **Step 1: TDD `EnvelopeLayer`** — Tower layer wrapping `axum::Response`. On 2xx with JSON body: wraps in `{data, _meta, _actions}`. On non-2xx: ensures body matches `ErrorEnvelope`, fills missing `_meta` fields. Always adds `x-trace-id` header (generates UUIDv7 if absent).
- [ ] **Step 2: TDD `DiscoveryLayer`** — mounts GET handlers for `/.well-known/harness`, `/.well-known/harness/errors`, `/.well-known/harness/scopes`, `/.well-known/harness/recipes`, `/.well-known/harness/envelope.json`, `/.well-known/harness/whoami`. Discovery doc generated from a `HarpServiceConfig` provided at app construction time.
- [ ] **Step 3: TDD `CostLayer`** — measures wall-clock and emits `HARP-Cost-Units`, `HARP-Actual-Ms` headers + `_meta.cost`.
- [ ] **Step 4: Commit.**

**Acceptance:** Demo axum app with three layers stacked yields canonical responses validated against `harp-core` types in tests.

---

### PR 16: `harp-axum` extractors

**Files:**
- Create: `crates/harp-axum/src/extractors/{mod,dry_run,two_phase,idempotency,audit}.rs`

- [ ] **Step 1: TDD `DryRun(bool)` extractor** — checks query param + header per §8.1.
- [ ] **Step 2: TDD `TwoPhase` extractor + `mint_token` / `verify_token` helpers using HMAC-SHA256.**
- [ ] **Step 3: TDD `IdempotencyKey` extractor + pluggable cache trait (in-memory default, Redis adapter behind `redis` feature).**
- [ ] **Step 4: TDD `AuditEmitter` extractor — produces audit row per §11.2; pluggable sink (Postgres adapter behind `postgres` feature).**
- [ ] **Step 5: Commit.**

**Acceptance:** Each extractor isolated and testable; all sinks pluggable via trait, defaults compile without optional features.

---

### PR 17: `ref-impl/rust-axum` server

**Files:**
- Create: `ref-impl/rust-axum/Cargo.toml`, `src/main.rs`
- Modify: `.github/workflows/conformance.yml` to spin up + run `harp test`

- [ ] **Step 1: Build a < 500 LOC axum service exercising every L1+L2+L3 feature** — at minimum: 1 read op, 1 write op, 1 idempotent write op, 1 dry-runnable write op, 1 destructive two-phase op, 1 long-running op. In-memory state. Tied to `harp-axum`.
- [ ] **Step 2: Conformance CI** boots it, runs `harp test --tier L3 --url http://localhost:8080`, fails if `tier_attained != L3`.
- [ ] **Step 3: Commit.**

**Acceptance:** CI green; `tier_attained: L3` on every PR.

---

### PR 18: `harp serve-refs` subcommand

**Files:**
- Modify: `crates/harp/src/cli/serve_refs.rs`, `actions/serve_refs.rs` (was deferred from PR 8)

- [ ] **Step 1: `harp serve-refs --lang rust` cargo-runs the rust ref-impl with `tracing-subscriber` set to info.**
- [ ] **Step 2: `--lang python` shells out to `uv run --directory ref-impl/python-fastapi uvicorn app:app`.** Until PR 22 lands and the python ref-impl exists, this branch returns a structured error (`HARP_REF_IMPL_NOT_AVAILABLE`) and exit code 2 — must NOT silently fail or panic.
- [ ] **Step 3: Commit.**

**Acceptance:** `harp serve-refs --lang rust` boots a fully-conformant HARP service. `--lang python` is non-functional with a clean error until PR 22 lands; that is documented in the subcommand `--help`.

---

## Phase F — Python

### PR 19: `py-harp` PyO3 setup

**Goal:** Stand up a maturin-managed py-harp package mirroring py-scouter / py-opsml. Expose a thin PyO3 module that wraps `harp-core` types for Python consumption.

**Files:**
- Create: `py-harp/Cargo.toml` (cdylib + pyo3)
- Create: `py-harp/pyproject.toml` (uv + maturin)
- Create: `py-harp/Makefile`
- Create: `py-harp/src/lib.rs`
- Create: `py-harp/python/harp/__init__.py`, `_harp.pyi`, `cli/__init__.py`
- Create: `py-harp/tests/test_envelope.py`
- Modify: `Cargo.toml` workspace `members` to include `py-harp`
- Create: `.github/workflows/python.yml`

- [ ] **Step 1: Cargo.toml** (PyO3 0.28 + abi3-py310 to match py-scouter / py-opsml workspace conventions; do not bump unilaterally)

```toml
[package]
name = "py-harp"
version = { workspace = true }
edition = { workspace = true }

[lib]
name = "_harp"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.28", features = ["extension-module", "abi3-py310", "anyhow", "chrono", "serde"] }
harp-core = { workspace = true }
serde_json = { workspace = true }
```

- [ ] **Step 2: `pyproject.toml`** with `uv` dev deps (`pytest`, `ruff`, `pylint`, `mypy`, `httpx`, `fastapi`, `pytest-asyncio`).

- [ ] **Step 3: PyO3 expose envelope types + lint runner stub.**
- [ ] **Step 4: TDD round-trip test — Python deserializes a fixture envelope via `_harp.deserialize_error_envelope`.**
- [ ] **Step 5: `python.yml` CI: maturin develop, ruff, pylint, mypy, pytest.**
- [ ] **Step 6: Commit.**

**Acceptance:** `cd py-harp && make setup.project && uv run pytest` green.

---

### PR 20: `harp.fastapi` middleware

**Goal:** Pure-Python ASGI middleware wrapping FastAPI responses in HARP envelope; mounting discovery routes; emitting trace_id.

**Files:**
- Create: `py-harp/python/harp/fastapi/__init__.py`, `middleware.py`
- Create: tests
- Use: `_harp.serialize_*` / `_harp.validate_*` helpers from PyO3 layer

- [ ] **Step 1: TDD `HarpMiddleware`** — wraps responses, inserts `_meta`, emits `x-trace-id`.
- [ ] **Step 2: TDD `mount_discovery(app, config)`** — adds `/.well-known/harness/*` routes from a `HarpServiceConfig` (Pydantic model).
- [ ] **Step 3: TDD `CostMiddleware`** parity with rust version.
- [ ] **Step 4: Commit.**

**Acceptance:** A FastAPI test app with the middleware passes the same envelope assertions as the rust ref-impl.

---

### PR 21: `harp.fastapi` decorators

**Files:**
- Create: `py-harp/python/harp/fastapi/decorators.py` + tests

- [ ] **Step 1-4: TDD per decorator (`@dry_run`, `@two_phase`, `@idempotent`, `@audited`) mirroring the Rust extractor semantics.**
- [ ] **Step 5: Commit.**

**Acceptance:** Same conformance properties as harp-axum extractors.

---

### PR 22: `ref-impl/python-fastapi` server

**Files:**
- Create: `ref-impl/python-fastapi/pyproject.toml`, `app.py`
- Modify: `.github/workflows/conformance.yml`

- [ ] **Step 1: < 500 LOC FastAPI app exercising same surface as rust ref-impl.**
- [ ] **Step 2: Conformance CI runs `harp test --tier L3 --url http://localhost:8000` against this app on every PR.**
- [ ] **Step 3: Commit.**

**Acceptance:** Both ref-impls attain L3 on every CI run.

---

## Phase G — Skills

Skills source files live in `harness-protocol/tools/skills/harness-*/` (versioned in the repo). Installation script `tools/skills/install.sh` symlinks them into `~/.claude/skills/` for runtime use. This gives the canonical material an auditable home, lets the pinned-commit reference in skill frontmatter resolve directly to the repo, and makes skill iteration a normal PR flow.

### PR 23: `harness-api-design` skill

**Files (versioned in repo):**
- Create: `tools/skills/harness-api-design/SKILL.md`
- Create: `tools/skills/harness-api-design/references/tier-checklists.md` (concatenated L1/L2/L3 checklists)
- Create: `tools/skills/harness-api-design/references/envelope-patterns.md`
- Create: `tools/skills/install.sh` (symlinks `tools/skills/harness-*` into `~/.claude/skills/`)

- [ ] **Step 1: Author SKILL.md per `superpowers:writing-skills` skill conventions.**

```markdown
---
name: harness-api-design
description: Use when designing or significantly refactoring an API surface. Walks through HARP tier requirements, error envelope construction, OpenAPI x-harness extension, scope grammar. Pulls canonical material from harness-protocol@<commit-hash>.
canonical_repo: https://github.com/demml/harness-protocol
canonical_commit: <pinned-hash>
---

[skill body — process: ask target tier, audit current OpenAPI, propose x-harness annotations, generate scaffolds via harp init, enumerate gaps]
```

- [ ] **Step 2: Author reference markdown files copying from `harness-protocol/spec/12-tiers.md` and `01-envelope.md` content at the pinned commit.**
- [ ] **Step 3: Manually invoke skill on a sample (e.g., scouter) project to verify it drives concrete HARP-aware design decisions.**
- [ ] **Step 4: Run `tools/skills/install.sh` to symlink into `~/.claude/skills/`. Commit the source files under `tools/skills/harness-api-design/` to the harness-protocol repo.**

**Acceptance:** Steven invokes `Skill: harness-api-design` on a real API design conversation; the skill produces a target-tier proposal + concrete x-harness suggestions.

---

### PR 24: `harness-api-review` skill

**Files:**
- Create: `tools/skills/harness-api-review/SKILL.md`
- Create: `tools/skills/harness-api-review/references/violation-catalog.md`

- [ ] **Step 1: SKILL.md drives PR review against tier requirements; uses `harp lint` output if available, else manual heuristics.**
- [ ] **Step 2: Author reference catalog of common violations + remediations.**
- [ ] **Step 3: Test on a representative diff.**
- [ ] **Step 4: Commit.**

---

### PR 25: `harness-conformance-test` skill

**Files:**
- Create: `tools/skills/harness-conformance-test/SKILL.md`
- Create: `tools/skills/harness-conformance-test/references/conformance-walkthrough.md`

- [ ] **Step 1: SKILL.md scaffolds conformance test infra: where to invoke `harp test`, how to wire it into CI, how to write custom vectors.**
- [ ] **Step 2: Reference walkthrough copies from `spec/13-conformance.md`.**
- [ ] **Step 3: Test on a stub service.**
- [ ] **Step 4: Commit.**

---

### PR 26: `harness-api-migrate` skill

**Files:**
- Create: `tools/skills/harness-api-migrate/SKILL.md`
- Create: `tools/skills/harness-api-migrate/references/migration-paths.md`

- [ ] **Step 1: SKILL.md drives progressive lift L1 → L2 → L3 of an existing OpenAPI service. Each phase produces a separate PR using `harp migrate` output as the diff baseline.**
- [ ] **Step 2: Reference paths document common patterns: "L1 in 2 days", "L1→L2 in a week", "L2→L3 in 3 weeks".**
- [ ] **Step 3: Test on a stub service.**
- [ ] **Step 4: Commit.**

---

## Phase H — Polish + Release

### PR 27: End-to-end smoke test

**Files:**
- Create: `tests/e2e/smoke.sh`
- Modify: `.github/workflows/conformance.yml`

- [ ] **Step 1: `tests/e2e/smoke.sh`** scripts the §6 of design doc verification flow:
  1. `cargo build --workspace --release`
  2. `harp serve-refs --lang rust &` background
  3. `harp test --url http://localhost:8080 --tier L3 --report report-rust.json` exit 0 + `tier_attained: L3`
  4. Kill process; same for python ref-impl
  5. `harp lint --openapi ref-impl/rust-axum/openapi.yaml --tier L3` exit 0
  6. `harp init --openapi tests/fixtures/virgin.yaml --target-tier L1 --dry-run` exit 0
  7. `harp migrate --from L1 --to L2 --openapi tests/fixtures/l1-only.yaml --dry-run` exit 0
- [ ] **Step 2: CI runs smoke on every PR.**
- [ ] **Step 3: Commit.**

**Acceptance:** End-to-end story works from a clean clone in CI.

---

### PR 28: v0.1.0 release prep

**Files:**
- Create: `CHANGELOG.md`
- Modify: `Cargo.toml` (bump versions if needed; tag prep)
- Create: `RELEASING.md` (release process doc)

- [ ] **Step 1: Author `CHANGELOG.md`** with v0.1.0 entry summarizing all 27 prior PRs.
- [ ] **Step 2: Author `RELEASING.md`** with the publish process (cargo publish dry-run, maturin publish, GitHub release).
- [ ] **Step 3: Tag v0.1.0 once merged.**

```bash
git tag -a v0.1.0 -m "v0.1.0 — initial reference implementation"
```

- [ ] **Step 4: Commit (do NOT push tag without explicit approval).**

**Acceptance:** Repo ready to publish; nothing actually published until Steven says go.

---

## Cross-cutting Notes

### Conventional Commits

All commits follow Conventional Commits:
- `feat(scope): ...` — new feature
- `fix(scope): ...` — bug fix
- `docs(scope): ...` — docs only
- `chore(scope): ...` — tooling, scaffolding
- `refactor(scope): ...` — non-behavioral change
- `test(scope): ...` — tests only

Scope = crate name without `harp-` prefix (e.g. `core`, `lint`, `cli`, `axum`) or `spec`, `schemas`, `python`, `ci`.

### Test Discipline

Every PR ships tests for new behavior. TDD per skill guidance: failing test → implementation → passing test → commit.

Rust tests use `cargo test --workspace --all-features -- --nocapture --test-threads=1` per opsml/scouter convention.

Python tests use top-level `def test_*` (no class-based test classes) per Steven's CLAUDE.md.

### Verification Sequence (run before declaring any PR done)

```bash
# Rust
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features -- --nocapture --test-threads=1

# Schemas + spec
./scripts/validate-examples.sh
./scripts/regen-spec-index.sh && git diff --exit-code spec/index.json

# Python (if changed)
cd py-harp && make setup.project && make lints && uv run pytest

# Conformance (if PR touched ref-impls or middleware)
./tests/e2e/smoke.sh
```

### Skills as Code Reviewers

Once `harness-api-review` skill (PR 24) lands, every subsequent PR review can invoke it via `Skill: harness-api-review` to audit the diff against tier requirements before merge. This is recursive eating of own dog food.

---

## Done When

- All 29 PRs merged to `main`
- Every CI workflow green (rust, python, schemas, conformance)
- Both ref-impls attain L3 on a clean clone
- `~/.claude/skills/harness-*` invoked successfully from a Claude Code conversation against a third-party project
- v0.1.0 tag pushed
- `crates.io` publication in leaf-first dependency order: `harp-core` → `harp-fixtures` → `harp-openapi` → `harp-lint` → `harp-codegen` → `harp-migrate` → `harp-conformance` → `harp-axum` → `harp` (binary)
- PyPI publication of `harp` Python package
- README updated with install + quickstart + tier badge for self
