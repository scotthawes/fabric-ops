# 0006 — Access through one Entra security group per workspace

- **Status:** accepted
- **Date:** 2026-11-11
- **Deciders:** Scott
- **Evidence:** [`identity-service-principal-and-tenant-settings.md`](../research/identity-service-principal-and-tenant-settings.md)

## Context

Workspace roles can be granted to users, groups or service principals. Direct per-user
assignments in Terraform are easy to review in a diff and become a directory of staff that
rots: nothing removes a leaver from a workspace they were granted in March, because the
assignment is not what offboarding looks at. Item-level sharing sits beneath workspace roles
and can hand out access the pipeline never sees.

## Decision

- One Entra security group per workspace, named for the workspace, granted a single workspace
  role. Membership is managed in Entra; the pipeline manages the assignment, not the people.
- The workspace **Admin** role is granted to named humans only. Groups carry `Contributor` or
  `Viewer`, so a group's membership can never silently become admin.
- Role assignments are created by `sp-fabric-admin` through Terraform
  (`fabric_workspace_role_assignment`), never by the deploy principal.
- Direct per-user role assignments are not created by automation. If one exists, it is either a
  break-glass exception, recorded, or a bug.

## Consequences

- Offboarding happens in one place, and the pipeline does not need to know who works here.
- The convention is not an enforcement: a **group can hold `Admin`**, and nested groups work, so
  nothing structural stops a group from becoming admin. The pipeline cannot tell the difference
  between a group assignment and a person. Review is the control.
- "Who can see what" is no longer a Fabric query: role assignments return a bare `Group`
  principal with no members, so the answer is Fabric's admin API joined to Entra group
  membership. Item sharing, OneLake security roles and SQL grants are outside it entirely.
- A workspace whose admins have all left reports `Orphaned` and still looks `Active` to the admin
  API, and role changes only take effect at the member's next Fabric sign-in.
- Group sprawl: three environments × N workspaces means 3N groups, each needing an owner and a
  naming convention. Budget for the naming, not just the groups.
- A workspace with a group-based `Contributor` cannot express "this person is a Contributor in
  dev and a Viewer in prod" without a second group. That is a feature: it makes the difference
  explicit.
- Item-level sharing and app audiences bypass workspace roles entirely, and Fabric has tenant
  settings that control whether viewers may share. Those settings are part of the access model
  even though this repo does not manage them — see the run-book.
- Not established: whether a group containing only a service principal is accepted by both
  Admin API toggles. Verify before relying on it.
