# Naming convention (illustrative)

**Dated 2026-11-11.** Base pattern, adopted by the work repo:

```
fabric-<domain>-<project>-<env>
```

`<env>` is exactly one of `dev`, `test`, `prod`. `<domain>` is the business area, `<project>` the
deliverable inside it; both are lowercase words joined by hyphens.

Rules:

1. Lowercase `a-z`, digits and hyphens only. No underscores, spaces or dots in anything that
   becomes a resource name, a repo folder or a URL path.
2. The environment token is the **last** segment. It never appears in the middle.
3. Never invent a fourth environment word. A short-lived experiment is a `dev` workspace with a
   suffix, not an `uat`.
4. Fabric names are untyped (`fabric-…`); Azure resources carry their resource-type prefix
   (`rg-`, `st-`, `kv-`). The prefix is why a resource list is filterable; Fabric has no such
   prefix, so the domain does that job.
5. Entra groups are the workspace name plus a role suffix: `<workspace>-<role>`. The workspace
   name is a substring, so one search in Entra finds the group (ADR 0006).
6. Item names carry **no** environment token. Items are promoted, so the environment is the
   container, not the name. Exception: a report display title may carry one where a human needs
   to tell two copies apart in a browser tab.
7. Keep a workspace name under 40 characters. Fabric URLs, ADO environment names and Terraform
   resource addresses all carry it, and truncation is silent.
8. Existing names are not renamed to fit. A rename changes a URL, an approval record and a
   Terraform address in one go.

Worked examples:

| Thing | Name |
| --- | --- |
| Workspace, dev | `fabric-sales-forecast-dev` |
| Workspace, test | `fabric-sales-forecast-test` |
| Workspace, prod | `fabric-sales-forecast-prod` |
| Shared capacity (one for all envs, ADR 0004) | `fabric-sales-forecast-shared` |
| Azure resource group (holds the capacity) | `rg-fabric-sales-forecast-shared` |
| Terraform state storage account (no hyphens, ≤24 chars) | `stfabricopssalesdev` |
| Terraform state key | `fabric-sales-forecast/dev.tfstate` |
| Entra group, dev contributors | `fabric-sales-forecast-dev-contributors` |
| Entra group, prod viewers | `fabric-sales-forecast-prod-viewers` |
| ADO pipeline | `fabric-sales-forecast-cicd` |
| ADO Environment, prod (approval gate) | `fabric-sales-forecast-prod` |
| Notebook item | `Sales Forecast Ingest.Notebook` |
| Semantic model item | `Sales Forecast Model.SemanticModel` |

Why this shape:

- **Sortability.** Every Fabric object starts `fabric-`, so a portal, an ADO list or a Terraform
  plan sorts by domain, then project, then environment, and the three copies of one project sit
  together. A `dev-` prefix scatters them across the alphabet.
- **URL legibility.** Workspace and item URLs carry GUIDs, not names, so the name is what a human
  reads in a breadcrumb, a support ticket or an approval record. A name that names its
  environment removes the "which one am I looking at?" question.
- **Group-to-workspace matching.** ADR 0006 spends 3N groups to grant access. Rule 5 makes that
  spend navigable: the workspace and its groups differ by one suffix, so a leaver check and an
  access review both start from the workspace name.
- **No env token in items.** An item name that hard-codes `dev` either lies after promotion or
  forces a rename mid-pipeline, and a rename breaks every reference to it.
