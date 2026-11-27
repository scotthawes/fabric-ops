# checks/known-good — reviewed resource-count baselines

**Pack: 2026-11-27.1 · illustrative, not runnable from `fabric-ops` (ADR 0001).**

This directory holds one reviewed baseline per phase: `<phase>.json`. A baseline is what
[`assert_plan`](../../spec/0002-contract.md#7-assert_plan-rules) rule 5 compares a plan against. It is
not a plan, not state, and not an approval — it is the recorded shape of a plan a human already
accepted.

```json
{
  "root": "workspaces",
  "phase": "prod",
  "counts": { "azuread_group": 1, "fabric_workspace": 1, "...": 0 },
  "addresses": ["azuread_group.members", "azuread_group.viewers", "..."]
}
```

## What a baseline does and does not do

- Rule 5 fails when a plan's per-type resource counts differ from `counts`. That is how an extra
  workspace, a dropped group or a vanished role assignment is caught in a plan nobody reads closely.
- It does **no** other work. Rules 1–4 and 6 (replace, delete, the three-assignment floor, capacity
  `Active`, the expected address set) fail closed on every run, with or without a baseline. A
  baseline cannot license a replacement, a destroy or a new address.
- It is a reference, not a permission slip. When it disagrees with a plan, the question is "which
  one changed, and who approved it?", never "how do I silence this?".

## How the first run produces it

The first run has no baseline, and there is no channel back to whoever wrote the pack, so the
pipeline closes the loop itself. At every `assert_plan` invocation
([`skeletons/pipeline/cicd.yml.tmpl`](../../skeletons/pipeline/cicd.yml.tmpl)):

1. If `checks/known-good/<phase>.json` exists, the script runs normally and compares counts.
2. If it does not, the script runs with `--write-baseline` and writes the observed counts into
   `$(Build.ArtifactStagingDirectory)/known-good/<phase>.json`, then the job publishes that
   directory as an artifact. The log carries both the contract's
   `BASELINE-MISSING root=… phase=… counts=…` line (the phase had nothing to compare against) and
   `##vso[task.logissue type=warning]FIRST-RUN BASELINE: commit known-good/<phase>.json from this run's artifact`.
3. The run still applies. A first run is allowed to proceed without a baseline; it is not allowed to
   proceed past a failed rule. If another rule fails, the script refuses to write the baseline at
   all (`refusing to write a baseline while another rule fails`) and the job fails closed.

Only the absent-baseline branch passes `--write-baseline`, so once the file is committed no run can
rewrite its own reference. A re-baseline is always a person editing the file, not a pipeline side
effect.

## How a human commits it

1. Open the completed run, download the `known-good-<phase>` artifact (names below).
2. Read the `counts` and `addresses` against the plan and the change that produced them. A count that
   surprises you is the finding, not a nuisance.
3. Commit the file as `checks/known-good/<phase>.json` in its **own reviewed change**, with the run
   id in the message. Never fold it into the change it describes: a baseline that ships with the
   diff it authorises proves nothing.
4. Delete the artifact only after the commit is on `main`.

| Phase | File | Artifact | Written by |
| --- | --- | --- | --- |
| `platform` | `platform.json` | `known-good-platform-nonprod` **or** `known-good-platform-prod` | both capacity jobs — same counts, one file |
| `domains` | `domains.json` | `known-good-domains` | the optional domains job (`createDomains: true`) |
| `nonprod` | `nonprod.json` | `known-good-nonprod-<domain>` | each domain's nonprod workspace job |
| `prod` | `prod.json` | `known-good-prod-<domain>` | each domain's prod `assert_plan` job |
| `assignments` | `assignments.json` | `known-good-assignments-<domain>` | each domain's assignment job |

Artifact names carry a domain or capacity suffix only because ADO requires a unique artifact name per
run; the file inside is always `<phase>.json`.

## Changing a baseline is a reviewed change

Treat a baseline edit like a schema change. The diff states, in resource types, what the estate is
about to become; it is the one place a reviewer can see "one more workspace" without reading a plan
file. Ask in review:

- Which change legitimately adds or removes a resource of this type?
- Is the new count the same in every environment and every domain that shares this phase?
- Was the baseline produced by a run whose other rules passed?

Not every run needs a baseline edit. A run that matches is silent, which is the point.

## The counts that move by design

- **A new domain re-baselines `domains.json` deliberately.** The domains root is one plan for the
  whole matrix: each domain adds `fabric_domain.this["<domain>"]` plus its admins and contributors
  role assignments, so the per-type counts grow by two. Adding a row in `config/domains.yaml` and its
  `parameters.domains` entry without re-baselining is count drift on the next run — expected drift,
  but still a reviewed change, not a silent one.
- **`nonprod.json` and `prod.json` are shared by every domain.** `<domain>.tfvars` can toggle
  `enable_workspace_identity`; a domain that sets it differently adds
  `fabric_workspace_role_assignment.identity` and `azurerm_role_assignment.identity_storage` and will
  read as drift against the other domains' baseline. Keep the setting uniform, or give that domain
  its own phase — do not widen the shared baseline to cover both shapes.
- **`platform.json` cannot differ between the two capacities.** Both jobs apply the same root, and a
  capacity's SKU, overage and admin list are values on one resource, not extra resources. One file is
  correct; a plan whose count differs is a real difference, not a capacity-size difference.
- `assignments.json` is one data source plus one multi-instance assignment resource, so its counts do
  not grow with the number of domains.

## Scope

Absent or empty is the correct state before the first run
([readiness R4](../../runbook/02-readiness.md)). This page is documentation of a directory that lives
in the **corporate** repo; nothing here is executed from `fabric-ops`.
