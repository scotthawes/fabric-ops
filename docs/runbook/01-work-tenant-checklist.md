# Run-book 01 — First contact with the work tenant

Run these in order. Each item says what you are checking, why it matters, and what a wrong
answer costs. Nothing here can be verified from this repo — see
[ADR 0001](../adr/0001-research-artefact-not-deployment-tool.md).

Record the date and who checked each item. Fabric changes monthly, and an unverified assumption
that outlives the person who made it is the main risk this pack carries.

## 1. Network isolation — do this first

- **Check, in this order:**
  1. Is the tenant setting **Block Public Internet Access** on?
  2. If yes, is it **tenant-level Private Link** or **workspace-level private link** (tenant
     setting *Configure workspace-level inbound network rules*)?
  3. Which private DNS zones are linked to the agent VNet, and does the tenant FQDN resolve
     from the agent?
  4. What sits between the agent and Fabric — proxy, Zscaler, forced tunnelling?
- **Why:** the REST API endpoint is not made private. Fabric keeps `api.fabric.microsoft.com`
  public and *checks where the call came from*: with public access restricted, a caller outside
  the private-link network is refused. So the deploy path is public only while the switch is
  off.
- **Expected:** switch off, or tenant-level private link with agents inside the VNet.
- **If workspace-level private link is in use:** deployment pipelines and semantic models cannot
  live in those workspaces at all, connection strings need the `z{xy}` FQDN, and Git features
  must be used from inside the VNet with branching blocked. That changes the design in
  [recommendation 03](../recommendations/03-deployment-and-environments.md) rather than tuning it.
- **Also confirm:** the agent can reach `login.microsoftonline.com:443` publicly. Entra is not
  behind private link, and without it no federated credential can obtain a token.
- **Timing trap:** a newly created capacity has no private-link path for up to 24 hours, so a
  pipeline that creates a capacity cannot assume private connectivity in the same run.

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
- **Beyond these four:** [the tenant settings catalogue](../research/tenant-settings-catalogue.md)
  catalogues 57 settings that change deployment or access behaviour. The ones most likely to bite
  after the four above are the two Git export switches, the shareable-link setting, and
  `Publish to web`.

## 3. Capacity

- **Check:** the F SKU exists, its SKU, region, and who is capacity Admin. Confirm whether a
  trial capacity is still attached to anything that matters.
- **Why:** workspace assignment needs capacity **Contributor** plus workspace **Admin**, and
  capacity **Admin** is documented for users, so the group-based lever is Contributor.
- **Record:** the SKU size, because it sets the sizing floor for three environments at once
  ([ADR 0004](../adr/0004-one-shared-capacity.md)).
- **Check the overage setting before anything else runs.** Capacity overage is enabled by
  default at a 25% threshold and billed at **3× pay-as-you-go**; AzureRM cannot express it, so
  it never appears in `terraform plan`. Keep the threshold below one-third of the capacity's
  daily CU hours. Turn on surge protection at the same time.
- **Note what you cannot see:** the Azure Monitor supported-metrics index has no
  `Microsoft.Fabric` entry, so utilisation alerting has to come from the Capacity Metrics app or
  Real-Time hub `Capacity.Summary` / `Capacity.State` events.

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

- **Check:** pull the access report — `GET /v1/admin/workspaces`, then
  `…/{workspaceId}/users` — and compare it with the repo's role assignments. Note the rate limit
  (roughly 200 requests/hour) and that the per-workspace access endpoints are Preview.
- **Why:** item sharing, OneLake security roles and SQL grants grant access the pipeline never
  created, and the last two are invisible to every admin API. The drift you cannot see is the
  drift that matters.
- **Expected:** every entry traces to a group in the repo, or is a recorded break-glass exception.
- **Also check:** for workspaces in state **Orphaned** (no admin). The admin API still reports
  them `Active`, so a state-based check misses them entirely.
- **Remember:** a role change only takes effect at the member's next Fabric sign-in, so a removal
  verified in the portal can still be live in someone's open session.

## 9. Sources and gateways

- **Check:** list every source the solution reads, and for each, which route it needs — plain
  connection, VNet data gateway, on-premises data gateway, managed private endpoint, or trusted
  workspace access. Then confirm who owns each gateway and how its credentials rotate.
- **Why:** none of this is deployable. A deployed model with no binding looks healthy and fails at
  refresh, and the binding is per item, per stage, so it must be repeated in test and prod.
- **Route table:** [`gateway-and-connectivity.md`](../research/gateway-and-connectivity.md).
- **Watch for:** an on-premises data gateway cannot register in a tenant with private link enabled.
  If run-book item 1 finds private link on, the on-premises gateway route is closed.
- **Record:** the owner, the rotation cadence, and the error you saw when a binding was missing —
  so the next person recognises it.

## Things this run-book cannot settle

| Unknown | Who answers it | Why it matters |
| --- | --- | --- |
| Whether an SP needs a Fabric licence | first failing call | blocks a clean prod cutover |
| Whether an SP can hold the Fabric administrator role | M365 admin centre | otherwise tenant settings stay human |
| Whether a group of only an SP satisfies the admin API settings | a test call | hinge of the admin path |
| Supported item-type list for your estate | Learn + a test commit | silent non-sync |
| Capacity headroom under real load | production metrics | ADR 0004's revisit trigger |
