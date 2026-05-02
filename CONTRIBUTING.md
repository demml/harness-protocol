# Contributing to HARP

## Branch Model

Work off `main` using short-lived feature branches. PRs are squash-merged. Branch names should be descriptive (`feat/harp-core-schema`, `fix/lint-error-path`, etc.).

## Commit Style

[Conventional Commits](https://www.conventionalcommits.org/):

| Prefix | When to use |
|---|---|
| `feat:` | New protocol feature or crate capability |
| `fix:` | Bug fix |
| `chore:` | Maintenance, dependency bumps, tooling |
| `docs:` | Documentation only |
| `test:` | Test additions or changes |
| `refactor:` | Code restructure with no behaviour change |
| `ci:` | CI/CD pipeline changes |

## Running Lints and Tests

From repo root:

```bash
make lints      # cargo clippy --workspace --all-targets --all-features -- -D warnings
make test.unit  # cargo test --workspace --all-features -- --nocapture --test-threads=1
```

Both must pass before opening a PR.

## PR Review Expectations

- CI must be green before requesting review.
- At least one approval required before merge.
- Pre-1.0: breaking changes to the protocol or public API surface are acceptable, but must be called out explicitly in the PR description with a `BREAKING:` note.

## Code Organization

| Directory | Purpose |
|---|---|
| `crates/` | Rust workspace crates (one crate per concern) |
| `py-harp/` | Python sub-package (PyO3 bindings + pure Python API) |
| `ref-impl/` | Reference server implementations |
| `spec/` | Protocol specification documents |
