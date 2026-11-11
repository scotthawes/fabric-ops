# 01 — Identity and access

**The decision this supports:** [ADR 0002](../adr/0002-two-service-principals-federated.md).
**Evidence:** [identity note](../research/identity-service-principal-and-tenant-settings.md).

## The shape

```
Azure DevOps pipeline
   │  service connection A                 service connection B
   │  (workload identity federation)       (workload identity federation)
   ▼                                       ▼
sp-fabric-deploy                        sp-fabric-admin
workspace Contributor                   capacity Contributor
no admin API access                     workspace Admin where it acts
not in the admin security group         member of the admin security group
runs on every merge                     runs only in a gated stage
```

Neither principal holds a secret. The federation trust is the credential, which means there is
nothing to rotate, nothing to leak in a pipeline log, and nothing sitting on a VM between runs.

## What the tenant must allow

Four switches, all in the Fabric admin portal. Names are exact — the setting called "Service
principals can use Fabric APIs" in older articles does not exist in the current index.

| Setting | Page | Group required | Default |
| --- | --- | --- | --- |
| `Service principals can call Fabric public APIs` | Developer settings | yes | on |
| `Service principals can create workspaces, connections, and deployment pipelines` | Developer settings | yes | **off** |
| `Service principals can access read-only admin APIs` | Admin API settings | yes | off |
| `Service principals can access admin APIs used for updates` | Admin API settings | yes | off |

"Group required" means the principal must be in the security group the setting names, not just
in the tenant. Getting this wrong produces a 401 that looks like a permissions problem but is a
tenant-configuration problem.

## The permission thresholds that trip people up

- **Create a workspace** — Contributor on the capacity, plus the setting above for service
  principals.
- **Put a workspace on a capacity** — Contributor on the capacity *and* **Admin** on the
  workspace. Contributor on the workspace is not enough, and the error does not say so.
- **Deploy an item** — Contributor on the workspace.
- **Add or remove a role assignment** — **Member or higher.** This is the line that forces the
  split; a Contributor-only principal cannot grant access, which is the point.
- **Read the item definition** — read and write on the item.
- **Call admin APIs / set tenant settings** — membership of the allowed security group, and for
  the Fabric administrator role the documentation describes users, not service principals.

## Order of operations, once

1. Create both app registrations; no client secrets, federated credentials only.
2. Create the service connections in ADO. There is **no Fabric service connection type** — it is
   *Azure Resource Manager* with *workload identity federation*.
3. Put both principals in the tenant's admin security group if you want admin APIs; put only
   `sp-fabric-admin` there if not.
4. Turn on the four settings, naming that group.
5. Grant `sp-fabric-admin` capacity **Contributor** — capacity **Admin** is documented for users
   only, so Contributor is the lever.
6. Verify each step with one read call before building anything on top. A failed step 4 surfaces
   in step 5 as an unrelated-looking error.

## Risks

- **Unverified: licensing.** No Learn page establishes whether a service principal needs a
  Fabric or Power BI licence. Cheapest safe assumption: it does not, and the first failing call
  in the work tenant proves it either way.
- **Unverified: SP as Fabric administrator.** Documented for users. Do not design around
  assigning the role to a principal; use the security group.
- **Unverified: group containing only an SP.** Confirm the Admin API toggles accept it early —
  it is the hinge of the admin path.
- Token lifetime is 60–90 minutes and managed-identity lifetimes are not configurable; a long
  deployment must refresh rather than assume its token survives the run.

## What it costs to get this wrong

A single principal with Member rights on the deploy path means anything that can merge code can
add itself to a workspace and read production data. That is not a permissions bug, it is the
difference between a deployment pipeline and a privilege-escalation path.
