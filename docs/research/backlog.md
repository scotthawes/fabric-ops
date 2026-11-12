# Research backlog

What this repository still owes. Nothing here is a build task: every item produces a cited note
under `docs/research/`, and only some of them change a decision.

## A. Open questions carried by existing notes

Each of these is a gap a note already declares. Most need a tenant or a portal, not more reading.

| Question | Raised by | Needs |
| --- | --- | --- |
| Is the API support table complete? It omits `Map`, `VariableLibrary`, `AnomalyDetector`, `CosmosDBDatabase`, `OperationsAgent`, `WarehouseSnapshot` and others that have definition pages | item-type coverage | Learn + one probe call |
| Does a service principal need a Fabric or Power BI licence? | identity note | first real deploy, or support case |
| Can an SP hold capacity **Contributor**, directly or through a group? | capacity note | tenant test |
| Does a group containing only service principals satisfy both Admin API allow-lists? | identity note | tenant test |
| Does the Fabric audit log ever expand a group to member UPNs? | governance note | tenant test on a known group |
| What does Fabric display for an assignment whose Entra group was permanently purged? | governance note | tenant test |
| What does a scheduled refresh do when its capacity is paused — fail, queue or skip? | capacity note | tenant test |
| Does a prepaid yearly reservation keep billing while the capacity is paused? | capacity note | billing question |
| Are deployment pipelines supported under **tenant-level** private link? Only the workspace-level block is documented | network note | Learn + tenant |
| Do the Terraform provider and `fabric-cicd` honour `HTTP_PROXY`? | network note | vendor docs or a test |
| Does an ARM/Terraform-created capacity default overage to on, at 25%? | capacity note | tenant test |
| Do Terraform item resources round-trip every definition, or only create? | deployment note | one probe per item type |

## B. Topics not yet researched

Ordered by how much they would change what the team does.

1. **Tenant settings catalogue.** Every setting that touches deployment, service principals,
   sharing, export and external access, with its exact name, default and portal page. The four
   in the identity note are the ones that block us; the rest are the ones that will surprise us.
   _(done 2026-11-12)_
2. **Terraform, in depth.** Two notes: the provider *surface* (resource inventory, authentication,
   per-resource permissions, state semantics) and the *operating model* (layout, ordering, import,
   drift, deletion, upgrades, and the boundary with the content deployer). ADR 0003 leans on
   Terraform for the whole control plane, so this is the load-bearing research.
   _(done 2026-11-12)_
2. **Capacity economics.** F-SKU sizing against real workloads, reservation versus pay-as-you-go,
   how smoothing and overage interact in a month's bill, and what a chargeback model would need.
3. **Gateway and connectivity.** When an on-premises or VNet data gateway is required, how it
   authenticates for unattended refresh, and how that interacts with the deployment identity.
   _(done 2026-11-12)_
4. **OneLake security model.** Data access roles, RLS/CLS, shortcut authorisation, and what
   "Viewer can't read OneLake but can read T-SQL" means in practice.
   _(in progress 2026-11-12)_
5. **Sensitivity labels lifecycle.** Creation, inheritance to downstream items, behaviour on
   export and on deployment, and what the pipeline genuinely cannot do.
   _(in progress 2026-11-12)_
6. **Item definition formats.** What each deployable item's definition actually contains, so
   reviews of serialised JSON are meaningful rather than structural.
7. **Schema and DDL management.** How warehouse and lakehouse schemas are versioned and migrated
   when item deployment only ships shells.
8. **Monitoring surface.** Capacity Metrics app measures, Real-Time hub event schemas, and which
   alert is actually possible — given there are no Azure Monitor metrics.
9. **Mirroring.** Supported sources, latency, cost and limits, since it changes whether ingestion
   is a pipeline concern at all.
10. **Real-Time Intelligence.** Eventhouse retention, KQL database sizing, and what deployment can
    and cannot carry.
11. **Workspace identity.** What it is used for, how it is created, and where it replaces a
    service principal.
12. **Azure DevOps mechanics.** Service connection types, Environment approvals, self-hosted agent
    hardening and key-vault-free secret handling.
13. **Power BI coexistence.** What a Fabric estate inherits from an existing Premium or Pro
    tenant, and what that changes about licensing and access.
14. **Purview and lineage.** What governance metadata Fabric emits, and what has to be maintained
    by hand.

## C. How an item gets done

1. Copy `docs/research/TEMPLATE.md` to `<topic>-<question>.md`.
2. Answer it against Microsoft Learn or an official `microsoft/*` repository, dated.
3. Say what it settles and what it does not.
4. Add it to the index in `docs/research/README.md`.
5. If it changes a decision, amend the relevant ADR in `docs/adr/` rather than leaving the note
   as the only record.

A note that changes nothing is still useful — it stops the question being asked again — but it
does not belong in `docs/recommendations/`.
