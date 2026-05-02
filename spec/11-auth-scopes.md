---
id: harp-auth-scopes
status: draft
normative: true
tier: L1
version: 0.1
depends_on: []
---

# HARP — Auth Scope Grammar

## Why this exists

Without a standardized scope grammar, agents checking their own authorization must parse service-specific scope strings that vary in format across services. One service uses `read:drift`, another uses `drift.read`, another uses `drift_read`, another uses `drift:profiles:read`. An agent integrating multiple services maintains per-service scope parsers and cannot generalize "can I perform a write on this resource?" across services.

The 403 response problem is worse: without a machine-readable scope error, an agent that receives a 403 cannot determine _which_ scope is missing. "Forbidden" is the entire signal. The agent must either prompt a human, guess, or fail. With `HARP_INSUFFICIENT_SCOPE` including `_meta.required_scopes` and `_meta.granted_scopes`, the agent computes the gap directly and can request the right scope upgrade or explain the problem to the user precisely.

The optional `:qualifier` component addresses a common pattern that services implement inconsistently: "read your own resources, but not others'" or "write within a specific namespace." Without a standardized qualifier, services invent ad-hoc scope hierarchies (`read:own`, `read:public`, `read:team-<name>`) that no agent can generalize.

## Mental model

HARP's scope grammar is a strict superset of OAuth2 scope strings (RFC 6749 §3.3). OAuth2 scopes are space-separated opaque strings with no internal structure mandated. HARP mandates the structure `<resource>:<action>[:<qualifier>]` to make scopes machine-parseable and composable.

The `grants_implicit` mechanism in the discovery doc models scope hierarchy: `drift:write` implies `drift:read`. This is the same model used by AWS IAM policies (where `iam:*` implies all IAM actions) but expressed as explicit grant declarations rather than wildcard matching. Explicit grants are safer for agents: no implicit expansion surprises.

The `/.well-known/harness/whoami` endpoint mirrors the OAuth2 token introspection endpoint (RFC 7662). The difference: introspection is server-to-server; `whoami` is client-accessible and returns HARP-formatted scope data rather than the OAuth2 introspection response shape.

## Specification

### 13. Auth Scope Grammar (L1+)

#### 13.1 Format

```
<resource>:<action>[:<qualifier>]
```

| Component | Values |
|---|---|
| `resource` | noun (e.g. `drift`, `profile`, `alert`, `audit`, `job`, `*`) |
| `action` | `read | write | destroy | execute | admin` |
| `qualifier` | optional narrowing (`own`, `space:<name>`, `tier:public`) |

#### 13.2 Discovery Sub-resource

`/.well-known/harness/scopes`:

```yaml
scopes:
  - id: drift:read
    description: Read drift profiles and results
    grants_implicit: []
  - id: drift:write
    description: Create/update drift profiles
    grants_implicit: [drift:read]
  - id: drift:destroy
    description: Delete drift profiles
    grants_implicit: [drift:read, drift:write]
  - id: "*:admin"
    description: Full administrative access
    grants_implicit: ["*"]
```

Per-op required scopes are declared via `x-harness.scopes_required` (see [OpenAPI Extensions](./03-openapi-extensions.md)).

#### 13.3 Failure Envelope

403 + `HARP_INSUFFICIENT_SCOPE` with `_meta.required_scopes` and `_meta.granted_scopes` so an agent can reason about the gap.

#### 13.4 Token Introspection

`GET /.well-known/harness/whoami` returns:

```json
{
  "data": {
    "requestor": "user@example.com",
    "agent_id": "claude-code/0.42",
    "granted_scopes": ["drift:write", "audit:read:own"],
    "expires_at": "..."
  }
}
```

Agents SHOULD call this once at startup and cache.

## Per-field rationale

### Scope format `<resource>:<action>[:<qualifier>]`

A structured, machine-parseable permission identifier.

If unstructured (e.g., opaque strings like `read_drift`, `my_scopes`), agents cannot extract the resource and action components programmatically. Structured scopes enable an agent to check "do I have `write` action on the `drift` resource?" without hardcoding every possible scope string. The colon delimiter is consistent with OAuth2 ecosystem conventions (GitHub's `repo:read`, Google's `storage.objects.get` uses dots — HARP uses colons for clarity).

### `resource` component

Names the noun the scope applies to.

If absent (unstructured scope), the agent cannot determine which API resources a scope covers. `*` as a resource is the wildcard for admin scopes. MUST be a stable noun matching the service's resource taxonomy.

### `action` component

Names the permitted operation class.

The five actions (`read`, `write`, `destroy`, `execute`, `admin`) cover the full operation semantic vocabulary. `destroy` is a separate action from `write` because many services want to grant write-but-not-delete; merging them into a single `write` action would make this common pattern inexpressible.

### `qualifier` component

Narrows the scope to a subset of the resource.

If absent, the scope applies to all instances of the resource. `drift:read:own` applies to profiles owned by the requestor; `drift:read` applies to all profiles. The qualifier is the mechanism for multi-tenant access control without service-specific scope string conventions. MAY be omitted when the scope applies globally.

### `grants_implicit`

Lists scopes that are implied by holding this scope.

If absent, agents cannot compute their effective permission set from their granted scopes. An agent with `drift:write` but no `grants_implicit` declaration cannot know it also has `drift:read`. With `grants_implicit: [drift:read]`, the agent's effective scope set is the union of its granted scopes and all transitively implied scopes. MUST be accurate — incorrect implicit grants create privilege escalation vulnerabilities.

### `_meta.required_scopes` (in 403 response)

Lists the scopes needed to perform the operation.

If absent from a 403 response, the agent receives "forbidden" with no signal on what scope to request. With `required_scopes: ["drift:write"]`, the agent can either request a token with the right scope, explain the gap to the user, or fail with a specific error message. MUST be present on every `HARP_INSUFFICIENT_SCOPE` response.

### `_meta.granted_scopes` (in 403 response)

Lists the scopes the current token actually holds.

If absent, the agent must call `/.well-known/harness/whoami` to discover its current scope set before computing the gap. With `granted_scopes` in the error body, the agent has all the information it needs in one response: what was required, what was granted, what is missing. MUST be present on every `HARP_INSUFFICIENT_SCOPE` response.

### `whoami.expires_at`

Declares when the current token expires.

If absent, agents caching the `whoami` response have no signal for when to invalidate the cache. A token that expires in 30 seconds produces a `HARP_INSUFFICIENT_SCOPE` on the next call despite the cached `granted_scopes` showing the right permissions. MUST be present when the token has a finite lifetime.

## Examples

**Good: 403 error with full scope gap information.**

```json
{
  "error": {
    "code": "HARP_INSUFFICIENT_SCOPE",
    "message": "Operation requires drift:write; token grants drift:read only.",
    "hint": "Request a token with drift:write scope and retry.",
    "retry": { "retryable": false }
  },
  "_meta": {
    "required_scopes": ["drift:write"],
    "granted_scopes": ["drift:read", "audit:read:own"],
    "tier": "L1",
    "trace_id": "01HV7P..."
  }
}
```

Agent reads this, computes: required = `drift:write`, granted = `drift:read`. The gap is `write`. Agent requests a token upgrade and retries. No human intervention required.

**Bad: 403 with no scope information.**

```json
{
  "error": {
    "message": "Forbidden"
  }
}
```

Agent has no signal on which scope is missing, what it currently has, or whether retrying with a different token would help. It cannot automatically recover.

**Fix:** Emit `HARP_INSUFFICIENT_SCOPE` with `required_scopes` and `granted_scopes` in `_meta`.

**Good: `whoami` call at agent startup.**

```http
GET /.well-known/harness/whoami
Authorization: Bearer $TOKEN
```

Response:
```json
{
  "data": {
    "requestor": "svc-account@myorg.com",
    "agent_id": "claude-code/0.42",
    "granted_scopes": ["drift:write", "drift:read", "alert:read"],
    "expires_at": "2026-05-02T21:00:00Z"
  }
}
```

Agent caches this. Before calling `POST /drift/profiles` (which requires `drift:write`), it checks `granted_scopes` and confirms it has `drift:write`. Call succeeds. No speculative 403.

**Bad: agent calls operations without checking scopes, discovers missing scope on first 403.**

Agent has `drift:read` scope and calls `POST /drift/profiles`. Gets 403. Now must inspect the error, discover the missing scope, request a new token, and retry — burning two API calls and delaying the workflow.

## Cross-references

- [OpenAPI Extensions](./03-openapi-extensions.md) — `x-harness.scopes_required` declares per-operation required scopes using this grammar
- [Discovery](./02-discovery.md) — `/.well-known/harness/scopes` and `auth.default_scope` are part of the discovery doc; `links.scopes` points to the scopes sub-resource
- [Envelope](./01-envelope.md) — `HARP_INSUFFICIENT_SCOPE` uses the standard error envelope; `_meta.required_scopes` and `_meta.granted_scopes` are envelope extensions
- [Conformance](./13-conformance.md) — scope enforcement is tested implicitly via `possible_errors: [HARP_AUTH_FORBIDDEN]` vector replay

## Limitations and v0.1 caveats

The qualifier component is defined normatively but only three qualifier values are shown in examples (`own`, `space:<name>`, `tier:public`). Services may define additional qualifiers; there is no registry of valid qualifiers in v0.1. The `grants_implicit` mechanism is declared in the discovery sub-resource but the spec does not define how the auth server (which issues tokens) should reflect these implicit grants — the grants are informational for agents computing effective scope sets, not binding on the token issuer. Token refresh (requesting an upgraded scope) is outside HARP scope — the spec declares the gap but defers the resolution to the service's authentication flow.
