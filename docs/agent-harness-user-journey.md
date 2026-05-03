---
id: harp-agent-harness-user-journey
status: draft
version: 0.1
date: 2026-05-03
audience:
  - agent-users
  - agent-tooling-authors
  - protocol-implementers
---

# HARP Agent Harness User Journey

This guide covers the client-side half of HARP: how a human configures an agent, how that agent adds a HARP service to a local harness, and how future requests are executed without asking the model to guess routes or safety policy.

The service-side protocol makes APIs harnessable. The client-side harness makes those APIs usable.

## Mental Model

There are three layers:

1. **HARP service** — an HTTP/OpenAPI service that serves `/.well-known/harness`, OpenAPI, error envelopes, `x-harness` metadata, and higher-tier safety affordances.
2. **Local HARP harness** — a CLI-managed registry and execution layer on the user's machine. It owns discovery, OpenAPI indexing, auth references, safety policy, and calls.
3. **Agent adapter** — a Claude Code skill, Codex skill, or another agent-specific adapter that teaches the agent to use the local harness.

The model should stay vendor-neutral. Claude Code is the first adapter, not the architecture.

HARP does not need an MCP or agent-to-agent bridge to make services usable. The service contract is HTTP/OpenAPI plus HARP metadata; the local harness is the client-side policy layer that agents call.

## User Journey

### 1. Install agent support

The user installs the HARP CLI, then installs an adapter for their agent:

```bash
harp agent install claude-code --scope user
```

This writes a Claude Code skill such as `harness-consumer/SKILL.md`. The skill tells Claude when to use HARP and which `harp harness` commands to run. It does not store secrets.

Project-local install is also supported:

```bash
harp agent install claude-code --scope project
```

Project scope writes repo-local agent config and is useful when a team wants everyone working in the repo to use the same HARP harness behavior.

### 2. Add a service

The user can ask the agent:

> Claude, add https://api.service-a.com to my harness as service-a.

Claude should run:

```bash
harp harness add service-a https://api.service-a.com --auth-env SERVICE_A_TOKEN
```

The harness does the protocol work:

1. Fetches `https://api.service-a.com/.well-known/harness`.
2. Validates `harness_version`, `service.max_tier`, `links.openapi`, `links.errors`, `auth.modes`, and `trace.header`.
3. Fetches OpenAPI from `links.openapi`.
4. Indexes `operationId` to method, path template, parameters, request body schema, response schemas, and `x-harness`.
5. Stores metadata in the local registry.
6. Stores only an auth reference such as `env:SERVICE_A_TOKEN`, never the token value.

The user sets the token outside HARP:

```bash
export SERVICE_A_TOKEN=...
```

### 3. Use a registered service

The user can ask:

> Claude, get entity a from service-a.

Claude should not invent a URL or call `curl` directly. It should use the harness:

```bash
harp harness plan service-a "get entity a" --format json
harp harness call service-a get_entity --params '{"entity_id":"a"}' --format json
```

`harp harness plan` maps natural-language intent to candidate operations. The agent can ask the user to choose if there are multiple safe candidates.

`harp harness call` executes the selected operation by `operation_id`. The route comes from the cached OpenAPI index, not from the model.

### 4. Handle writes

For writes, Claude still goes through the harness:

```bash
harp harness call service-a update_entity \
  --params '{"entity_id":"a"}' \
  --body @update.json \
  --format json
```

The harness enforces the HARP contract:

- Adds an `Idempotency-Key` when the operation advertises idempotency.
- Requires or obtains an ETag when the operation is guarded by optimistic concurrency.
- Validates the request body against OpenAPI before sending.
- Validates the response envelope after receiving it.
- Surfaces `trace_id`, HARP error codes, retry hints, and suggested actions to the agent.

### 5. Handle destructive work

For destructive operations, the harness must prevent direct execution by default:

```bash
harp harness call service-a delete_entity \
  --params '{"entity_id":"a"}' \
  --preview
```

The harness returns the preview effects:

```json
{
  "operation_id": "delete_entity",
  "requires_commit": true,
  "effects": [
    {
      "kind": "delete",
      "resource": "entities/a",
      "summary": "would delete entity a and 3 dependent aliases"
    }
  ],
  "confirmation_token": "ct_..."
}
```

Claude shows the effects to the user. If the user confirms, Claude runs:

```bash
harp harness commit service-a ct_...
```

If the service does not support the HARP safety contract required for the action, the harness refuses the call unless the user explicitly overrides policy.

## Local Registry

The harness uses two registry locations:

| Location | Scope | Commit? |
|---|---|---|
| `~/.harp/harness.yaml` | User-global | No |
| `.harp/harness.yaml` | Project-local | Yes, if it contains no secrets |

Project-local entries override user-global entries with the same service name.

Example registry entry:

```yaml
services:
  service-a:
    base_url: https://api.service-a.com
    harness_version: "0.1"
    service_version: "1.4.2"
    max_tier: L2
    effective_tier: L2
    discovery_url: https://api.service-a.com/.well-known/harness
    openapi_url: https://api.service-a.com/openapi.json
    auth_ref: env:SERVICE_A_TOKEN
    cache:
      refreshed_at: "2026-05-03T12:00:00Z"
      operation_count: 42
```

Raw tokens are invalid in registry files. The harness should reject config that appears to contain bearer tokens, API keys, or other secret material.

## Expected Agent Behavior

Agents should follow these rules when a service is registered in the HARP harness:

- Use `harp harness inspect <service>` before making assumptions about tier or capabilities.
- Use `harp harness plan` for natural-language requests that do not name an exact operation.
- Use `harp harness call` or `harp harness recipe run` for execution.
- Do not call raw HTTP against registered service base URLs.
- Do not derive routes from memory or from prose docs.
- Do not store tokens in prompts, skills, project config, or registry files.
- Treat destructive actions as preview-first unless the harness refuses because the service is not safe enough.

The skill is guidance. The harness CLI is the policy engine. Agent hooks can provide harder enforcement by blocking raw HTTP calls to registered service URLs.

## Expected CLI Surface

```bash
harp harness init --scope user|project
harp harness add <name> <base-url> --auth-env <ENV_VAR>
harp harness refresh <name>
harp harness list
harp harness inspect <name> --format json|human
harp harness ops <name> --filter read|write|destructive
harp harness recipes <name>
harp harness plan <name> "<intent>" --format json
harp harness call <name> <operation_id> --params <json> --body @file --format json
harp harness recipe run <name> <recipe_id> --input @file
harp harness commit <name> <confirmation_token>
```

`harp harness` should return structured JSON by default when invoked by an agent adapter and human-readable output by default when invoked directly in a terminal.

## Failure Modes

### Missing auth

If `SERVICE_A_TOKEN` is not set, the harness returns an actionable error:

```json
{
  "error": {
    "code": "HARP_HARNESS_AUTH_REF_UNRESOLVED",
    "message": "SERVICE_A_TOKEN is not set.",
    "hint": "Set SERVICE_A_TOKEN and retry."
  }
}
```

Claude should relay the fix. It should not ask the user to paste the token into chat.

### Ambiguous intent

If `harp harness plan` finds multiple candidate operations, it returns them with safety classifications. Claude should ask the user to choose unless one candidate is clearly read-only and matches the request.

### Non-HARP service

If `/.well-known/harness` is missing or invalid, `harp harness add` fails. The agent should tell the user the service is not HARP-harnessable yet and suggest `harp migrate` or the HARP service-side adoption docs.

### Unsafe destructive request

If the user asks for destructive work and the service lacks the required L3 safety affordance, the harness refuses by default. The refusal is a feature. Agents should not work around it with raw HTTP.

## Documentation Expectations

The public docs should include:

- `docs/concepts/agent-harness.md` — the three-layer model.
- `docs/guides/claude-code-harp.md` — install the Claude Code adapter and use a service.
- `docs/guides/add-harp-service.md` — add, inspect, refresh, and remove services.
- README section: "Using HARP from an agent" with a short preview and link to this document.

Each guide should include transcript-style examples:

1. User prompt.
2. Agent action.
3. `harp harness` command.
4. Expected result.

## Open Questions

- Should `harp harness plan` be deterministic string matching against OpenAPI summaries first, or should it optionally call an LLM later?
- Should raw HTTP blocking hooks be installed by default or offered as an opt-in hardening step?
- Should project-local registries be committed by default, or should `harp harness init --scope project` create `.harp/harness.local.yaml` for private service catalogs?
