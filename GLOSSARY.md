# Glossary

Project vocabulary for Microsoft Fabric. Two sentences per term, product wording only.

Definitions here are the ones this project relies on. Each will gain a Microsoft Learn link
as `docs/research/` fills in — until then, treat a definition without a link as
*provisional* and check it before building on it.

## This project

**Work tenant**
The Microsoft Entra tenant that holds the real Fabric estate under management. Not reachable
from the machine this repo lives on, which is signed into a personal tenant instead.

**Work repo**
The repository that actually deploys: it owns the Azure DevOps pipeline, the service
connection, Terraform state and environment topology. It is a separate project with its own charter
([ADR 0001](docs/adr/0001-research-artefact-not-deployment-tool.md), amended 2026-11-12); this repo
carries findings *to* it and never becomes it.

**Trial capacity**
The free, time-limited Fabric capacity used for experimentation. Useful for learning
mechanics, never for judging the work tenant's settings.

## Platform

**Tenant**
The Microsoft Entra tenant that owns a Fabric deployment. Tenant-wide behaviour is governed
by tenant settings in the admin portal, not by anything in this repo.

**Capacity**
The provisioned pool of compute that Fabric workloads run on, bought as an F SKU (F2 to
F2048) or an equivalent reserved SKU. Workspaces are assigned to a capacity, and their
consumption is measured in capacity units (CU).

**Workspace**
The collaboration and security boundary: it holds items, assigns roles (Admin, Member,
Contributor, Viewer) to users, groups and service principals, and is assigned to one
capacity.

**Item**
Any object inside a workspace — lakehouse, warehouse, notebook, data pipeline, semantic
model, report, environment. The item is the unit that Git integration, deployment pipelines
and the item-definition APIs all operate on.

**Domain**
A tenant-level grouping of workspaces used for governance, so administration can be
delegated by business area rather than workspace by workspace.

**Monitoring Item**
The Fabric item that holds a workspace's telemetry: an Eventstream, a read-only KQL database and an
Activator. Its Eventhouse destination cannot be changed after configuration, and only one Monitoring
Item can collect for a workspace at a time.

**Eventhouse**
A Fabric item holding a KQL database. Here it is the store for capacity events, retained for as long
as its data policy says rather than the metrics app's 14-day compute view.

**Capacity overage**
A billing allowance that lets a capacity exceed its provisioned units and charges the excess at
three times the pay-as-you-go rate. Enabled by default at a 25% threshold, and not configurable
through AzureRM.

**Surge protection**
A capacity setting that rejects new *background* operations once sustained usage crosses a
threshold, before deep throttling starts. It never stops operations already running.

## Deployment

**Deployment pipeline**
Fabric's own CI/CD construct: a named pipeline with ordered stages (Development, Test,
Production by default) that items are promoted through. Distinct from a *pipeline* in Azure
DevOps or GitHub Actions, and from a Fabric *data pipeline* item.

**Git integration**
The per-workspace binding between a workspace and a folder in an Azure DevOps or GitHub
repo, one branch at a time. Items are committed out to the branch and updated from it
manually or on a schedule.

**Item definition**
The part-based JSON representation of an item — what the REST item-definition APIs read and
write, and what a repo holds when it acts as the source of truth.

**fabric-cicd**
Microsoft's Python library for deploying Fabric items from a parameterised repo layout into
workspaces. Verify its current capabilities before depending on it; it moves quickly.

## Identity and access

**Service principal**
A Microsoft Entra application identity used for automation. Fabric only accepts one when the
relevant tenant settings are enabled, and admin-level APIs additionally require the
principal to be in an allowed security group.

**Tenant setting**
A switch in the Fabric admin portal that enables or restricts a capability for the whole
tenant, or for a security group within it. The usual reason an automation that "works in
dev" fails in prod.

**Fabric administrator**
The tenant role that can read and change tenant settings and call the admin REST APIs.
Distinct from a workspace Admin, who controls one workspace only.
