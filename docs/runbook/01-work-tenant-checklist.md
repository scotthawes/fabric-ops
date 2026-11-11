# Run-book 01 — First contact with the work tenant

Run these in order. Each item says what you are checking, why it matters, and what a wrong
answer costs. Nothing here can be verified from this repo — see
[ADR 0001](../adr/0001-research-artefact-not-deployment-tool.md).

Record the date and who checked each item. Fabric changes monthly, and an unverified assumption
that outlives the person who made it is the main risk this pack carries.

## 1. Network isolation — do this first

- **Check:** ask the platform team which private-networking features are in use: Fabric private
  links (inbound), managed private endpoints, managed virtual network, trusted workspace access.
- **Why:** it decides whether the deployment call to `api.fabric.microsoft.com` travels over
  public HTTPS or must originate inside a VNet. Everything downstream assumes the former.
- **Expected:** data plane private, control plane public.
- **If different:** stop and re-plan the agent topology before writing any YAML. The pipeline
  design in [recommendation 03](../recommendations/03-deployment-and-environments.md) assumes
  agents reach the public API.

## 2. Tenant settings

- **Check:** the four service-principal settings, and which security group each names.

  | Setting | Page | Expected |
  | --- | --- | --- |
  | `Service principals can call Fabric public APIs` | Developer settings | on |
  | `Service principals can create workspaces, connections, and deployment pipelines` | Developer settings | **off by default — turn on** |
  | `Service principals can access read-only admin APIs` | Admin API settings | off, on if auditing |
  | `Service principals can access admin APIs used for updates` | Admin API settings | off, on only for the admin principal |

- **Why:** a principal missing from the named group authenticates fine and then fails on the
  first call with an error that reads like a role problem.
- **Watch for:** "Service principals can use Fabric APIs" appears in older docs and some
  Microsoft tutorials. It is not a setting in the current index. Do not hunt for it.

## 3. Capacity

- **Check:** the F SKU exists, its SKU, region, and who is capacity Admin. Confirm whether a
  trial capacity is still attached to anything that matters.
- **Why:** workspace assignment needs capacity **Contributor** plus workspace **Admin**, and
  capacity **Admin** is documented for users, so the group-based lever is Contributor.
- **Record:** the SKU size, because it sets the sizing floor for three environments at once
  ([ADR 0004](../adr/0004-one-shared-capacity.md)).

## 4. Service principals and identities

- **Check:** both app registrations exist, both are federated (no client secret), and each ADO
  service connection authenticates successfully against the right tenant.
- **Why:** there is no Fabric service connection type; it is *Azure Resource Manager* with
  *workload identity federation*. A client secret here defeats [ADR 0002](../adr/0002-two-service-principals-federated.md).
- **Verify explicitly:** that `sp-fabric-admin` can read one admin API response. That proves the
  security group membership and the toggle, which are two separate things that fail alike.
- **Still unknown:** whether a service principal needs a Fabric or Power BI licence. The first
  real deploy answers it; note the answer here.

## 5. Groups and naming

- **Check:** whether Entra groups can be created for the pattern in
  [`docs/reference/naming.md`](../reference/naming.md), and who owns group membership.
- **Why:** three environments × each workspace is a lot of groups. If nobody owns membership,
  the access model becomes a list of people who left.
- **Verify:** a group containing only a service principal is accepted by both Admin API toggles.
  This is the hinge of the admin path and is not established in the documentation.

## 6. Git connection

- **Check:** whether the dev workspace can connect to the work repo (Azure Repos, same ADO
  organisation), what the commit size and item-count limits are for your estate, and which of
  your item types are on the supported list.
- **Why:** item types outside the list are silently ignored by commit and update — they look
  connected and are not synced.
- **Watch for:** cross-geography export and sensitivity-labelled export are separate tenant
  settings; either one being off produces a connection that works for some items only.

## 7. First deployment, smallest possible

- **Check:** deploy one workspace, one role assignment and one notebook to `dev`. Then read all
  three back.
- **Why:** proves the identity, the ordering (containers before content) and the parameterisation
  in one run, before anything complicated exists.
- **Expected:** the role assignment exists with the group's object ID, the notebook's definition
  matches the repo, and the capacity is not paused.

## 8. Access audit

- **Check:** run the workspace-users admin API and compare it with the repo's role assignments.
- **Why:** item sharing, apps and OneLake roles grant access the pipeline never created. The
  drift you cannot see is the drift that matters.
- **Expected:** every entry traces to a group in the repo, or is a recorded break-glass exception.

## Things this run-book cannot settle

| Unknown | Who answers it | Why it matters |
| --- | --- | --- |
| Whether an SP needs a Fabric licence | first failing call | blocks a clean prod cutover |
| Whether an SP can hold the Fabric administrator role | M365 admin centre | otherwise tenant settings stay human |
| Whether a group of only an SP satisfies the admin API settings | a test call | hinge of the admin path |
| Supported item-type list for your estate | Learn + a test commit | silent non-sync |
| Capacity headroom under real load | production metrics | ADR 0004's revisit trigger |
