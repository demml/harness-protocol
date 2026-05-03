# HARP — Harness Agent-Ready Protocol

HARP is a vendor-neutral protocol layered on HTTP/OpenAPI that makes services equally usable by humans and AI coding agents. It defines a three-tier compliance ramp — L1 Baseline (minimal discovery, stable error envelopes, traceability), L2 Agent-ready (structured success envelopes, actions, idempotency, ETags, audit), and L3 Autonomous-ready (dry-run, two-phase destructive commits, recipes, capability negotiation, long-running jobs) — so teams can adopt incrementally without rewriting existing APIs.

## Status

Pre-1.0 / experimental. Protocol version 0.1.

## Spec

The draft spec lives under `spec/`.

## Using HARP From an Agent

HARP is meant to be consumed through a local harness, not by asking an agent to guess HTTP routes from prose. The planned flow is:

```bash
harp agent install claude-code --scope user
harp harness add service-a https://api.service-a.com --auth-env SERVICE_A_TOKEN
harp harness plan service-a "get entity a" --format json
harp harness call service-a get_entity --params '{"entity_id":"a"}' --format json
```

Claude Code and Codex are the first planned local adapters. The vendor-neutral piece is `harp harness`: a local registry and execution layer that owns discovery, OpenAPI operation resolution, auth references, safety policy, and HARP response handling.

See [docs/agent-harness-user-journey.md](docs/agent-harness-user-journey.md) for the draft client-side and agent-side user journey.

## Local Dogfooding

The implementation roadmap includes an early local dogfood slice before the full conformance runner and reference middleware are complete. The first loop is a tiny static HARP service plus a read-only `harp harness` path that Claude Code and Codex can both use.

See [docs/local-dogfooding.md](docs/local-dogfooding.md) for the planned local workflow and expected commands.

## Quickstart

Coming with v0.1.0.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
