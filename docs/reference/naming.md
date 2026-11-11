# Naming convention (illustrative)

**Dated 2026-11-11.** Base pattern, adopted by the work repo:

```
fabric-<domain>-<project>-<env>
```

`<env>` is exactly one of `dev`, `test`, `prod`. `<domain>` is the business area, `<project>` the
deliverable inside it; both lowercase words joined by hyphens.

Rules:

1. Lowercase `a-z`, digits and hyphens only — no underscores, spaces or dots in any name or path.
2. The environment token is the **last** segment, never the middle.
3. No fourth environment word. A short-lived experiment is a suffixed `dev` workspace, not `uat`.
4. Fabric objects are untyped (`fabric-…`); Azure resources keep their type prefix (`rg-`, `st-`,
   `kv-`), which is what makes an Azure list filterable. On the Fabric side the domain does that.
5. Entra groups are `<workspace>-<role>`, so one Entra search finds the group (ADR 0006).
6. Item names carry **no** environment token — items are promoted, so the environment is the
   container. Exception: a report title may carry one so two browser tabs are tellable apart.
7. Keep workspace names under 40 characters: URLs, ADO environment names and Terraform addresses
   carry them, and truncation is silent.
8. Existing names are not renamed to fit: one rename changes a URL, an approval record and a
   Terraform address at once.

| Thing | Name |
| --- | --- |
| Workspace, dev / test / prod | `fabric-sales-forecast-dev` · `-test` · `-prod` |
| Shared capacity, all envs (ADR 0004) | `fabric-sales-forecast-shared` |
| Resource group for the capacity | `rg-fabric-sales-forecast-shared` |
| State account / key | `stfabricopssalesdev` · `fabric-sales-forecast/dev.tfstate` |
| Entra group, dev contributors | `fabric-sales-forecast-dev-contributors` |
| Entra group, prod viewers | `fabric-sales-forecast-prod-viewers` |
| ADO pipeline / prod Environment | `fabric-sales-forecast-cicd` · `fabric-sales-forecast-prod` |
| Notebook / semantic model item | `Sales Forecast Ingest.Notebook` · `Sales Forecast Model.SemanticModel` |

Why this shape:

- **Sortability.** Every object starts `fabric-`, so a portal, ADO list or plan sorts by domain,
  project, then environment; a `dev-` prefix scatters the three copies.
- **URL legibility.** Workspace and item URLs carry GUIDs, so the name is what a human reads in a
  breadcrumb, ticket or approval record. Naming the environment removes "which one is this?".
- **Group-to-workspace matching.** ADR 0006 spends 3N groups on access; rule 5 makes that spend
  navigable, since an access review starts from the workspace name.
- **No env token in items.** An item named `…-dev` lies after promotion, or forces a rename that
  breaks every reference to it.
