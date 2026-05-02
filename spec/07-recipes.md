---
id: harp-recipes
status: draft
normative: true
tier: L3
version: 0.1
depends_on: [harp-envelope, harp-discovery]
---

# HARP — Recipes Catalog

## 14. Recipes Catalog (L3)

`/.well-known/harness/recipes` lists machine-executable workflow DAGs. Server does not orchestrate; agents fetch and execute.

```yaml
recipes:
  - id: register_drift_workflow
    title: Register a PSI drift profile end-to-end
    description: Create profile, attach alert config, schedule cron job.
    when_to_use: |
      Agent wants to set up monitoring for a new model. Use this instead of
      calling endpoints individually.
    inputs:
      - name: model_uid
        schema: { type: string, format: uuid }
      - name: feature_names
        schema: { type: array, items: { type: string } }
    outputs:
      - name: profile_uid
      - name: cron_job_id
    steps:
      - id: create
        operation: POST /drift/profiles
        body_template: |
          { "model_uid": "${inputs.model_uid}", "features": ${inputs.feature_names} }
        capture: { profile_uid: "$.data.uid" }
      - id: alert
        operation: POST /alerts/configs
        depends_on: [create]
        body_template: |
          { "profile_uid": "${steps.create.profile_uid}", "channel": "slack" }
      - id: schedule
        operation: POST /scheduler/cron
        depends_on: [create]
        body_template: |
          { "profile_uid": "${steps.create.profile_uid}", "cron": "0 * * * *" }
        capture: { cron_job_id: "$.data.id" }
    failure_modes:
      - step: create
        error: SCOUTER_DUPLICATE_PROFILE
        recovery: "Use existing profile_uid from error._meta.existing_uid; skip to alert step"
    examples_ref: /openapi/examples/recipes/register_drift_workflow
    tier: L2
```

Notes:

- `body_template` uses simple `${...}` interpolation with namespaces `inputs.<name>` and `steps.<id>.<captured>`. JSONata explicitly NOT used in v1 to keep agent execution trivial.
- `capture` extracts via JSONPath into named vars for downstream steps.
- `depends_on` declares the DAG.
- `failure_modes` enumerates known recovery hints per step + error code.
- `tier` is the minimum service tier required to execute the recipe.

### Interpolation Grammar

`${...}` interpolation is limited to `${var}` substitution into JSON literals only. No math, no functions. Supported namespaces:

- `inputs.<name>` — values supplied by caller at recipe invocation
- `steps.<id>.<captured>` — values captured from a prior step via `capture`

Escaping: to emit a literal `${`, use `$${`. No other escaping is defined.

Type coercion: the interpolated value is inserted verbatim into the `body_template` string. Callers are responsible for supplying values of the correct JSON type for the target field.
