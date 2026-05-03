---
id: harp-local-dogfooding
status: draft
version: 0.1
date: 2026-05-03
audience:
  - protocol-implementers
  - local-agent-users
---

# Local Dogfooding

HARP should be usable before it is complete. Unit tests prove the crates behave; local dogfooding proves the product shape feels right when a human and an agent try to use it.

The first dogfood loop is intentionally small: one static HARP service, one read operation, one local harness registry, and the same command path for Claude Code and Codex.

## What lands first

The early loop lands after the L1 static tooling path:

1. `harp-core`, `harp-openapi`, and L1 `harp-lint`.
2. `harp` CLI skeleton and `harp lint`.
3. Tiny static HARP service.
4. Read-only `harp harness` path.
5. Claude Code and Codex `harness-consumer` skills.

Full conformance, middleware-backed reference servers, writes, destructive preview/commit, recipes, and Python support still land later.

## CLI loop

Start the tiny service:

```bash
cargo run -p harp-ref-tiny -- --port 8090
```

In another terminal, add and call it through the harness:

```bash
harp harness init --scope project
harp harness add tiny http://127.0.0.1:8090 --no-auth
harp harness inspect tiny --format json
harp harness ops tiny --format json
harp harness call tiny get_entity --params '{"entity_id":"a"}' --format json
```

Expected result:

```json
{
  "data": {
    "id": "a",
    "name": "Entity A",
    "status": "active"
  }
}
```

The exact metadata may change as envelopes settle, but the important behavior should not: the caller passes `get_entity`, not a method or path. The harness resolves the route from OpenAPI.

## One-command smoke

After the D0.3 slice lands:

```bash
make dogfood.local
```

That target should:

1. Build `harp`.
2. Start `harp-ref-tiny` on a free local port.
3. Create a temporary project harness registry.
4. Add the tiny service.
5. Call `get_entity` by `operation_id`.
6. Fail if the returned entity is not `a`.

This is not a replacement for unit tests or conformance. It is the "can I feel the product locally?" check.

## Claude Code loop

Install the project-local skill:

```bash
harp agent install claude-code --scope project
```

Then ask Claude:

```text
Claude, add the local tiny HARP service to my harness and get entity a.
```

Expected agent behavior:

```bash
harp harness add tiny http://127.0.0.1:8090 --no-auth
harp harness inspect tiny --format json
harp harness ops tiny --format json
harp harness call tiny get_entity --params '{"entity_id":"a"}' --format json
```

Claude should not call `curl` against the service once it is registered. The point of the skill is to route service use through `harp harness`.

## Codex loop

Install the project-local skill:

```bash
harp agent install codex --scope project
```

Then ask Codex:

```text
Codex, use HARP to inspect the local tiny service and call get_entity for entity a.
```

Expected agent behavior is the same as Claude Code: inspect through the harness, list operations if needed, then call by `operation_id`.

## Early limitations

The first dogfood loop only supports:

- Project-local `.harp/harness.yaml`.
- `--no-auth`.
- Read operations.
- Direct `operation_id` calls.
- One tiny local service.

It intentionally does not support:

- User-global registry merge.
- Auth references.
- Writes or destructive operations.
- Recipes.
- Natural-language operation planning.
- Full `harp test` conformance verdicts.

Those belong in the later harness and conformance milestones. The early loop should stay small enough that it can land quickly and keep working while the rest of HARP grows around it.
