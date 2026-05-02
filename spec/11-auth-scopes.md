---
id: harp-auth-scopes
status: draft
normative: true
tier: L1
version: 0.1
depends_on: []
---

# HARP — Auth Scope Grammar

## 13. Auth Scope Grammar (L1+)

### 13.1 Format

```
<resource>:<action>[:<qualifier>]
```

| Component | Values |
|---|---|
| `resource` | noun (e.g. `drift`, `profile`, `alert`, `audit`, `job`, `*`) |
| `action` | `read | write | destroy | execute | admin` |
| `qualifier` | optional narrowing (`own`, `space:<name>`, `tier:public`) |

### 13.2 Discovery Sub-resource

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

### 13.3 Failure Envelope

403 + `HARP_INSUFFICIENT_SCOPE` with `_meta.required_scopes` and `_meta.granted_scopes` so an agent can reason about the gap.

### 13.4 Token Introspection

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
