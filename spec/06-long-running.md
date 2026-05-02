---
id: harp-long-running
status: draft
normative: true
tier: L3
version: 0.1
depends_on: [harp-envelope]
---

# HARP — Long-Running Jobs

## Why this exists

Some operations cannot complete within an HTTP request timeout. Model profiling, batch drift computation, dataset ingestion, and large-scale evaluation jobs all run in seconds to minutes. A service that handles these synchronously either forces clients to use long timeouts (fragile under load balancers and proxies that impose their own limits) or returns an incomplete result.

Without a standardized async job pattern, every service invents its own: some return `202` with a `Location` header, some return `200` with a `status: pending` field, some use webhooks with no signature, some use polling with no `Retry-After`. An agent integrating three services faces three different async protocols. The combinatorial harness complexity is the problem HARP solves.

The webhook callback addresses a secondary problem: polling is expensive for long jobs and wastes agent compute. An agent that polls every 5 seconds for a 10-minute job makes 120 calls and burns context. A webhook delivers the result exactly once, signed for authenticity, with retry on delivery failure.

## Mental model

The job pattern is the same pattern used by Kubernetes Jobs, AWS Batch, and most cloud provider async APIs: submit returns immediately with a job ID, poll the job ID for status, fetch the result when the job reaches a terminal state. The terminal states follow the same vocabulary as cloud job systems (`pending`, `running`, `succeeded`, `failed`, `cancelled`).

HARP's addition to this pattern: the 202 response MUST include `_actions[]` pointing to the status, cancel, and result endpoints so the agent does not need to construct URLs. The job response is self-describing — no prior knowledge of the job polling URL pattern is required.

The webhook signing pattern is identical to GitHub webhook signatures: the delivery payload is HMAC-SHA256 signed with a client-supplied secret, and the signature is in a well-known header. This is a widely understood pattern with good library support.

## Specification

### 12. Long-Running Jobs (L3)

#### 12.1 Submit

Op with `x-harness.long_running: true` returns 202:

```json
{
  "data": {
    "job_id": "job_01HV7P...",
    "status": "pending",
    "submitted_at": "...",
    "estimated_completion_at": "..."
  },
  "_meta": { },
  "_actions": [
    { "rel": "status", "method": "GET", "href": "/jobs/job_01HV7P..." },
    { "rel": "cancel", "method": "DELETE", "href": "/jobs/job_01HV7P...", "semantics": "destructive" },
    { "rel": "result", "method": "GET", "href": "/jobs/job_01HV7P.../result", "available_when": "succeeded" }
  ]
}
```

#### 12.2 Poll

`GET /jobs/{job_id}`:

```json
{
  "data": {
    "job_id": "...",
    "status": "pending | running | succeeded | failed | cancelled",
    "progress": { "pct": 42, "message": "binning features" },
    "submitted_at": "...",
    "started_at": "...",
    "completed_at": "...",
    "result_url": "/jobs/.../result",
    "error": { }
  }
}
```

`status` values:
- `pending` — queued, not yet started
- `running` — in progress
- `succeeded` — terminal; result available
- `failed` — terminal; `error` populated
- `cancelled` — terminal; cancelled by client or system

`result_url` is null until status is `succeeded`.
`error` is populated on `failed`.

Server SHOULD return `Retry-After` header on non-terminal responses.

#### 12.3 Result

`GET /jobs/{job_id}/result` returns the final envelope as if the op had been synchronous.

TTL on result default: 24h. After expiry: 410 Gone.

#### 12.4 Cancel

`DELETE /jobs/{job_id}` is idempotent; returns final state.

#### 12.5 List

`GET /jobs?requestor=<r>&status=<s>` returns ordered jobs visible to caller.

#### 12.6 Optional Webhook Callback

Submission accepts `?callback_url=https://...&callback_secret=...`. Server POSTs the final envelope to the callback. Body is HMAC-SHA256 signed with `callback_secret` (header `HARP-Signature: <hmac>`). Server retries with exponential backoff on non-2xx delivery for up to 24h, then drops with audit row.

`callback_secret` lifecycle:

- Stored encrypted at rest, scoped to the job row only.
- Discarded when the job reaches a terminal state AND callback delivery succeeds OR retry budget is exhausted.
- Never echoed back to clients (job poll responses MUST omit the secret; presence is signaled via `_meta.callback_configured: true`).

## Per-field rationale

### `data.job_id`

A stable identifier for this async job.

If absent, the caller has no handle for polling, cancellation, or audit. The job ID MUST be stable for the lifetime of the job plus the result TTL (24h). The format is opaque to the caller; the server MUST ensure uniqueness.

### `data.estimated_completion_at`

A server estimate of when the job will reach a terminal state.

If absent, agents polling for completion have no signal on how frequently to poll. With `estimated_completion_at`, an agent can sleep until near the estimated time and then switch to active polling — reducing wasted calls by an order of magnitude. SHOULD be populated when the server has a basis for estimation; MAY be null when the estimate is not computable.

### `_actions[].available_when`

Declares the job status at which this action becomes available.

If absent on the `result` action, agents may attempt to fetch the result before the job completes and receive an unexpected 404 or 202. With `available_when: "succeeded"`, the agent knows not to follow the `result` link until the status field reaches `succeeded`. Only needed on conditionally-available actions.

### `data.progress`

Structured progress report with `pct` (0–100) and `message` string.

If absent, agents and users polling a long-running job see a binary `running` status with no visibility into how far along the job is. A 10-minute job at 99% is qualitatively different from a 10-minute job at 1%. SHOULD be populated for jobs where the server can compute progress; MAY be null for jobs with binary (not started / done) execution models.

### `data.result_url`

The URL to fetch the final result from.

If absent, agents know the job succeeded but must construct the result URL from convention. `result_url` makes the URL self-describing — no convention required. MUST be null until status is `succeeded`.

### `data.error`

The error envelope for a failed job, inlined into the job status response.

If absent on `status: "failed"`, agents must fetch the result endpoint (which will return an error response) to discover the failure reason — an extra round trip. With `error` inlined in the status response, the agent knows why the job failed at the first poll that shows `failed`. MUST be populated when status is `failed`.

### `_meta.callback_configured`

Signals that a webhook callback is registered for this job.

If absent, a caller who registered a callback cannot verify that the callback was captured — they might assume it wasn't and set up polling instead, leading to duplicate delivery handling. `callback_configured: true` confirms the callback is registered. The actual `callback_secret` MUST NOT appear in any response.

### `HARP-Signature` (webhook delivery header)

HMAC-SHA256 signature of the callback body.

If absent, the callback receiver cannot verify the delivery is from the expected server. Any caller with the callback URL can forge a delivery. With HMAC signing using the `callback_secret`, the receiver validates `HMAC-SHA256(secret, body) == signature` before processing. MUST be present on all webhook deliveries.

## Examples

**Good: submit a long-running profiling job and poll to completion.**

Submit:
```http
POST /profile/jobs
Authorization: Bearer $TOKEN
Content-Type: application/json

{ "dataset_uid": "ds_abc123", "profile_type": "psi" }
```

Response (202):
```json
{
  "data": { "job_id": "job_01HV7P", "status": "pending", "submitted_at": "2026-05-02T19:00:00Z", "estimated_completion_at": "2026-05-02T19:05:00Z" },
  "_actions": [
    { "rel": "status", "method": "GET", "href": "/jobs/job_01HV7P" },
    { "rel": "cancel", "method": "DELETE", "href": "/jobs/job_01HV7P", "semantics": "destructive" },
    { "rel": "result", "method": "GET", "href": "/jobs/job_01HV7P/result", "available_when": "succeeded" }
  ]
}
```

Poll (after estimated completion time):
```http
GET /jobs/job_01HV7P
```

Response: `status: "succeeded"`, `result_url: "/jobs/job_01HV7P/result"`.

Fetch result:
```http
GET /jobs/job_01HV7P/result
```

Response: standard success envelope with the completed profile in `data`.

**Bad: operation returns 202 without `_actions`, no standard job endpoint.**

```json
{ "job_id": "abc123", "status": "running" }
```

Agent must hardcode `/jobs/{job_id}` URL pattern — not present in the response. If the service uses `/tasks/` instead, the agent fails. `result_url` is absent, so agent doesn't know where to fetch the result. No `Retry-After` header, so agent polls every second and burns quota.

**Fix:** Return the full HARP 202 envelope with `_actions[]`, `estimated_completion_at`, and set `Retry-After` on every non-terminal poll response.

## Cross-references

- [Envelope](./01-envelope.md) — the long-running submit response uses the standard success envelope with `_actions[]`
- [OpenAPI Extensions](./03-openapi-extensions.md) — `x-harness.long_running: true` declares that an op returns 202
- [Capability Negotiation](./08-capability-negotiation.md) — `HARP-Signature` appears in the header reference; `Retry-After` header guidance
- [Audit](./10-audit.md) — failed callback deliveries produce an audit row
- [Conformance](./13-conformance.md) — long-running poll-to-completion is a mandatory L3 conformance test

## Limitations and v0.1 caveats

The webhook retry policy (exponential backoff, 24h budget) is specified at the behavior level but the exact backoff parameters (initial interval, multiplier, jitter, max interval) are left to the implementation. v0.1 does not define priority queuing between jobs from different callers. The `progress.pct` field has no required update frequency — a server that emits `pct: 0` for 9 minutes and `pct: 100` at completion satisfies the spec. Real-time progress streaming over Server-Sent Events or WebSocket is deferred to v0.2. Webhook delivery to non-HTTPS URLs is a security risk; the spec does not mandate HTTPS but implementations SHOULD reject `http://` callback URLs.
