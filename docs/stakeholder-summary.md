# Summary for stakeholders

One page for someone who needs the shape of the plan and the cost of it, not the citations.
Everything here is argued in [`docs/recommendations/`](recommendations/) and decided in
[`docs/adr/`](adr/).

## What is being built

Fabric content — lakehouses, notebooks, semantic models, reports, pipelines — moves from a Git
repository into three environments (dev, test, prod) through an Azure DevOps pipeline, instead of
being clicked together in the portal. People get access through Entra groups, so joiners and
leavers are handled in one place rather than per workspace.

Nothing deploys from this repository. It is the research and decision record; the work repo
builds it.

## The six decisions, in one line each

| Decision | One line |
| --- | --- |
| Automation identity | Two service principals with no stored secrets; one deploys content, one manages access |
| Tooling | Terraform for containers (workspaces, permissions), Microsoft's `fabric-cicd` for content |
| Environments | dev → test → prod, with a human approval before production |
| Authoring | Authors work in the dev workspace, changes are committed to Git and reviewed |
| Capacity | One Fabric capacity shared by all three environments, paid for as an Azure resource |
| Access | One Entra group per workspace; Admin stays with named people |

## What it costs, beyond the obvious

- **Capacity is one shared pool.** A runaway notebook in dev degrades production, and the usual
  cost saving — switching capacity off overnight — is unavailable while production lives on it.
- **Two service principals and a nightly access scan** are ongoing maintenance, not one-off work.
- **Roughly three Entra groups per workspace** to create and keep owned.
- **Some things stay manual:** sensitivity labels are not deployed by the pipeline, and some
  Fabric item types cannot be deployed by any automated route. Both are documented rather than
  hidden.

## What needs a decision from someone senior

1. **Licensing for the automation identities.** Microsoft's documentation does not state whether
   a service principal needs a Fabric licence; the first real deployment answers it.
2. **Who owns capacity spend.** Overage is **on by default at a 25% threshold and bills at three
   times the pay-as-you-go rate**. That default is a cost risk until someone sets a threshold.
3. **Whether production may be down outside working hours.** If yes, the shared capacity can be
   paused to save money; if no, that saving does not exist.
4. **Network posture.** If the tenant blocks public internet access to Fabric, the deployment
   agents must sit inside the right virtual network. One answer from the platform team changes
   the pipeline design.

## What "done" looks like

A colleague can create the work repository and ship the first workspace and notebook without
asking a question. That is the bar this pack is written to — [run-book
01](runbook/01-work-tenant-checklist.md) is the part that still needs a human in the tenant.

## The five words worth knowing

| Term | Means |
| --- | --- |
| **Workspace** | The container, and the security boundary. People get access to a workspace, not to the platform. |
| **Item** | Anything inside a workspace — a notebook, a report, a lakehouse. The unit that gets deployed. |
| **Capacity** | The compute you pay for. All workspaces on it share one performance budget. |
| **Deployment** | Copying a definition from the repository into a workspace. Not the same as Fabric's own "deployment pipelines", which never read the repository. |
| **Tenant setting** | A switch an administrator turns on for the whole organisation. The usual reason automation that worked in one tenant fails in another. |
