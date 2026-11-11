# Role and permission matrix

**Dated 2026-11-11.** Quoted capability wording comes from the Fabric docs via
[the governance note](../research/governance-access-and-workspace-roles.md), which carries the
citations. This page exists so an access request can be approved without opening the research.

## 1. What a workspace role gets you

| Capability | Admin | Member | Contributor | Viewer |
| --- | :-: | :-: | :-: | :-: |
| Add or remove people, including other admins | ✅ | | | |
| Add members or others with lower permissions | ✅ | ✅ | | |
| Allow others to reshare items | ✅ | ✅ | | |
| Update and delete the workspace | ✅ | | | |
| Create or modify database / warehouse items | ✅ | ✅ | ✅ | |
| Write or delete pipelines, notebooks, shortcuts | ✅ | ✅ | ✅ | |
| Read data through OneLake and Spark (`ReadAll`) | ✅ | ✅ | ✅ | |
| Read data through T-SQL / connect to the SQL endpoint (`ReadData`) | ✅ | ✅ | ✅ | ✅ |
| Modify gateway connection settings | ✅ | ✅ | ✅ | |
| Create a workspace identity / connect the workspace to Git | ✅ | | | |
| Publish or unpublish an app | ✅ | ✅ | | |
| Edit OneLake security roles | ✅ | ✅ | | |

Two rows worth reading twice: **Viewer can read data through T-SQL** but **not** through OneLake
or Spark. And **Contributor cannot publish an app, edit OneLake security, or connect the
workspace to Git** — those are Member and above, which is why the deploy principal is
Contributor and nothing more.

## 2. Six ways to get access without a workspace role

The pipeline only controls the first column. The rest is why "who can see this" is not a
Fabric-only question.

| Path | Who can create it | Setting that restrains it |
| --- | --- | --- |
| Item sharing | Admin/Member, or anyone holding **Reshare** on the item | `Allow shareable links to grant access to everyone in your organization` |
| Workspace app / audience | Admin/Member | `Publish apps to the entire organization`, `Push apps to end users` |
| Publish to web | users named by the setting | `Publish to web` → `Allow only existing embed codes` |
| OneLake security roles | workspace Admin/Member | none that disables it |
| SQL `GRANT` on warehouse / SQL endpoint | sufficient rights in the item | none — enforced per item |
| Shortcut and workspace-identity credentials | item owner / workspace Admin | per-connection |

## 3. Three facts that decide most access arguments

1. **Item permissions do not inherit upward.** You cannot remove an inherited workspace grant by
   editing the item.
2. **Removing an item permission does not revoke access.** A Viewer still reaches the item
   through the workspace role.
3. **Role changes apply at the member's next Fabric sign-in**, so a "revoked" user can still act
   in an open session.

## 4. Where service principals differ

- Can be a workspace **Admin** (sanctioned), and hold **Contributor** on the capacity.
- **Cannot** hold semantic-model RLS roles or sit directly on protection policies.
- Appear as a GUID with no display name in the portal — match by object ID, not by name.

## 5. Approving an access request, in four questions

1. Which workspace, and does the person's **group** already carry the role? Prefer the group.
2. Do they need to **publish** or **edit OneLake security**? That is Member, not Contributor.
3. Do they need data through **Spark or OneLake** as well as SQL? If SQL only, Viewer is enough.
4. Is the request really about **one item**? Then it is item sharing, with a named owner and a
   review date — not a workspace role.
