---
id: harp-recipes
status: draft
normative: true
tier: L3
version: 0.1
depends_on: [harp-envelope, harp-discovery]
---

# HARP — Recipes Catalog

## Why this exists

Multi-step API workflows have two possible homes: the server can orchestrate them (a workflow engine, a saga, a stored procedure), or the client can execute them against a published definition. Server-side orchestration is opaque — the client submits a job and waits, with no visibility into the individual steps, no ability to inspect intermediate state, and no ability to recover from partial failure without service-specific error codes.

Without recipes, an agent that wants to set up monitoring for a new model must independently discover the sequence: register the profile, attach an alert config, schedule the cron job. The sequence is implicit in the documentation. If the agent omits the alert step or gets the order wrong, it produces a partially-configured system with no error — the individual API calls all succeed. The failure is silent and operational.

Recipes make the workflow explicit and machine-executable: the DAG of steps, the input/output bindings, the known failure modes and their recovery hints. An agent reading a recipe executes it the same way every time, knows which step failed when something goes wrong, and has recovery guidance for known error codes without parsing prose.

The deliberate choice to make recipes client-executed (not server-orchestrated) keeps the server stateless. The agent is the orchestrator. The server provides the building blocks and the declared workflow — but does not maintain saga state, distributed transactions, or compensation logic. This trades expressiveness for simplicity: the server has fewer failure modes to manage, and the agent has full visibility into execution.

## Mental model

Recipes are analogous to GitHub Actions workflow definitions: a YAML (or JSON) DAG of steps with inputs, outputs, dependency declarations, and failure handling — but the runner is the agent (or any client), not GitHub's infrastructure. The server publishes the workflow definition; the client executes it.

The closest web API prior art is Stripe's PaymentIntents lifecycle: a multi-phase object where the client drives transitions (create → confirm → capture) guided by the server's state machine. Recipes generalize this to arbitrary multi-step workflows without requiring a server-side state object per workflow execution.

The interpolation grammar (`${inputs.name}`, `${steps.id.captured}`) is intentionally minimal — no JSONata, no Jinja, no Turing-complete template engine. Any client can implement it in under 100 lines. The constraint is a feature: recipes that require complex interpolation are a signal the workflow belongs in application code, not in a declarative recipe.

## Specification

### 14. Recipes Catalog (L3)

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

## Per-field rationale

### `id`

Stable identifier for the recipe, referenced by `x-harness.related_recipes` on individual operations.

If absent, there is no way to reference the recipe from an OpenAPI operation or from another recipe step. MUST be unique within the service's recipe catalog. MUST be stable across service versions; a renamed recipe requires a deprecation cycle matching operation deprecation.

### `when_to_use`

A machine-readable (but human-authored) description of when this recipe applies.

If absent, agents scanning the recipe catalog for a workflow that matches their goal have no signal beyond `description`. `when_to_use` is authored as a condition: "Use this when you want to X" — an agent matching its intent to available recipes can evaluate this field literally. SHOULD be one to three sentences. MUST NOT be marketing copy.

### `inputs`

Typed declaration of the parameters the caller must supply.

If absent, agents invoking the recipe have no schema to validate their inputs against before execution. A type mismatch discovered at step 3 of a 5-step recipe wastes two API calls and leaves the system in a partial state. `inputs[].schema` is a JSON Schema fragment; callers validate their values before submitting. MUST be present for every parameter the recipe uses.

### `outputs`

Named values the recipe produces, captured from terminal steps.

If absent, a caller that executes a recipe has no machine-readable signal for what the recipe produced. The caller must parse the last step's response independently. With `outputs`, the executor extracts the named values and returns them in a structured form. MUST include every value a downstream workflow would need from this recipe.

### `steps[].operation`

The HTTP operation to execute for this step, in `METHOD /path` format.

If absent, the agent cannot execute the step. MUST reference an operation in the service's OpenAPI spec. The `harp lint` tool validates that every `operation` value resolves to a real operation ID.

### `steps[].body_template`

A JSON template with `${...}` interpolation for the request body.

If absent, the step has no request body definition — acceptable for GET and DELETE steps, but required for POST and PUT steps. If present, MUST be valid JSON after interpolation with any valid input values. The `harp lint` tool parses `body_template` for syntactic validity.

### `steps[].capture`

A map of variable names to JSONPath expressions extracting values from the step response.

If absent on a step whose output is consumed by a downstream step, the downstream step has no values to interpolate. MUST be present on any step that produces values referenced by `steps.<id>.<captured>` in a downstream `body_template`.

### `steps[].depends_on`

Declares which prior steps this step requires to complete before it can execute.

If absent, the executor has no dependency graph — it cannot determine which steps are parallelizable and which are sequential. A step that omits `depends_on` is treated as having no dependencies (can run immediately, in parallel with all other dependency-free steps). Steps with `depends_on` MUST NOT execute until all listed steps are in a succeeded state.

### `failure_modes`

Maps known error codes per step to recovery instructions.

If absent, an agent that hits a known error code (e.g., `SCOUTER_DUPLICATE_PROFILE` on the create step) treats it as an unhandled failure and aborts the recipe. With `failure_modes`, the agent has a machine-readable recovery hint: fetch the existing `profile_uid` from `error._meta.existing_uid` and skip to the next step. SHOULD be exhaustive for errors that have deterministic recovery paths.

### `tier`

The minimum service tier required to execute this recipe.

If absent, agents cannot determine whether the service's declared `max_tier` is sufficient before attempting execution. A recipe with `tier: L3` requires dry-run support for safe execution; an L2 service cannot run it safely. MUST match or be below the declared `max_tier` of the service for the recipe to be listed in the catalog.

## Examples

**Good: recipe with full field set, covering a two-step workflow with known failure mode.**

```yaml
- id: register_spc_profile
  title: Register an SPC drift profile
  when_to_use: "Use when setting up statistical process control monitoring for a new model feature."
  inputs:
    - name: model_uid
      schema: { type: string, format: uuid }
    - name: feature_name
      schema: { type: string }
  outputs:
    - name: profile_uid
  steps:
    - id: create
      operation: POST /drift/profiles
      body_template: |
        { "model_uid": "${inputs.model_uid}", "features": ["${inputs.feature_name}"], "drift_type": "spc" }
      capture: { profile_uid: "$.data.uid" }
    - id: alert
      operation: POST /alerts/configs
      depends_on: [create]
      body_template: |
        { "profile_uid": "${steps.create.profile_uid}", "channel": "console" }
  failure_modes:
    - step: create
      error: SCOUTER_DUPLICATE_PROFILE
      recovery: "Fetch existing profile from GET /drift/profiles?model_uid=${inputs.model_uid}&drift_type=spc; use returned uid"
  examples_ref: /openapi/examples/recipes/register_spc_profile
  tier: L1
```

**Bad: recipe with no `failure_modes`, no `when_to_use`, untyped inputs.**

```yaml
- id: setup_monitoring
  title: Set up monitoring
  inputs:
    - name: model_uid
    - name: features
  steps:
    - id: create
      operation: POST /drift/profiles
      body_template: |
        { "model_uid": "${inputs.model_uid}", "features": ${inputs.features} }
```

An agent using this recipe has no guidance on when to use it vs. another recipe, no schema to validate its inputs before execution, and no recovery path when `create` fails with `SCOUTER_DUPLICATE_PROFILE`. It will abort the recipe on a recoverable error and leave the system unmonitored.

**Fix:** Add `when_to_use`, add `schema` to all inputs, add `failure_modes` for known recoverable errors, add `outputs` and `examples_ref`.

## Cross-references

- [Discovery](./02-discovery.md) — `links.recipes` points to `/.well-known/harness/recipes`
- [OpenAPI Extensions](./03-openapi-extensions.md) — `x-harness.related_recipes` links operations to recipes; `harp lint` validates recipe step operations against the OpenAPI spec
- [Self-Test Vectors](./09-self-test-vectors.md) — `examples_ref` on recipes points to vector documents following the same schema
- [Conformance](./13-conformance.md) — recipe DAG executability is a mandatory L3 conformance test

## Limitations and v0.1 caveats

Recipes in v0.1 are read-only artifacts — they describe what to do but are not executed server-side. There is no server-side recipe execution tracking, no recipe run ID, and no audit of which recipe a multi-step write came from. Clients that need to audit recipe runs must track this themselves. The interpolation grammar does not support conditional branching — a recipe that needs "if the create step returned status X, skip to step Y" requires an explicit `failure_modes` entry rather than an inline conditional. Complex conditional workflows beyond the `failure_modes` recovery hint pattern belong in application code, not in a recipe.
