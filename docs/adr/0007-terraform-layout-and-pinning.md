# 0007 — Two Terraform roots: capacity, then workspaces; pin the provider exactly

- **Status:** accepted
- **Date:** 2026-11-12
- **Deciders:** Scott
- **Evidence:** [`terraform-operating-model.md`](../research/terraform-operating-model.md)

## Context

The provider's own quickstarts are one flat root per example, which is fine for a demo and wrong
here for three reasons. The capacity is an Azure resource that outlives every environment and must
not be recreated when a workspace changes. The two principals in [ADR 0002](0002-two-service-principals-federated.md)
hold different permissions, and Terraform CLI workspaces are explicitly discouraged by HashiCorp for
exactly that case — separate credentials and access controls. And `preview` is a **provider-wide**
flag, so one preview resource turns it on for everything in the root.

Two further facts from the same research forced the pinning decision. `~> 1.0` is unsafe: v1.6.0
shipped a breaking change in a minor version (`git_credentials` became required). And deleting a
resource block bypasses `lifecycle { prevent_destroy }` entirely, because the block is no longer in
state to be protected.

## Decision

- **`terraform/capacity`** — its own root and state: resource group, tags, the F SKU, capacity
  administration. Applied rarely, by the admin principal, in its own pipeline stage.
- **`terraform/workspaces`** — one root, a state key and a tfvars file per environment, with the
  capacity consumed as `data "fabric_capacity"` protected by a `postcondition` asserting the state
  is `Active`. Workspaces, role assignments and the dev Git connection live here.
- **No CLI workspaces.** Environments are separate state keys, not `terraform workspace select`.
- **Pin exactly** (`= 1.15.1` at time of writing) and commit the dependency lock file. Upgrade
  deliberately, reading the release notes for breaking changes in minor versions.
- **Isolate preview resources** in their own root if one is ever needed, so `preview = true` never
  covers production containers.
- **Hand off by `removed { … lifecycle { destroy = false } }`**, never by deleting a resource block.

## Consequences

- Two applies, in order, and the second one reads a capacity it does not own. A deployment that
  skips the capacity stage fails on the data source rather than creating something unexpected.
- The capacity root changes almost never, so its blast radius is small — but its state is now a
  separate thing to back up and restore.
- Exact pinning converts provider upgrades into a deliberate task with a diff, rather than a
  surprise in a routine run. The cost is falling behind on fixes, which the research notes make
  visible by dating the version they checked.
- Reference to the capacity must be a resource reference in the workspaces root, not a variable
  carrying an ID: an ambient ID has no graph edge, and the first apply of a new environment fails
  with a 404 or 409 on item creation and passes on retry — a failure that looks like a Fabric bug.
- If this is ever collapsed to one root, the state must be moved deliberately; it is not a
  refactor to do casually mid-sprint.
