# Research backlog

What this repository still owes. Nothing here is a build task: every item produces a cited note
under `docs/research/`, and only some of them change a decision.

## A. Open questions carried by existing notes

Each of these is a gap a note already declares. Most need a tenant or a portal, not more reading.
Anything answered since the note was written is struck through with a pointer.

| Question | Raised by | Needs | Status |
| --- | --- | --- | --- |
| Is the API support table complete? It omits `Map`, `VariableLibrary`, `AnomalyDetector`, `CosmosDBDatabase`, `OperationsAgent`, `WarehouseSnapshot` and others with definition pages | item coverage | Learn + probe | open |
| Does a service principal need a Fabric or Power BI licence? | identity | deploy, or support case | open |
| Can an SP hold capacity **Contributor**, directly or through a group? | capacity | tenant | open |
| Does a group containing only service principals satisfy both Admin API allow-lists? | identity | tenant | open |
| Does the Fabric audit log expand a group to member UPNs? | governance | tenant | open |
| What does Fabric display for an assignment whose Entra group was purged? | governance | tenant | open |
| What does a scheduled refresh do when its capacity is paused? | capacity | tenant | open |
| Does a prepaid yearly reservation keep billing while paused? | capacity | billing question | open |
| Are deployment pipelines supported under **tenant-level** private link? | network | Learn + tenant | open |
| Do the Terraform provider and `fabric-cicd` honour `HTTP_PROXY`? | network | vendor docs or test | open |
| Does an ARM/Terraform-created capacity default overage to on, at 25%? | capacity | tenant | open |
| Do Terraform item resources round-trip every definition, or only create? | deployment | probe per type | open — resource *existence* confirmed, round-trip not |
| Is `SqlPackage` `Publish` transactional against a Fabric warehouse, and does the DDL really apply? | schema | tenant | open |
| Does `CREATE OR ALTER` execute on the warehouse endpoint? Syntax says yes, the "applies to" table says no | schema | tenant | open |
| Can warehouse `MERGE` tolerate new source columns at all? | schema | tenant | open |
| Is `UpdateArtifactRoles` the write path for OneLake roles, and is it audited with before/after values? | OneLake security | Learn | open |
| Does RLS bind Admin/Member/Contributor in user-identity mode? Two Learn pages state opposite things | OneLake security | Learn + tenant | open |
| Is `DefaultReader` recreated after deletion, and does the 250-role cap count it? | OneLake security | tenant | open |
| Does an API-created item referencing a lakehouse count as "created from" for label inheritance? | labels | tenant | open |
| Does `Update Item Definition` preserve an existing label? | labels | tenant | open |
| Is `sensitivityLabelSettings` honoured per item type, or does it need the label in the caller's policy? | labels | Learn + tenant | open |
| Does `sqlcmd` or a pipeline script activity work against the warehouse endpoint at all? Never documented | schema | tenant | open |

## B. Topics not yet researched

Ordered by how much they would change what the team does.

1. **Tenant settings catalogue.** Every setting that touches deployment, service principals,
   sharing, export and external access, with its exact name, default and portal page.
   _(done 2026-11-12)_
2. **Terraform, in depth.** The provider *surface* and the *operating model*.
   _(done 2026-11-12 — ADR 0007)_
3. **Gateway and connectivity.** When a gateway is required, how it authenticates for unattended
   refresh, and what that means for the deployment identity. _(done 2026-11-12)_
4. **OneLake security model.** Data access roles, RLS/CLS, shortcut authorisation.
   _(done 2026-11-12)_
5. **Sensitivity labels lifecycle.** Creation, inheritance, behaviour on export and on deployment.
   _(done 2026-11-12)_
6. **Item definition formats.** What each deployable item's definition actually contains, so a
   review of serialised JSON is meaningful rather than structural.
7. **Schema and DDL management.** How warehouse and lakehouse schemas are versioned and migrated
   when item deployment only ships shells. _(done 2026-11-12 — ADR 0008)_
8. **Monitoring surface.** Capacity Metrics app measures, Real-Time hub event schemas, and which
   alert is actually possible — given there are no Azure Monitor metrics.
   _(done 2026-11-12)_
9. **Mirroring.** Supported sources, latency, cost and limits, since it changes whether ingestion
   is a pipeline concern at all.
10. **Real-Time Intelligence.** Eventhouse retention, KQL database sizing, and what deployment can
    and cannot carry.
11. **Workspace identity.** What it is used for, how it is created, and where it replaces a service
    principal.
12. **Azure DevOps mechanics.** Service connection types, Environment approvals, self-hosted agent
    hardening and secret-free handling.
13. **Power BI coexistence.** What a Fabric estate inherits from an existing Premium or Pro tenant.
14. **Purview and lineage.** What governance metadata Fabric emits, and what has to be maintained
    by hand.
15. **Platform taxonomy.** The official component names and workload grouping, so the system map
    uses Microsoft's vocabulary rather than invented layers. _(done 2026-11-12)_

## C. How an item gets done

1. Copy `docs/research/TEMPLATE.md` to `<topic>-<question>.md`.
2. Answer it against Microsoft Learn or an official `microsoft/*` repository, dated.
3. Say what it settles and what it does not.
4. Add it to the index in `docs/research/README.md`.
5. If it changes a decision, amend the relevant ADR in `docs/adr/` rather than leaving the note
   as the only record.
6. Move any new gap into section A of this file, so the next reader sees it.

A note that changes nothing is still useful — it stops the question being asked again — but it
does not belong in `docs/recommendations/`.
