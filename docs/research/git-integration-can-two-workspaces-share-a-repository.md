# Can two or more Fabric workspaces bind to the same Azure DevOps repository, and what breaks when they do?

- **Status:** answered
- **Checked:** 2026-11-26
- **Blocks:** the Git-layout decision for the work repo — one Azure DevOps project and repository serving every
  workspace, versus one repository per workspace

## Short answer

Yes to one repository: the unit of binding is not a repository but a tuple — provider, organisation, project,
repository, branch and folder — and nothing documented makes that tuple unique across workspaces. Learn states
that "a branch can be synced to multiple workspaces" and recommends either one branch per workspace or one
branch split into a folder per workspace. Two workspaces on the *same* folder appear to be permitted for the same
reason, but they are replicas, not collaborators: each holds a full copy of the same items, the only merge model
is workspace-versus-branch, and connecting the second one overwrites whichever side is not preferred.

## Detail

Scope: Microsoft Learn's Git integration pages and the `microsoft/terraform-provider-fabric` `workspace_git`
resource docs, read 2026-11-26. Where a statement is an inference from documented mechanics rather than a
documented sentence, it says so.

### 1. A binding is a tuple, not a repository

`POST /v1/workspaces/{workspaceId}/git/connect` takes `gitProviderDetails`, and `GET …/git/connection` returns the
same object. Those fields are the whole identity of the binding ([Connect][connect], [Get Connection][get-conn]):

| Field | Constraint | Note |
| --- | --- | --- |
| `gitProviderType` | `AzureDevOps` or `GitHub` | Selects whether the Azure DevOps or GitHub fields apply |
| `organizationName` | ≤100 chars | Azure DevOps only |
| `projectName` | ≤100 chars | Azure DevOps only |
| `ownerName` | ≤100 chars | GitHub only |
| `repositoryName` | ≤128 chars | Both providers |
| `branchName` | ≤250 chars (REST and provider); Learn's limitations section says 244 | One branch at a time |
| `directoryName` | ≤256 chars, "the relative path to the directory" | Empty string means the repository root |

None of these is unique per workspace. The one uniqueness rule on the *workspace* side is that a workspace can
hold one binding: a second connect returns `WorkspaceAlreadyConnectedToGit`, and in Terraform
`git_provider_details` is `ForceNew`, so changing any of the six destroys and recreates the binding
([Connect][connect], [`fabric_workspace_git`][tf-git]).

The product also names the shared-tuple case directly. A *related workspace* is either a branched workspace or
one that "has same connection properties as the current branch, such as the same organization, project,
repository, and git folder" ([Git integration process][process]). A workspace with an identical tuple is
therefore a recognised relationship, not an error state.

### 2. What each field actually permits

Terraform spells these `git_provider_details.git_provider_type`, `…branch_name` and `…directory_name`; the
constraints are the same ([`fabric_workspace_git`][tf-git]).

- **`gitProviderType`** is a discriminator for the request shape and for credential rules, not for tenancy. It
  carries no repository identity.
- **`branchName`** is one branch per workspace, but not one workspace per branch: "The Fabric workspace is a
  shared runtime environment for all items, and each workspace can thus be connected to a *single* branch"
  ([development process][manage-branches]). Switching branch replaces every item in the workspace, and the new
  branch "must contain the same directory as the current branch" ([branched workspace][branched]).
- **`directoryName`** is the folder the workspace reads and writes. The UI calls it **Folder**: "Type in the name
  of an existing folder or enter a name to create a new folder. If you leave the folder name blank, content is
  created in the root folder. You can only connect to one folder at a time" ([get started][get-started]). The
  service-principal walkthrough passes `"<folder name – must exist before OR empty>"` ([automate SP][sp-auto]).
  Terraform enforces a leading `/` (`Directory name path must starts with forward slash '/'`) while the REST
  examples pass `"Test Directory"` and Get Connection returns `""` for the root — treat the leading slash as
  provider-side normalisation, not part of the stored value ([`fabric_workspace_git`][tf-git]).
- **`ConfiguredConnection`** is a credential *source*, not a binding. `myGitCredentials` is "user-specific Git
  credentials … not shared with other workspace contributors"; for Azure DevOps it is optional and defaults to
  `Automatic`, for GitHub it is required ([Connect][connect]). `ConfiguredConnection` points at a Fabric cloud
  connection (`ShareableCloud`, type `AzureDevOpsSourceControl` or `GitHubSourceControl`) whose `url` parameter
  scopes it to one repository and whose credential is a service principal or PAT
  ([Git automation][automation]). One connection can serve many workspaces: the SP page says other users on the
  same workspace "don't need to repeat the connection process" and that Fabric falls back to "any Configured
  Credential which the user has access to" ([automate SP][sp-auto]). With `Automatic`, Connect is "blocked for
  GitHub provider and for Service Principal" ([Connect][connect]).

### 3. Several workspaces, one repository — the documented shapes

The clearest sentence is in the source-code-format page:

> Since a branch can be synced to multiple workspaces, it's possible to have items in different workspaces with
> the same logicalId, but a single workspace can't have two items with the same logicalId.
> — [Git source code format][format]

The 1,000-item section repeats the layout advice: split artefacts into sets, where "each set should be placed in a
separate workspace and linked to a different Git branch, or organized into different folders within a single
branch" ([Git integration process][process]). That gives three documented shapes:

| Shape | Tuple | What it is for |
| --- | --- | --- |
| One branch per workspace | same repo, distinct `branchName` | The developer model: dev/test/prod or one feature branch per workspace |
| One branch, one folder per workspace | same repo and branch, distinct `directoryName` | Splitting a large estate, or separating domains, without more branches |
| One folder, several workspaces | identical tuple | A mirror or review copy; not a collaboration model (see §4) |

(A fourth, "one repository per workspace", works but buys nothing the first two do not; it only multiplies
repositories.)

### 4. What breaks when two workspaces sync from the same branch

**Same folder.** The first sync is directional and destructive. If both sides hold content, you choose: "If you
commit your workspace to the Git branch, all supported workspace content is exported to Git and overwrites the
current Git content", or the workspace "is overwritten, and you lose your workspace content" ([process][process]).
`initializeConnection` encodes the same choice as `PreferRemote` or `PreferWorkspace`, and the SP walkthrough
warns to prefer the workspace "in case the connected workspace has items already" ([automate SP][sp-auto]).
So the second workspace to connect to a populated folder either adopts the folder or replaces it.

After that the two are replicas. Status is computed against the branch, not against each other: the response
carries `workspaceHead` and `remoteCommitHash` as commit SHAs, and flags `Conflict` when "the remote and workspace
items were both modified" ([Get Status][get-status]). Commits are then serialised by the branch head: "If there
were updates made to the Git branch, commits are disabled until you update your workspace" ([process][process]).
A conflict is resolved per item, and accepting the incoming side loses the workspace version
([conflict resolution][conflict]). Nothing in that model merges two workspaces; conflicts are defined only as
workspace-versus-branch.

Consequences, in order of confidence:

- **Documented:** the same `logicalId` in two workspaces on one branch is legal; only two items with the same
  logical ID *in one workspace* are blocked ([format][format], [troubleshooting][trouble]).
- **Documented:** a second workspace cannot commit while the branch has moved ahead of its own head; it must
  update first, which is a whole-side overwrite of each changed item.
- **Inference:** with both workspaces editable, the last committer wins per item, and there is no record of the
  other workspace's uncommitted state. The pair is safe as a read-only mirror (for example a review workspace
  that only ever updates) and unsafe as two authoring surfaces.

**Same branch, different folders.** These are independent by design: the binding is to a folder, items live in
subdirectories beneath it, and a commit only touches items in that workspace. Two caveats. First, the sync state
is anchored to the branch commit, not the folder — status returns the branch head and "the *Update* command
always updates the entire branch and syncs to the most recent commit" ([process][process]) — so whether a commit
in another folder blocks yours is not stated (see "does not establish"). Second, nesting one workspace's folder
inside another's is not a documented configuration; keep them siblings.

**Two branches** is the intended isolation: switching branch "overrides all items in the workspace", and a
branch-out creates the new branch and workspace together ([branched workspace][branched]).

### 5. The service-principal path

- The SP must be **Admin** on the workspace (Connect requires it) and must be granted "Access to the relevant
  Azure DevOps organization and project" — added to the ADO organisation and to a project team
  ([automate SP][sp-auto], [manual SP][sp-manual]).
- The SP needs permission on the cloud connection: either "share the connection with the service principal" or
  create a new connection with `POST /v1/connections` passing its credentials ([automate SP][sp-auto]).
- Connect succeeds for an SP **only** with `myGitCredentials.source = "ConfiguredConnection"`; `Automatic` is
  "blocked for GitHub provider and for Service Principal" ([Connect][connect]).
- The SP path costs commit headroom: 25 MB through the Azure DevOps connector, against 125 MB for the default
  SSO user principal ([process][process]).
- `Update From Git` as an SP is "Only supported when all the items involved in the operation support service
  principals" ([Update From Git][update]).
- One SP connection can be reused by any workspace binding the SP administers; it is scoped to the repository URL,
  not to a workspace ([Git automation][automation]).

### 6. Limits that bear on sharing a repository

| Limit | Value | Source |
| --- | --- | --- |
| Items per workspace | 1,000. "If the Git branch contains more than 1,000 items, syncing the content to the workspace will fail" | [process][process] |
| File size | 25 MB maximum | [process][process] |
| Commit size, Azure DevOps | 25 MB with service principal; 125 MB with user principal (SSO) | [process][process] |
| Commit size, GitHub | 50 MB combined; troubleshooting states 50 MB unqualified | [process][process], [troubleshooting][trouble] |
| Folder depth | 10 levels | [process][process] |
| Branch name | 244 chars (limitations) vs 250 (REST and provider) | [process][process], [Connect][connect], [provider docs][tf-git] |
| Full path | 250 chars | [process][process] |
| Git API throttling | 50 calls/min per Git operation, 500/min unified quota | [Connect][connect] |

For a shared repository the 1,000-item limit is the operative one: each workspace must stay under it, and adding
a workspace for a new domain is the documented way to grow. With many workspaces committing on a schedule, the
50 calls/min ceiling also applies to each connect, status, commit and update call ([Connect][connect],
[Update From Git][update]).

### 7. What identifies a folder, and can two workspaces point at the same one?

A workspace's folder is identified only by `directoryName` within the tuple of §1. Inside the folder, item
identity is **not** the directory name: each item sits in `{display name}.{public facing type}` (falling back to
the logical-ID GUID when the name is unusable), and the durable key is `config.logicalId` in `.platform` —
"Items with the same logicalIds are assumed to be the same", and renaming the folder does not rename the item
([format][format]). So the folder is a path; the items are logical IDs.

Nothing documented forbids two workspaces naming the same `directoryName`. The Connect error list contains no
repository- or folder-uniqueness code, only `WorkspaceAlreadyConnectedToGit`, and the "related workspaces"
definition presumes workspaces sharing a git folder ([Connect][connect], [process][process]). The honest reading:
it is permitted and it is a mirror. The documented collaboration answer to "two people, same content" is a
branched workspace on its own branch, not a second workspace on the same folder ([development process][manage-branches]).

## What this settles

- A repository is not the constraint. Several workspaces can bind into one Azure DevOps project and repository;
  repository; the binding tuple is provider + organisation + project + repository + branch + folder, and only the
  *workspace* is limited to one binding.
- The two supported layouts are one branch per workspace, and one branch with one folder per workspace. Learn
  recommends both in the same paragraph about splitting large estates.
- Two workspaces on the identical folder are not blocked by any documented rule, but they are replicas with a
  workspace-versus-branch conflict model and a destructive first sync; use them as mirrors, not as two editors.
- The service principal must be a workspace Admin, must have ADO organisation and project access, must use
  `ConfiguredConnection`, and pays a 25 MB commit cap instead of 125 MB.
- Same `logicalId` across workspaces on one branch is explicitly allowed; duplicate logical IDs are only an error
  within a single workspace.
- The item, file-size, folder-depth and call-rate limits all attach to the binding.

## What this does not establish

- **Whether Connect rejects a second workspace on the identical tuple.** No uniqueness rule or error code is
  documented either way. The related-workspaces wording implies it is accepted; a tenant test is the only proof.
- **What a genuinely concurrent commit does.** The UI disables commit until the workspace updates, and the API
  takes `workspaceHead`, but the docs never say whether a stale head is refused with `WorkspaceHeadMismatch` or
  whether the commit overwrites. Both behaviours are consistent with the published error list.
- **Whether the head check is branch-wide or folder-scoped.** Status returns the branch head, so a commit in
  another folder may still block a workspace sharing only the branch. This decides whether folder-per-workspace
  is truly independent or merely mostly independent. Needs a tenant.
- **Whether the 1,000-item cap counts the connected folder or the whole branch.** The limit sentence says
  "the Git branch", but the recommended workaround — different folders in one branch — only works if the count is
  per folder.
- **Which commit-size figure governs.** 25 MB per file, 25 MB per ADO/SP commit and an unqualified 50 MB in
  troubleshooting cannot all be the binding rule; whether a single 25 MB item is committable on the SP path is
  untested here.
- **Whether nested or overlapping folders are supported.** No page addresses one workspace's folder living inside
  another's.
- **Tenant switches and cross-geography.** Whether the work tenant has Git integration enabled, and whether an
  ADO repository in another region needs **Users can export items to Git repositories in other geographical
  locations**, is covered in [`tenant-settings-catalogue.md`](tenant-settings-catalogue.md), not here.

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [Git integration overview](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/intro-to-git-integration) | workspace-level scope, supported providers, unsupported items | ms.date 2026-11-24, read 2026-11-26 |
| [Git integration process](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-integration-process) | binding fields, permissions, initial sync direction, folders, related workspaces, 1,000-item limit, 25 MB file, 25/125 MB ADO commit, 10 levels | ms.date 2026-06-15, upd. 2026-10-26, read 2026-11-26 |
| [Get started with Git integration](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-get-started) | Folder/one folder at a time, branch connection steps, update all | ms.date 2026-09-01, upd. 2026-09-29, read 2026-11-26 |
| [Git source code format](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/source-code-format) | "a branch can be synced to multiple workspaces", item folder naming, `logicalId` as identity | ms.date 2025-12-15, upd. 2026-07-21, read 2026-11-26 |
| [Git – Connect](https://learn.microsoft.com/en-us/rest/api/fabric/core/git/connect) | request shape, field limits, `ConfiguredConnection` rules, error codes, throttling | upd. 2026-11-10, read 2026-11-26 |
| [Git – Get Connection](https://learn.microsoft.com/en-us/rest/api/fabric/core/git/get-connection) | returned tuple, `directoryName: ""` at root, connection state | upd. 2026-11-10, read 2026-11-26 |
| [Git – Update From Git](https://learn.microsoft.com/en-us/rest/api/fabric/core/git/update-from-git) | workspace/remote head, SP item-support caveat, conflict resolution | upd. 2026-11-10, read 2026-11-26 |
| [Git – Commit To Git](https://learn.microsoft.com/en-us/rest/api/fabric/core/git/commit-to-git) | `workspaceHead`, commit modes, error codes | upd. 2026-11-10, read 2026-11-26 |
| [Git – Get Status](https://learn.microsoft.com/en-us/rest/api/fabric/core/git/get-status) | status is branch-anchored; conflict and same-changes types | upd. 2026-11-17, read 2026-11-26 |
| [Resolve conflicts](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/conflict-resolution) | conflict definition and per-item resolution | ms.date 2026-06-15, read 2026-11-26 |
| [Development process](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/manage-branches) | one branch per workspace, separate workspace per developer | ms.date 2026-10-18, upd. 2026-10-19, read 2026-11-26 |
| [Development process using branch workspace](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/branched-workspace) | switch-branch override, "must contain the same directory" | ms.date 2026-09-24, upd. 2026-10-29, read 2026-11-26 |
| [Automate Git integration by using APIs](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-automation) | cloud connection shape and `url` scope, SP flow, connection reuse | ms.date 2026-09-24, upd. 2026-09-29, read 2026-11-26 |
| [Automate Git integration with a service principal](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/automate-git-integration-with-service-principal) | SP prerequisites, connection sharing, initialization strategy | ms.date 2026-09-01, upd. 2026-09-29, read 2026-11-26 |
| [Git integration with a service principal (manual)](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-integration-with-service-principal) | ADO organisation and team membership for the SP | ms.date 2026-09-01, upd. 2026-09-29, read 2026-11-26 |
| [Troubleshooting the lifecycle tools](https://learn.microsoft.com/en-us/fabric/cicd/troubleshoot-cicd) | duplicate logical IDs, connect-folder failures, 50 MB commit message | ms.date 2026-09-23, upd. 2026-09-29, read 2026-11-26 |
| [`fabric_workspace_git` resource](https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/resources/workspace_git.md) | ForceNew provider details, leading-slash `directory_name`, `allow_override_items`, SP/`ConfiguredConnection` rule | read 2026-11-26 |

[connect]: https://learn.microsoft.com/en-us/rest/api/fabric/core/git/connect
[get-conn]: https://learn.microsoft.com/en-us/rest/api/fabric/core/git/get-connection
[update]: https://learn.microsoft.com/en-us/rest/api/fabric/core/git/update-from-git
[commit]: https://learn.microsoft.com/en-us/rest/api/fabric/core/git/commit-to-git
[get-status]: https://learn.microsoft.com/en-us/rest/api/fabric/core/git/get-status
[process]: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-integration-process
[get-started]: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-get-started
[format]: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/source-code-format
[conflict]: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/conflict-resolution
[manage-branches]: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/manage-branches
[branched]: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/branched-workspace
[automation]: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-automation
[sp-auto]: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/automate-git-integration-with-service-principal
[sp-manual]: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-integration-with-service-principal
[trouble]: https://learn.microsoft.com/en-us/fabric/cicd/troubleshoot-cicd
[tf-git]: https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/resources/workspace_git.md
