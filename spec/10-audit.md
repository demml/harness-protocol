---
id: harp-audit
status: draft
normative: true
tier: L2
version: 0.1
depends_on: [harp-envelope]
---

# HARP — Audit Trail

## Why this exists

Agents executing write and destructive operations on behalf of users need a way to answer the question "who did what, when, and why." Without an audit trail, every write is opaque: if a drift profile is deleted, there is no record of which requestor triggered the operation, which agent executed it, which trace ID is associated with the decision, or whether it was a dry-run or a real commit.

For autonomous agent systems, this is not just an operational nicety — it is a safety requirement. An agent that executes unattended must leave a recoverable trace of its actions. When an agent makes an unexpected change, the audit trail is the difference between "we can reconstruct what happened" and "we have no idea what the agent did."

The `HARP-Causality` chain serves a second purpose: multi-step agent workflows produce multiple write operations that appear disconnected in a flat log. Without causality linking, a 5-step recipe leaves 5 orphaned audit rows. With causality, the entire workflow is reconstructable from a single root trace ID.

The metadata-only default for request bodies is a deliberate privacy constraint. Full request body logging creates PII exposure risk, inflates storage, and violates the principle of minimum necessary data collection. The spec mandates logging only the metadata that enables reconstruction of intent, not the full data payload.

## Mental model

The audit trail is closest to structured event sourcing for API operations — each write produces a timestamped, immutable row declaring what happened, to which resource, by whom, and with what outcome. This is analogous to database write-ahead logs or CloudTrail, scoped to the operations defined in the HARP service.

The causality chain is the same model used in distributed tracing (W3C Trace Context, OpenTelemetry): a parent-child relationship between spans forms a tree. HARP maps this directly to API operations — each call that results from a prior call carries the prior call's `trace_id` in `HARP-Causality`, forming a causal tree of API operations rather than in-process spans.

## Specification

### 11. Audit Trail (L2+)

#### 11.1 Causality

Every request MAY carry `HARP-Causality: <parent_trace_id>` to declare the upstream operation that initiated it. Forms a causality chain.

Every response MUST carry `x-trace-id` and `_meta.trace_id` (matching the header).

#### 11.2 Mandatory Log Row

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

#### 11.3 Endpoints

| Endpoint | Returns |
|---|---|
| `GET /audit/trace/{trace_id}` | Full row + envelope |
| `GET /audit?resource=<r>&since=<t>&until=<t>` | Ordered audit rows for resource |
| `GET /audit/causality/{trace_id}` | Recursive parent walk producing the full chain |

#### 11.4 Privacy

Request bodies MUST NOT be logged by default. `_meta.audited_fields: ["model_uid", "feature_count"]` declares what server captured. Operators may opt into deeper logging via service config; spec mandates the metadata-only default.

#### 11.5 Retention

Spec mandates retention of at least 30 days. Service may extend.

## Per-field rationale

### `trace_id` (audit row)

Unique identifier for this specific operation.

If absent, the audit row cannot be retrieved by trace ID from `GET /audit/trace/{trace_id}`. Every response includes `x-trace-id` — the audit row MUST be retrievable via that value. The trace ID is the join key between the response envelope and the server-side audit record.

### `parent_trace_id`

The trace ID of the operation that caused this one.

If absent when the operation is part of a multi-step workflow, the audit trail shows disconnected rows with no causal relationship. With `parent_trace_id`, `GET /audit/causality/{trace_id}` can walk the entire causal tree from any operation in the chain to its root. NULL is correct for operations that are not part of a multi-step workflow.

### `requestor`

The identity of the authenticated caller (JWT subject or API key identifier).

If absent, there is no accountability for write operations. "Who deleted this profile?" has no answer without `requestor`. MUST be set from the authenticated credential on every write op. MUST NOT be derived from client-supplied headers (which can be spoofed).

### `agent_id`

The identity of the agent software executing the operation (from `HARP-Client`).

If absent, operations performed by different agent implementations are indistinguishable — you cannot answer "which agent version introduced this behavior?" `agent_id` is distinct from `requestor`: the requestor is the human or system account; the agent is the software acting on their behalf. NULL when `HARP-Client` header was not sent.

### `semantics`

The operation's semantic category (`read | write | destructive`).

If absent, audit queries filtering by operation type (e.g., "show me all destructive operations on this resource") cannot be satisfied without parsing `operation` string patterns. MUST match the `x-harness.semantics` declared for the operation in the OpenAPI spec.

### `outcome`

The result of the operation: `"success"` or `"error_<code>"`.

If absent, audit rows do not distinguish successful writes from failed attempts. An audit showing "100 write operations on this profile" is misleading if 80 of them failed — the resource is in a different state than the raw count implies. MUST be populated on every row, including rows for failed operations.

### `etag_before` / `etag_after`

The resource version before and after the operation.

If absent, audit rows do not capture the state transition. An audit row showing `requestor=user@example.com, operation=update_profile, outcome=success` does not tell you what changed. `etag_before=W/"v5"` and `etag_after=W/"v6"` record that a specific state transition occurred. This enables diff reconstruction (by fetching the resource at the etag values, if snapshots are retained). NULL for creates (no `etag_before`) and deletes (no `etag_after`).

### `dry_run`

Declares whether this row records a dry-run preview or a real operation.

If absent, dry-run operations appear identical to real operations in the audit trail. An audit showing "profile foo/bar/1.0 deleted" is alarming — until you discover it was a dry-run. `dry_run: true` distinguishes preview operations from real mutations. MUST be `false` for all operations that committed state; MUST be `true` for dry-run calls.

### `two_phase_token` (hash)

A hash of the confirmation token used to authorize a two-phase destructive commit.

If absent, there is no audit link between phase-1 (preview) and phase-2 (commit) for destructive operations. Storing the hash (not the raw token) allows matching the commit to the preview in audit queries without exposing the token for replay. MUST be stored as a hash. MUST NOT store the raw token.

### `_meta.audited_fields`

Declares which request body fields the server logged.

If absent, consumers of the audit trail cannot determine what data was captured. The metadata-only default means the full request body is NOT logged; `audited_fields` names what IS captured. This is the privacy manifest for the audit row.

## Examples

**Good: full audit row for a two-phase delete operation.**

```json
{
  "trace_id": "01HV7P...",
  "parent_trace_id": "01HV7A...",
  "requestor": "user@example.com",
  "agent_id": "claude-code/0.42",
  "operation": "delete_drift_profile",
  "resource": "drift/profiles/foo/bar/1.0",
  "semantics": "destructive",
  "timestamp": "2026-05-02T19:14:00Z",
  "outcome": "success",
  "etag_before": "W/\"v5\"",
  "etag_after": null,
  "dry_run": false,
  "two_phase_token": "sha256:AABBCC..."
}
```

**Bad: audit row missing outcome, requestor, and trace_id.**

```json
{
  "operation": "delete_drift_profile",
  "resource": "drift/profiles/foo/bar/1.0",
  "timestamp": "2026-05-02T19:14:00Z"
}
```

"Who deleted this?" — no answer. "Did it succeed?" — no answer. "Which trace is this from?" — no answer. This row is audit theater: it proves a log entry exists but provides no actionable information.

**Fix:** Populate every mandatory field. Extract `requestor` from the authenticated credential. Set `outcome` from the operation result. Generate `trace_id` from the request and match it to the `x-trace-id` response header.

**Good: causality chain query.**

```http
GET /audit/causality/01HV7A...
```

Returns the full causal tree:

```json
{
  "root": { "trace_id": "01HV7A...", "operation": "recipe:register_drift_workflow", "outcome": "success" },
  "children": [
    { "trace_id": "01HV7B...", "operation": "create_drift_profile", "outcome": "success" },
    { "trace_id": "01HV7C...", "operation": "create_alert_config", "outcome": "success" },
    { "trace_id": "01HV7D...", "operation": "create_cron_job", "outcome": "error_SCOUTER_CRON_CONFLICT" }
  ]
}
```

An operator can see that the recipe succeeded on the first two steps and failed on the third, without needing to know the recipe's step IDs in advance.

## Cross-references

- [Envelope](./01-envelope.md) — `x-trace-id` response header and `_meta.trace_id` are the join keys to audit rows; `_meta.audited_fields` is part of the success envelope
- [Capability Negotiation](./08-capability-negotiation.md) — `HARP-Causality` request header carries the parent trace ID; `HARP-Client` provides `agent_id`
- [Write Safety](./04-write-safety.md) — `dry_run` and `two_phase_token` fields in the audit row correspond to Write Safety contracts
- [Conformance](./13-conformance.md) — audit trail correctness is a mandatory L2 conformance test

## Limitations and v0.1 caveats

The audit endpoints (`GET /audit/trace/{trace_id}`, `GET /audit/causality/{trace_id}`) are defined normatively but their access control is left to the service. The spec does not mandate which scopes gate audit reads; services SHOULD require `audit:read` or `audit:read:own`. The causality query (`/audit/causality/{trace_id}`) performs a recursive walk; services MUST bound the depth to prevent unbounded recursion (recommended max depth: 50). Audit rows for read operations are not required by the spec — only write and destructive ops. Services that want read-op audit trails may implement them but they are outside the conformance scope.
