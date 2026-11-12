# 0005 — Authoring in a bound dev workspace, promotion by pinned commit

- **Status:** accepted
- **Date:** 2026-11-11
- **Deciders:** Scott
- **Evidence:** [`deployment-mechanism-comparison.md`](../research/deployment-mechanism-comparison.md)

## Context

Report authors and semantic-model developers will not write item-definition JSON by hand, and
a repo-only workflow cuts them out. But a portal-first workflow makes the platform the source of
truth, which inverts promotion and hides drift. Fabric's Git integration exists precisely to
bridge the two, at the cost of being workspace-bound and lossy at the edges (labels, item IDs
and data do not round-trip).

## Decision

- **Authoring:** the `dev` workspace is bound through Git integration to a branch in the work
  repo (Azure Repos, same ADO organisation). Authors work in the workspace; changes are
  committed out and reviewed as pull requests into `main`.
- **Promotion:** ADO YAML pipelines. `dev` deploys on merge to `main`; `test` follows the same
  artefact; `prod` requires a manual approval on the stage. The artefact is the commit SHA, so
  what was approved is what ships.
- **No Git integration on `test` or `prod`.** Those workspaces are deployment targets only, so
  the only way in is the pipeline.

## Consequences

- The repo stays the source of truth for deployed content without asking authors to leave the
  visual tools.
- Drift is possible in one direction only: an edit in `test` or `prod` is invisible to the repo
  and will be overwritten on the next deploy. That is deliberate, and must be stated to anyone
  with Contributor on those workspaces.
- Git integration's known losses apply to the dev workspace: sensitivity labels, item IDs and
  data do not survive the round trip, and `Update from Git` replaces the whole branch. Item
  types outside the supported list are silently ignored — check before authoring in one.
- **Sensitivity labels are not a deployed property.** Git does not export them, and the only API
  surface is `Create Item` with `labelId` plus `sensitivityLabelApplyStrategy` — creation only, so
  an existing item cannot be labelled by any call. Default and mandatory labelling are explicitly
  not supported for service principals and APIs, so a pipeline-created item arrives unlabelled and
  **nothing fails**: the only detection is the catalogue's Govern report.
- **A labels constraint with a date.** From 28 February 2027, a principal without read-write on
  *all* items in a workspace cannot deploy to it, or assign it, when it contains items protected by
  a label with a protection policy — Git integration included. The deploy principal's Contributor
  role satisfies this today; any move to narrower item-level grants would not.
- **Protection policies behave differently in CI/CD**: they "use only workspace permissions", so a
  deploy succeeds and the service principal's refresh or query fails afterwards, up to 24 hours
  later. A green pipeline is not evidence that the model can read its own data.
- **The authoring model has two tenant-setting dependencies**, not one: `Users can synchronize
  workspace items with their Git repositories`, and — if auto-labelling is on —
  `Users can export workspace items with applied sensitivity labels to Git repositories`. With the
  second off, labelled items become uncommittable and a deploy fails partway through a workspace
  rather than at the first item.
- Because the `main` branch is what the pipeline deploys, `dev` must be updated from Git to see
  what was merged, or the next commit will resurrect what the merge removed.
- A pull request touches JSON, so review is a diff of serialised definitions — reviewable for
  structure and names, weak for behaviour. Behaviour still needs a human in the dev workspace
  before approval.
- **Connecting the dev workspace to Git is not a passive binding.** Creating the connection runs a
  connect plus an initialise, and with `PreferRemote` it can overwrite items already in the
  workspace. Connect before authors start, or initialise with the workspace as the source of truth,
  and do not re-apply the connection casually. The resource also has no import path, so it must be
  created from a clean state rather than adopted.
