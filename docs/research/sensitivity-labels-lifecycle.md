# What is the full lifecycle of a sensitivity label in Fabric, and what can a deployment pipeline never do about it?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the label section of any deployment design, and the "settings to agree with a Purview admin" run-book item

## Short answer

A label is created and published in Microsoft Purview, switched on in Fabric by one tenant setting, and attached to an
item — never to its definition. That decides everything: Git does not carry labels, Terraform has no label field,
`Update Item` cannot set one, and default and mandatory labelling both exclude service principals and APIs. A pipeline
can at most pass a `labelId` to `Create Item`; everything else is a post-deploy human step, and when it is forgotten
nothing fails — the item simply arrives unlabelled.

## Detail

### 1. Where labels come from

Labels are Purview Information Protection objects created and published in the Purview portal
(sensitivity-label-overview, ms.date 2025-11-25); Azure Information Protection labels must be migrated to the unified
labelling platform first (information-protection, 2026-07-13). To *gate access* rather than merely classify, a label
must be scoped to **Files & other data assets** with protection settings including **Control access** — only such
"appropriately configured" labels can back a Fabric protection policy (protection-policies-overview, 2025-12-03).
Licensing is stated two ways and not reconciled: "An Azure Information Protection Premium P1 or Premium P2 license" to
apply or view labels plus "a Power BI Pro or Premium Per User (PPU) license" to label items
(enable-data-sensitivity-labels, 2025-06-05), versus "A Microsoft 365 E3/E5 license is required"
(protection-policies-create, 2025-12-03).

Three actors: a Purview label administrator defines and publishes labels, and an **Information Protection Admin** or
higher creates protection policies; a Fabric administrator enables **Allow users to apply sensitivity labels for
content**, which defaults to **The entire organization**; and to apply a label a user needs **Edit** on the item, Power
BI Pro/PPU, *and* the label published to them — "it's not enough just to include the user in the list of specified
users. The sensitivity label must also be published to the user as part of the label's policy definitions"
(information-protection).

**A label is not an endorsement.** Endorsement is a discovery badge — **Promoted**, **Certified** ("only users
specified by a Fabric administrator can actually certify items") and **Master data** — with no protection, no export
behaviour and no licensing (endorsement-overview, 2024-07-11). Endorsement sits on deployment pipelines' "not copied"
list, whereas labels are copied in narrow cases (§4). Neither is a permission.

### 2. What a label actually does in Fabric

In the service a label on its own does **not** gate access:

> "In the Power BI service, sensitivity labeling **does not** affect access to content. Access to content in the
> service is managed solely by Power BI permissions. While the labels are visible, any associated encryption settings
> ... aren't applied. They're applied only to data that leaves the service via a supported export path"
> (sensitivity-label-overview, 2025-11-25).

Content marking does not exist inside Fabric — "Sensitivity label settings, such as encryption and content marking for
files and emails, aren't applied to content" (service-admin-portal-information-protection, 2026-04-08) — and even on
export "Applying a sensitivity label and protection to an exported file doesn't add content marking to the file";
markings appear when the file opens in an Office desktop app.

The one enforced path is a **protection policy**: a Purview object tied to one label that "controls access to an item
that has the associated label by allowing users and groups specified in the policy to retain permissions they have on
the item, while blocking access for everyone else" (protection-policies-overview). Limits: 50 policies, 100 users/groups
each, no guests, up to 24 hours before enforcement; supported for "all native Fabric item types" and Power BI semantic
models — reports and dashboards are **not** supported.

| Exit | Label and protection applied? |
| --- | --- |
| Excel/PDF/PowerPoint export, Analyze in Excel, PivotTable live connection, .pbix download | **Yes.** PowerPoint only via "Export as image"; on .pbix download "the more restrictive label will be applied" |
| .csv or .txt | **No** — "Access control in all other scenarios is unsupported ... or other export paths, such as export to *.csv* files or *.txt* files" |
| Any non-Power BI item's own export | **No** — "Currently no other Fabric experience uses an export method that transfers the sensitivity label to the exported output. However, if they do export an item that has a sensitivity label, a warning is issued" |
| Publish to web | **Could not establish** — in no supported-export list, so no protection documented; no page read says it strips a label |
| Git export | **No** — "Sensitivity labels aren't included when exporting an item" (git-integration-admin-settings, 2026-10-07) |

Manual labelling is "Supported for all Fabric items" but export support is Power BI items only, so for a lakehouse,
notebook or warehouse the label is a visible classification plus, at most, an access gate — not a file-encryption
guarantee.

### 3. Inheritance

Inheritance is **documented, not merely observed** — a capability table plus enumerated cases (information-protection).
Supported: Power BI → Power BI, Fabric → Fabric, Fabric → Power BI. **Not** supported: Power BI → Fabric. On creation,
"A Pipeline created from a Lakehouse inherits", "A Notebook created from a Lakehouse inherits", "A Lakehouse shortcut
created from a Lakehouse inherits", "A Pipeline created from a Notebook inherits", plus the two KQL equivalents. From
data sources: semantic models only, and only Azure Synapse Analytics and Azure SQL Database.

Where the chain breaks: at the **80-item cap** ("If the number of downstream items exceeds 80, no downstream
inheritance takes place"); at a manually applied label ("Downstream inheritance never overwrites labels that were
applied manually"); at a less-restrictive label; and at autogenerated items, which "take their sensitivity label from
their parent lakehouse or data warehouse. They don't inherit the label from items further upstream."

**Automatically apply sensitivity labels to downstream content** is on by default when information protection is
enabled, but it "only controls whether labels propagate to existing downstream items ... It doesn't affect label
inheritance when you create new items" (service-security-sensitivity-label-downstream-inheritance, 2026-07-13);
creation-time inheritance happens regardless. The automation gap: inheritance fires on creating an item *from* another
item, and whether a REST `Create Item` whose definition references a lakehouse counts as "created from" is documented
nowhere I read — **could not establish**.

### 4. The automation surface

**Fabric REST.** `Create Item` takes optional `sensitivityLabelSettings` — `labelId` plus
`sensitivityLabelApplyStrategy`, whose values are `ApplyOrFail` ("Apply the sensitivity label or fail the operation if
it cannot be applied") and `Ignore` ("... proceed with the operation without applying the label"); "The default value is
ApplyOrFail" (create-item, updated 2026-11-11). It is the **only** label surface in Core Items: the operation group
lists 16 operations and none sets a label, and `Update Item` accepts only `displayName` and `description` (update-item,
updated 2026-11-11; Items group, 2026-09-21). A label cannot be added to an existing non-Power BI item over the Fabric
API at all.

**Power BI admin API.** `setLabels`/`removeLabels` cover `dashboards`, `reports`, `datasets` and `dataflows` only; they
need `Tenant.ReadWrite.All`, are capped at "Maximum 25 requests per hour" and 2,000 artifacts per request, and require
the label in the calling admin's own label policy with sufficient usage rights. Outcomes include
`InsufficientUsageRights` and `FailedToGetUsageRights` (information-protection-set-labels-as-admin).

**Terraform.** The generated schema for `fabric_lakehouse` has `display_name`, `definition`, `description`, `folder_id`,
`format`, `tags`, `timeouts` and no label argument (microsoft/terraform-provider-fabric, read 2026-11-12); could not
establish the same for every resource.

**Git: labels are never exported.** The tenant switch **Users can export workspace items with applied sensitivity
labels to Git repositories** exists because "Sensitivity labels aren't included when exporting an item. Therefore, the
Fabric admin can choose whether to block the export of items that have sensitivity labels, or to allow it even though
the sensitivity label won't be included" (git-integration-admin-settings). The limitation is flat: "Sensitivity labels
aren't supported and exporting items with sensitivity labels might be disabled" (git-integration-process, 2026-06-15).

A labelled item committed to Git and then deployed loses its label twice over: the commit drops it or is blocked, and
the deploy creates the item from a definition that never held it. Fabric's own deployment pipelines soften this in
exactly two documented cases — "A new item is deployed, or an existing item is deployed to an empty stage", and "The
source item has a label with protection and the target item doesn't", which asks for consent to override
(understand-the-deployment-process, 2026-09-24). Definition-only deploys via REST or Terraform fall into neither.

### 5. Auto-labelling and default labels

Fabric settings (service-admin-portal-information-protection): **Allow users to apply sensitivity labels for content**
(the master gate); **Apply sensitivity labels from data sources to their data in Power BI**; **Automatically apply
sensitivity labels to downstream content**; **Allow workspace admins to override automatically applied sensitivity
labels**; **Restrict content with protected labels from being shared via link with everyone in your organization**
(disabled unless *both* its prerequisites are on); **Domain admins can set default sensitivity labels for their domains
(preview)** — reports, semantic models and dataflows unsupported, and "Deployment pipelines and Git integration are
currently not supported" (domain-default-sensitivity-label, 2024-11-11). In the label policy: **Apply this default label
to Power BI content** (`Set-LabelPolicy -AdvancedSettings @{powerbidefaultlabelid="<LabelId>"}`) and **Require users to
apply a label to their Fabric and Power BI content** (`powerbimandatory="true"`).

The decisive line for a pipeline:

> "Default labeling in Fabric and Power BI isn't supported for service principals and APIs. Service principals and APIs
> aren't subject to default label policies." (sensitivity-label-default-label-policy, 2025-03-03)

The identical sentence appears for mandatory labelling (mandatory-label-policy, 2025-12-02). Reinforcing it, a non-Power
BI item only gets a default label "if there's a clear, substantive create dialog" — an API create has none. **An item
created by a service principal therefore gets no label from either policy**; whether a domain default or some
inheritance path still catches one is not stated.

### 6. The deployment consequence

Outside the pipeline a team must: agree the label taxonomy with the Purview owner; decide the export and Git-export
switches; create protection policies and put the deploy identity's security group in each; and label the target
workspace after every deploy that creates items — by hand, or as a separate scripted step using `Create Item`'s
`sensitivityLabelSettings` (creation only) or the Power BI admin API (Power BI items only).

When they forget, **nothing fails**; the item is unlabelled. The documented way to see it is the **Govern** report in
the OneLake catalog, which lets an organisation "Identify labeled and unlabeled assets" (information-protection), or
`sensitivityLabel` on the Item schema from `Get Item`/`List Items`. Failures that do surface, where documented:
`ApplyOrFail` fails the create (no error code named); a Git commit is blocked when the export switch is off (exact text
could not establish); an export fails, told by "Sensitivity label can't be loaded" in the info dropdown
(sensitivity-label-overview). And from **February 28, 2027**, "users without read-write permissions on **ALL** workspace
items can't deploy to the workspace through deployment pipelines ... This restriction applies only to workspaces that
contain items protected by sensitivity labels with protection policies" (understand-the-deployment-process); the same
date and restriction apply to Git integration.

### 7. Service principals and labels

An SP can be subject to a protection policy only through a group: "Service principals can't be added to the policy
directly in the Microsoft Purview portal", and if absent from the allowed list, "service principals that currently have
access to data will be denied access, potentially causing your application to break" (protection-policies-create). An
item it creates is unlabelled (§5). A protection policy does not block the deploy itself — "Deployment pipelines and Git
integration use only workspace permissions, not item-level permissions from protection policy labels"
(protection-policies-overview) — so the deploy passes and *runtime* fails: refresh or query of a protected semantic
model by an SP outside the policy, and policies take "up to 24 hours" to start enforcing. Where a native item's label was
applied automatically with no designated issuer, "the user who created the artifact will not be restricted by protection
policies" — written for the creating user; **could not establish** whether it extends to a service principal.

## What this settles

A deployment design should promise exactly one thing about labels: that the pipeline will not pretend to manage them.
The repo cannot be the source of truth, because the label is not part of the item definition — Git drops it, Terraform
cannot express it, `Update Item` cannot retrofit it, and default and mandatory policies exclude service principals and
APIs. The design should say labels are applied in the workspace by a named human (or by a separate, deliberately-
labelled post-deploy step, for the item types that allow it), and that an unlabelled target workspace is an expected,
detectable state rather than a deploy defect. Manual steps: (1) the Purview owner defines labels scoped to **Files &
other data assets** with **Control access**, published to the humans who will label; (2) the Fabric admin enables
**Allow users to apply sensitivity labels for content** and decides the four dependent settings plus **Users can export
workspace items with applied sensitivity labels to Git repositories**; (3) the Purview owner creates protection policies
and adds the deploy SP's security group to each; (4) someone labels each item after deploy, in the target workspace; (5)
the post-deploy check reads `sensitivityLabel` from `List Items` or the catalog **Govern** report and reports unlabelled
items as a warning, never as a failed deploy.

## What this does not establish

- That the label sits outside the item definition in so many words: it rests on "Sensitivity labels aren't included when
  exporting an item" plus `Create Item` taking `sensitivityLabelSettings` as a sibling of `definition`. No page read
  states it as a design fact.
- Whether a REST `Create Item` whose definition references a lakehouse triggers creation-time inheritance; and whether
  `sensitivityLabelSettings` is honoured for every item type or requires the label in the caller's label policy — the
  create page names neither restriction.
- Whether `Update Item Definition` clears, preserves or re-evaluates an existing label on the target item; and whether
  the Terraform provider exposes a label on any resource beyond the `fabric_lakehouse` schema checked here.
- Whether publish to web strips, carries or ignores a label; and whether the domain default label (preview) applies to
  SP-created items.
- The exact error text when Git refuses to export a labelled item, and the error code behind an `ApplyOrFail` failure.

## Correction — 2026-11-12

There is now an admin operation for Fabric items: `POST /v1/admin/items/bulkSetLabels`. Two things
stop it being the answer: its identity table lists service-principal support as **No**, and the Learn
page for it 404s at the time of writing. So this note's conclusion stands — labels are not a deployed
property — but the gap is now narrower than "no operation exists". See
[`purview-and-lineage.md`](purview-and-lineage.md).

## Sources

| Source | What it was used for |
| --- | --- |
| [Information protection in Fabric](https://learn.microsoft.com/en-us/fabric/governance/information-protection) (2026-07-13) and [its tenant settings](https://learn.microsoft.com/en-us/fabric/admin/service-admin-portal-information-protection) (2026-04-08) | Capability table, licensing, inheritance cases, export limits, setting names, Govern report |
| [Enable sensitivity labels](https://learn.microsoft.com/en-us/power-bi/enterprise/service-security-enable-data-sensitivity-labels) (2025-06-05) | AIP P1/P2 licensing, the master gate, label-policy requirement |
| [Sensitivity labels in Power BI](https://learn.microsoft.com/en-us/power-bi/enterprise/service-security-sensitivity-label-overview) (2025-11-25) | "does not affect access", export paths, content marking, "can't be loaded" |
| [Downstream inheritance](https://learn.microsoft.com/en-us/fabric/governance/service-security-sensitivity-label-downstream-inheritance) (2026-07-13) | 80-item cap, no manual overwrite, creation vs existing items |
| [Default](https://learn.microsoft.com/en-us/fabric/governance/sensitivity-label-default-label-policy) (2025-03-03) and [mandatory](https://learn.microsoft.com/en-us/fabric/governance/mandatory-label-policy) (2025-12-02) label policies | SP/API exclusion, `powerbidefaultlabelid`, `powerbimandatory` |
| [Protection policies](https://learn.microsoft.com/en-us/fabric/governance/protection-policies-overview) (2025-12-03) and [create them](https://learn.microsoft.com/en-us/fabric/governance/protection-policies-create) (2025-12-03) | Enforcement model, limits, item types, CI/CD exclusion, SP-via-group |
| [Domain-level default labels](https://learn.microsoft.com/en-us/fabric/governance/domain-default-sensitivity-label) (2024-11-11) | Domain default limits; excludes pipelines and Git |
| [Create Item](https://learn.microsoft.com/en-us/rest/api/fabric/core/items/create-item) and [Update Item](https://learn.microsoft.com/en-us/rest/api/fabric/core/items/update-item) (both updated 2026-11-11), [Items group](https://learn.microsoft.com/en-us/rest/api/fabric/core/items) (2026-09-21) | `sensitivityLabelSettings`, `ApplyOrFail`, no update field, no set-label operation |
| [Set or remove labels with admin APIs](https://learn.microsoft.com/en-us/fabric/governance/service-security-sensitivity-label-inheritance-set-remove-api) (2023-09-12) and [SetLabelsAsAdmin](https://learn.microsoft.com/en-us/rest/api/power-bi/admin/information-protection-set-labels-as-admin) (updated 2025-03-25) | Power BI-only scope, 25 req/hour, failure statuses |
| [Deployment process](https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/understand-the-deployment-process) (2026-09-24) | When labels are copied, endorsement not copied, 2027 restriction |
| [Git integration admin settings](https://learn.microsoft.com/en-us/fabric/admin/git-integration-admin-settings) (2026-10-07) and [Git integration process](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-integration-process) (2026-06-15) | "labels aren't included", the export switch, "Sensitivity labels aren't supported", 2027 restriction |
| [Endorsement overview](https://learn.microsoft.com/en-us/fabric/governance/endorsement-overview) (2024-07-11) | Promoted / Certified / Master data, who may grant |
| [fabric_lakehouse resource](https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/resources/lakehouse.md) (read 2026-11-12) | Generated schema has no label argument |
