# 04 — Users and governance

**The decision this supports:** [ADR 0006](../adr/0006-access-through-entra-groups.md).
**Evidence:** [governance note](../research/governance-access-and-workspace-roles.md).

## What to do on day one

Small, cheap, and each one closes a hole that reopening later is awkward:

1. **A group per workspace** carrying `Contributor` or `Viewer`; `Admin` to named humans
   ([ADR 0006](../adr/0006-access-through-entra-groups.md)).
2. **Turn off `Allow shareable links to grant access to everyone in your organization`.**
   Otherwise a Viewer can hand organisation-wide access to an item the pipeline never granted.
3. **Set Publish to web to `Allow only existing embed codes`.** Public web embeds bypass
   workspace roles entirely and are not visible to any admin API.
4. **Turn on both Admin API settings** for `sp-fabric-admin`, so access can be audited at all.
5. **A nightly workspace and workspace-access scan**, diffed against the repo's role assignments.
6. **Certification** on the items that matter, with named certifiers. Endorsement is the only
   cheap signal that separates "this is the real dataset" from "someone's prototype".

## What sits below workspace roles

These grant access the pipeline never created, and two of them are invisible to every admin
API:

| Path | Visible to admin APIs? | Where it is configured |
| --- | --- | --- |
| Item sharing (`Share`) | yes (`…/items/{itemId}/users`) | item → Share |
| Apps and app audiences | partly | workspace → app |
| Publish to web | **no** | workspace → item |
| OneLake security roles | partly — role names yes, effective membership no | lakehouse data access |
| SQL `GRANT` / row-level security | **no** | warehouse / SQL endpoint |
| Shortcut credentials, workspace identity | **no** | shortcut / identity settings |

Design consequence: the access report is **Fabric's API ∪ Entra group expansion**. Fabric returns
a role assignment whose principal is a bare `Group` with no members, so "who can see what" needs
the group's membership read from Entra and joined by object ID. No Fabric endpoint does that join
for you.

## The audit you can actually build

- `GET /v1/admin/workspaces` — inventory, including workspaces assigned to no capacity.
- `GET /v1/admin/workspaces/{workspaceId}/users` — role assignments (Preview).
- `GET /v1/admin/items/{itemId}/users` — per-item access (Preview).
- `GET /v1/admin/items` — item inventory, including items in no workspace.

All need `Tenant.Read.All` and are rate-limited to roughly 200 requests per hour, so an estate
of any size needs paging and caching, not a loop over workspaces on every run.

## What to leave until later

- **OneLake security roles and SQL grants** — per-item, capped (250 roles / 500 members), slow to
  converge. Add when a Viewer genuinely needs a subset of data, not before.
- **Domains** — they buy catalogue filtering and delegated settings, not access control. Domain
  assignment does not affect item visibility; do not sell it internally as an access boundary.
- **Sensitivity labels in the deployment path.** Git integration does not export labels, and the
  only API surface is item *creation* with a label id and an apply strategy — there is no call to
  label an existing item, and defaults are not applied to service principals. A deploy therefore
  produces unlabelled items silently. Apply labels in the workspace and be explicit that the
  pipeline is label-blind.
- **A dated constraint.** From 28 February 2027, a principal without read-write on every item in a
  workspace cannot deploy to it or assign it when labelled protection policies are in use. Workspace
  Contributor satisfies this; item-level grants would not. See
  [the labels note](../research/sensitivity-labels-lifecycle.md).

## Traps

- **A workspace with no Admin is "Orphaned"** and needs one assigned — while the admin API still
  reports it `Active`. Anything that detects workspaces purely by state will miss it.
- **Role changes land at the user's next Fabric sign-in.** A revoked member keeps working in an
  open session.
- **A group can hold `Admin`**, and nested groups work. "Admin goes to named humans" is a
  convention the pipeline cannot enforce, because a group assignment is structurally identical.
- **A permanently purged group** takes its assignments with it, leaving a principal Fabric cannot
  resolve. Entra keeps deleted security groups restorable for only 30 days; what Fabric displays
  afterwards is not established.
- **Service principals** can be workspace Admin, but cannot hold semantic-model RLS roles or sit
  directly on protection policies — so "deploy as the SP, secure data as a human" is real.

## What this costs

Two extra moving parts (the nightly scan and the Entra join) and one tenant setting change that
someone will notice. In exchange, "who can see this data" becomes a query rather than an
afternoon of clicking, and the answer covers the paths nothing else reports.
