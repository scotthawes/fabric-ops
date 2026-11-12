# Research notes

One question per file. The point is a defensible answer with a link, not a summary of the
docs.

## Index

| Note | Question it answers | Status |
| --- | --- | --- |
| [`deployment-mechanism-comparison.md`](deployment-mechanism-comparison.md) | Which way should a repo deploy and promote Fabric content, given it must also administer workspace users and roles? | answered 2026-11-11 |
| [`identity-service-principal-and-tenant-settings.md`](identity-service-principal-and-tenant-settings.md) | What identity can run headless Fabric automation, and which tenant settings gate it? | answered 2026-11-11 |
| [`capacity-provisioning-and-cost-control.md`](capacity-provisioning-and-cost-control.md) | How is Fabric capacity provisioned and cost-controlled per environment? | answered 2026-11-11 |
| [`network-private-endpoints-and-deployment-path.md`](network-private-endpoints-and-deployment-path.md) | Which network path does each kind of Fabric traffic take, and what must the agent VMs reach? | answered 2026-11-11 |
| [`governance-access-and-workspace-roles.md`](governance-access-and-workspace-roles.md) | Who can see what in Fabric, and what does the platform not tell you about it? | answered 2026-11-11 |
| [`item-type-deployment-coverage.md`](item-type-deployment-coverage.md) | Which item types can actually be deployed through the pipeline, and which must be created by hand? | answered 2026-11-11 |
| [`tenant-settings-catalogue.md`](tenant-settings-catalogue.md) | Which tenant settings are not harmless — the ones that block automation or let access escape a workspace? | answered 2026-11-12 |
| [`gateway-and-connectivity.md`](gateway-and-connectivity.md) | When does a source need a gateway, which kind, and what can the pipeline not do about it? | answered 2026-11-12 |
| [`terraform-operating-model.md`](terraform-operating-model.md) | How do you operate Terraform against Fabric over time — layout, ordering, import, drift, deletion, upgrades? | answered 2026-11-12 |
| [`terraform-provider-surface.md`](terraform-provider-surface.md) | What does the Terraform provider surface actually contain, how does it authenticate, and what does each call require? | answered 2026-11-12 |
| [`sensitivity-labels-lifecycle.md`](sensitivity-labels-lifecycle.md) | What is the lifecycle of a sensitivity label, and what can a pipeline never do about it? | answered 2026-11-12 |
| [`onelake-security-model.md`](onelake-security-model.md) | What is the OneLake data security model, and what can a pipeline do about it? | answered 2026-11-12 |
| [`schema-and-ddl-management.md`](schema-and-ddl-management.md) | How are warehouse and lakehouse schemas versioned and deployed when items ship as shells? | answered 2026-11-12 |
| [`platform-taxonomy.md`](platform-taxonomy.md) | What are the platform's parts actually called, and which layer and engine does each sit at? | answered 2026-11-12 |
| [`monitoring-and-alerting-surface.md`](monitoring-and-alerting-surface.md) | With no Azure Monitor metrics, what can actually be alerted on in Fabric? | answered 2026-11-12 |
| [`workspace-identity.md`](workspace-identity.md) | What is a workspace identity, what is it for, and where does it replace a service principal? | answered 2026-11-12 |
| [`item-definition-formats.md`](item-definition-formats.md) | What is inside an item definition, and what should a reviewer look for? | answered 2026-11-12 |
| [`ado-pipeline-mechanics.md`](ado-pipeline-mechanics.md) | What does Azure DevOps provide for this pipeline, and where are its sharp edges? | answered 2026-11-12 |
| [`workspace-and-item-lifecycle.md`](workspace-and-item-lifecycle.md) | What is safe to automate, what needs an approval, and what is irreversible? | answered 2026-11-12 |

## Adding a note

1. Copy `TEMPLATE.md` to `<topic>-<question>.md`.
2. Answer the question, citing Microsoft Learn or the official `microsoft/*` repo next to
   each claim that matters.
3. Fill in "What this settles" and "What this does not establish". A note with no
   "does not establish" section is usually overconfident.
4. Add a row to the index above.

## Open questions

Collected during grilling; promoted to a note when they start blocking a decision. The working
list lives in [`backlog.md`](backlog.md) — section A is open questions carried by the notes
below, section B is topics not yet researched.

All of the original questions are now answered — see the index above. What remains is
tenant-specific and not researchable from this repo:

- Does the work tenant have **Block Public Internet Access** on, and is its private link
  tenant-level or workspace-level? Run-book item 1.
- Can a group containing only a service principal satisfy both Admin API allow-lists?
- Does a service principal need a Fabric or Power BI licence?
- What does Fabric display for a role assignment whose Entra group has been permanently purged?
