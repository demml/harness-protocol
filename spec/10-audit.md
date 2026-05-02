---
id: harp-audit
status: draft
normative: true
tier: L2
version: 0.1
depends_on: [harp-envelope]
---

# HARP — Audit Trail

## 11. Audit Trail (L2+)

### 11.1 Causality

Every request MAY carry `HARP-Causality: <parent_trace_id>` to declare the upstream operation that initiated it. Forms a causality chain.

Every response MUST carry `x-trace-id` and `_meta.trace_id` (matching the header).

### 11.2 Mandatory Log Row

Per write/destructive op, server MUST persist:

```json
{
  "trace_id": "...",
  "parent_trace_id": "...",
  "requestor": "...",
  "agent_id": "...",
  "operation": "...",
  "resource": "...",
  "semantics": "...",
  "timestamp": "...",
  "outcome": "success | error_<code>",
  "etag_before": "...",
  "etag_after": "...",
  "dry_run": false,
  "two_phase_token": "<hash>"
}
```

Fields:

- `requestor` — subject from JWT/API key
- `agent_id` — from `HARP-Client` header (may differ from requestor)
- `operation` — operationId
- `outcome` — `"success"` or `"error_<code>"`
- `two_phase_token` — never raw token; store hash only

### 11.3 Endpoints

| Endpoint | Returns |
|---|---|
| `GET /audit/trace/{trace_id}` | Full row + envelope |
| `GET /audit?resource=<r>&since=<t>&until=<t>` | Ordered audit rows for resource |
| `GET /audit/causality/{trace_id}` | Recursive parent walk producing the full chain |

### 11.4 Privacy

Request bodies MUST NOT be logged by default. `_meta.audited_fields: ["model_uid", "feature_count"]` declares what server captured. Operators may opt into deeper logging via service config; spec mandates the metadata-only default.

### 11.5 Retention

Spec mandates retention of at least 30 days. Service may extend.
