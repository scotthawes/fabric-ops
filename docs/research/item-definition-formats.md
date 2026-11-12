# What is actually inside an item definition, and what should a reviewer look for?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the definition pull-request checklist; any claim that a repo of definitions is reviewable.

## Short answer

A definition is an envelope — `definition.parts[]`, each entry a `path`, a base64 `payload` and
`payloadType: InlineBase64`, plus an optional `format` naming the serialisation (`TMDL`, `PBIR`,
`FabricGitSource`, `sqlproj`, …). The parts are the files Git integration commits, `.platform`
included, but the envelope carries structure and references only: no data, schedules, permissions,
credentials, gateway bindings or sensitivity labels. A definition PR is therefore reviewable for
structure, names, queries and parameters, and for very little else.

## Detail

### 1. The definition envelope

`ItemDefinition` has two documented fields: `format` ("The format of the item definition.") and
`parts` ("A list of definition parts."). Each `ItemDefinitionPart` is `path` ("The item part path."),
`payload` ("The item part payload.") and `payloadType`. `PayloadType` has one value, `InlineBase64`
("Inline Base 64."), noting "Additional payload types may be added over time" — there is no
plain-text option, so a reviewer always decodes first.

`format` is optional and per item type: semantic model `TMDL` or `TMSL` ("but not both at the same
time"); report `PBIR` or `PBIR-Legacy`; notebook `FabricGitSource` (default) or `ipynb`; warehouse
`dacpac` or `sqlproj`; lakehouse `LakehouseDefinitionV1`. Get and update are `…/getDefinition` and
`…/updateDefinition`, both LROs needing read-write on the item.

**Size limits are documented for Git, not the API:** "Maximum file size is 25 MB", full path 250
characters, 25 MB per Azure DevOps commit with a service principal but 125 MB with a user principal,
50 MB per GitHub commit; reports add 1,000 pages and 300 MB of report files. A byte cap on the REST
payload could not be established.

### 2. The `.platform` file

"The platform file is a definition part that contains the item's metadata information." Its
lifecycle is asymmetric: Create Item "Respects the platform file if provided"; Get Item Definition
"Always returns the platform file"; Update Item Definition "Accepts the platform file if provided,
but only if you set a `updateMetadata=true` URL parameter." Fields: `version` ("Version number of
the system files. This number is used to enable backwards compatibility."); `logicalId` ("An
automatically generated cross-workspace identifier representing an item and its source control
representation."); `type` ("The item's type (semantic model, report etc.)"; "The *type* field is
case-sensitive. Don't change the way it's automatically generated or it might fail."); `displayName`
("The name of the item."); `description` ("(optional string)").

**What `logicalId` promises:** it "preserves the link even if the name or directory change"; "a
single workspace can't have two items with the same logicalId"; it "is created when the workspace is
connected to a Git branch or a new item is synced"; "it's essential not to change it in any way."
`Item.logicalId` "is null when no logical ID has been assigned", so `.platform` is also how a
deployed item acquires an identity.

⚠ **The two Learn pages disagree on the shape.** The Git page shows top-level `"version": "2.0"` and
`"$schema": https://developer.microsoft.com/json-schemas/fabric/platform/platformProperties.json`
(unquoted, i.e. invalid JSON as printed). The decoded `fabricGitSource` payload on the notebook
definition page shows `"$schema":
"https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json"`
with `"config": { "version": "2.0", "logicalId": "…" }`. Same fields, different placement: quote
both, hand-write neither.

### 3. A definition versus what Git integration writes

Git writes one folder per item, `{display name}.{public facing type}`, falling back to the logical-ID
GUID. Version 2 folders hold `.platform`; version 1 holds `item.metadata.json` and
`item.config.json`; "You can't have all three files." The API returns the same files base64-encoded:
notebook `notebook-content.py`; semantic model `definition.pbism` plus `definition/*.tmdl`; report
`definition.pbir` plus the `definition/` folder. Same bytes in the ordinary case, with four
documented divergences:

1. **PBIP-only files are not definition parts** — `.pbi/localSettings.json`, `editorSettings.json`,
   `cache.abf`, `unappliedChanges.json`, `DAXQueries/`, `TMDLScripts/`, `mobileState.json`. No part
   table lists them; the `.pbi` files are meant to be gitignored.
2. **Report binding differs by route** — "When deploying a report through Fabric REST API, you must
   use `byConnection` references", yet Git "always exports definitions with a `byPath` reference"
   when model and report share a workspace. REST needs only `semanticmodelid=`.
3. **Schedules sit beside the definition** — fabric-cicd documents a `.schedules` file in the item
   folder (`$schema …/gitIntegration/schedules/1.0.0/schema.json`). No part table mentions it; no
   Learn page found.
4. **A commit normalises and prunes** — the service "deletes files *inside the item folder* that
   aren't part of the item definition" and rewrites CRLF to LF.

`.platform` appears on both sides, but the API treats it as optional — `Required: false` on the data
pipeline, lakehouse, warehouse and mirrored database pages.

### 4. Definitions that are unusual

| Item | Shape | Why it matters |
| --- | --- | --- |
| Semantic model | `definition.pbism` + `definition/` (TMDL) or `model.bim` (TMSL) | TMDL is a folder of text where indentation defines structure; still *(preview)* in Git |
| Report | `definition.pbir` + PBIR `definition/` tree, or `report.json` | PBIR "is generally available and is the default report format", yet Report is *(preview)* in Git; PBIR-Legacy "doesn't support external editing" |
| Data pipeline | one `pipeline-content.json` | activities carry `externalReferences.connection` GUIDs; "Connections are not deployed with fabric-cicd" |
| Notebook | one file, `notebook-content.py`/`.sql`/`.scala`/`.r` | the `# META` block holds `default_lakehouse` and `default_lakehouse_workspace_id` — GUIDs inside source text |
| Lakehouse | `lakehouse.metadata.json` + optional `shortcuts.metadata.json`, `data-access-roles.json`, `alm.settings.json` | no tables, no Files; shortcuts point at `connectionId`/`itemId`; roles "only respected if … enabled through `AlmSettings`" |
| Warehouse | `sqldw.dacpac`, or `sqldw.sqlproj` + `**/*.sql` + `.sharedqueries/*.sql` | the API does carry schema, though fabric-cicd deploys "only the item shell" |
| Mirrored database | `mirroring.json` | a source `connection` GUID, a target `format`, a table list; replication is elsewhere |

Mostly a pointer rather than content: mirrored database, report, lakehouse shortcuts, mounted data
factory, paginated report, and any semantic model whose partitions are DirectQuery or live-connect.

### 5. What is never in a definition

- **Data** — "Data - Data isn't copied. Only metadata is copied"; Git "re-creates item definitions
  only and does not restore item data."
- **Schedules** — a separate Job Scheduler API: `Create Item Schedule`, "An item can create maximum
  20 schedulers". No definition part carries one.
- **Permissions and semantic-model settings** — "Permissions - For a workspace or a specific item"
  is on the not-copied list, as are "Role assignment", "Refresh schedule", "Query caching settings"
  and "Endorsement settings".
- **Gateway bindings and credentials** — "the gateway associated with the target item is not
  automatically mapped to the corresponding data source", and "Data source credentials" are not
  copied. Connections are their own API (`Create Connection`, `Get Connection`); a definition keeps
  only a GUID.
- **Sensitivity labels** — "the sensitivity label is not a part of the definition"; updating "does
  not affect its sensitivity label"; on create the label is `sensitivityLabelSettings`, a sibling of
  `definition`.

A reviewer who thinks a definition diff shows the whole item is wrong six ways.

### 6. What a human can review, and what they cannot

Reviewable, because it is content: `.platform`'s four fields; the part inventory and `format`; TMDL
tables, columns, measures, DAX, M partitions, relationships and the `ref` block; PBIR
`datasetReference` (`byPath` vs `byConnection`), `page.json`, `visual.json` `queryState` and filters;
pipeline `name`, `dependsOn`, `typeProperties`, `externalReferences.connection`; notebook source and
its `# META` GUIDs; warehouse `.sql` DDL, the highest-signal diff of any item type.

Unreviewable or misleading: base64 `payload` strings (decode first); generated IDs (20-character PBIR
object names, `lineageTag`, GUID folders); ordering noise (the AS engine "pushes renamed columns to
the end of the array", and TMDL `ref` ordering exists to suppress churn); `.platform` `$schema` and
CRLF/LF, rewritten by the service; TMDL whitespace, where indentation is semantic, so a "formatting"
diff can break the model; and a refresh through the Enhanced refresh API, which "causes a Git diff
after each refresh." PR advice: confirm `.platform` differs only in `displayName`/`description`, read
TMDL and `definition.pbir` first, grep for GUIDs and `connection` keys and require a `parameter.yml`
entry, and reject reorder-or-reformat-only diffs.

### 7. Traps

- **Hand edits to a regenerated file** — "Manually changing the item definition file. These changes
  are valid, but might be different than if done through the editors." The next commit rewrites them
  and deletes any file inside the item folder that is not part of the definition.
- **A changed `logicalId` breaks references**; so does a moved folder ("if you change a semantic
  model's directory then you should make sure to update the path of the semantic model in the
  report's dependency file"), and "Saving a deployment plan assigns a logical ID to each referenced
  item that doesn't already have one. A later Git operation can report a logical ID conflict."
- **`.platform` edits are ignored on update** without `updateMetadata=true`, so a display-name
  change in the repo silently does nothing.
- **The parameter file rewrites reviewed bytes** — `find_replace` "will replace every instance of a
  specified string in every file", `.platform` is "intentionally excluded from parameterization",
  and a regex matching only a GUID "would risk replacing any matching GUID in the file". Approved
  text ≠ deployed text. Renaming a PBIR object likewise "might break external references both inside
  and outside the report", and a Git delete-and-undo re-creates items with new IDs.

## What this settles

Definition pull-request checklist: (1) `.platform` — `type` unchanged and matching the folder
suffix, `logicalId` unchanged, only `displayName`/`description` differing. (2) Part inventory — same
file set and `format`, no PBIP-only files, no unexplained removals. (3) Content read in the item's
own language — TMDL/DAX/M, PBIR `datasetReference` and `visual.json`, `pipeline-content.json`
activities, notebook source and `# META`. (4) Every GUID or `connection` key touched has a
`parameter.yml` entry for every environment, and the reviewer read the substituted value. (5) No
reorder-only or reformat-only diffs; no hand edits to generated IDs, `$schema` or `version`.

What a review provably cannot catch: whether the deployed value is the reviewed value
(parameterisation runs at deploy time); data, schedules, permissions, gateway bindings, credentials
and labels, absent by construction; whether the item will build or run (TMDL validity, DAX, a
connection that may not exist in the target); drift from uncommitted portal edits, and portal edits
the next deploy overwrites; whether the item type is deployable at all; and a real one-line change
hidden in serialisation or ordering noise.

## What this does not establish

- A byte limit on the REST definition payload; only the Git and report limits are stated.
- The authoritative `.platform` shape — the two Learn pages disagree on `$schema` and where `version`
  lives, and neither says which the service writes today.
- Whether `.schedules` is a Git-integration system file or only a fabric-cicd convention, and whether
  Report and Semantic model leave *(preview)* in the Git list given PBIR is documented as GA.

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [Item definition overview](https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/item-definition-overview), [Get](https://learn.microsoft.com/en-us/rest/api/fabric/core/items/get-item-definition), [Update](https://learn.microsoft.com/en-us/rest/api/fabric/core/items/update-item-definition), [Create](https://learn.microsoft.com/en-us/rest/api/fabric/core/items/create-item) Item Definition/Item | envelope, `.platform` lifecycle, `updateMetadata`, `logicalId` null, labels | ms.date 2024-11-12, upd. 2026-11-11 / 2026-11-10 / 2026-11-11 |
| [Git source code format](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/source-code-format) and [Git integration process](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-integration-process) | folder naming, `.platform` v1/v2, pruning, commit limits, CRLF, manual-edit warning, logical-ID conflicts | upd. 2026-07-21 / 2026-10-26 |
| [Git integration overview](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/intro-to-git-integration) | Report/Semantic model *(preview)* | ms.date 2026-09-01, upd. 2026-11-10 |
| [Semantic model](https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/semantic-model-definition), [Report](https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/report-definition), [Notebook](https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/notebook-definition) definition | formats, part paths, decoded `.platform`, TMDL/PBIR shapes | upd. 2026-03-18 / 2026-03-18 / 2025-07-02 |
| [Lakehouse](https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/lakehouse-definition), [Warehouse](https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/warehouse-definition), [Mirrored database](https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/mirrored-database-definition) definition | shells, pointers, `sqlproj`/`dacpac`, ALM settings | upd. 2026-03-30 / 2026-10-28 / 2026-07-09 |
| [PBIP report](https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-report) and [semantic model](https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-dataset) folders | PBIR GA, PBIP-only files, `byPath`/`byConnection`, size limits | 2026-09-23, upd. 2026-09-29 |
| [TMDL overview](https://learn.microsoft.com/en-us/analysis-services/tmdl/tmdl-overview) | folder structure, indentation semantics, `ref` ordering | ms.date 2023-12-27, upd. 2026-06-11 |
| [Deployment process](https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/understand-the-deployment-process) | not-copied list: data, permissions, schedules, credentials, gateway, endorsement | ms.date 2026-09-24, upd. 2026-11-02 |
| [Job Scheduler](https://learn.microsoft.com/en-us/rest/api/fabric/core/job-scheduler) and [Connections](https://learn.microsoft.com/en-us/rest/api/fabric/core/connections) | schedules and connections are separate APIs | upd. 2025-03-03 / 2026-04-13 |
| [fabric-cicd parameterization](https://github.com/microsoft/fabric-cicd/blob/main/docs/how_to/parameterization.md) | `parameter.yml`, `.schedules`, `.platform` exclusion | read 2026-11-12 |
