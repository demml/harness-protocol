---
id: harp-long-running
status: draft
normative: true
tier: L3
version: 0.1
depends_on: [harp-envelope]
---

# HARP — Long-Running Jobs

## 12. Long-Running Jobs (L3)

### 12.1 Submit

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

### 12.2 Poll

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

### 12.3 Result

`GET /jobs/{job_id}/result` returns the final envelope as if the op had been synchronous.

TTL on result default: 24h. After expiry: 410 Gone.

### 12.4 Cancel

`DELETE /jobs/{job_id}` is idempotent; returns final state.

### 12.5 List

`GET /jobs?requestor=<r>&status=<s>` returns ordered jobs visible to caller.

### 12.6 Optional Webhook Callback

Submission accepts `?callback_url=https://...&callback_secret=...`. Server POSTs the final envelope to the callback. Body is HMAC-SHA256 signed with `callback_secret` (header `HARP-Signature: <hmac>`). Server retries with exponential backoff on non-2xx delivery for up to 24h, then drops with audit row.

`callback_secret` lifecycle:

- Stored encrypted at rest, scoped to the job row only.
- Discarded when the job reaches a terminal state AND callback delivery succeeds OR retry budget is exhausted.
- Never echoed back to clients (job poll responses MUST omit the secret; presence is signaled via `_meta.callback_configured: true`).
