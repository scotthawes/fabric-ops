# 0002 — Two service principals, federated, split by job

- **Status:** accepted
- **Date:** 2026-11-11
- **Deciders:** Scott
- **Evidence:** [`docs/research/identity-service-principal-and-tenant-settings.md`](../research/identity-service-principal-and-tenant-settings.md)

## Context

Pipelines run unattended on self-hosted VMs. Anything with a client secret on disk is a
credential that outlives the job, and Fabric's permission surface splits at a sharp line:
deploying an item needs workspace **Contributor**, while adding or removing a role assignment
needs **Member** or higher — "who can see the data" is a different permission from "what the
data is".

## Decision

Two Microsoft Entra service principals, both using **workload identity federation** through
Azure DevOps service connections, neither holding a client secret:

- `sp-fabric-deploy` — workspace **Contributor** in the deployed workspaces, no admin API
  access, not a member of the security group that the admin API tenant settings require.
- `sp-fabric-admin` — member of the allowed security group named by both Admin API settings,
  **Contributor on the capacity**, **Admin** on the workspaces it reassigns or on which it
  changes roles. It runs only from a manually-approved stage or a scheduled admin job.

Both need the tenant settings from the identity note enabled, and the second is only reachable
from a pipeline stage with an approval gate.

## Consequences

- A compromised deploy pipeline can change content but cannot grant anyone access, and cannot
  read tenant configuration. That is the point of the split.
- The boundary is narrower, not absolute: `sp-fabric-admin` still needs workspace Admin, so it
  can deploy too. Accept it, and keep it off the merge path.
- Day-to-day friction: any pipeline that does both jobs needs two service connections, and a
  single run that deploys and then grants access has to switch identity mid-flight. Prefer
  separate pipelines.
- Unverified: whether a service principal needs a Fabric or Power BI licence; whether the M365
  admin centre accepts an SP for the Fabric administrator role. Both are run-book items, not
  assumptions.
