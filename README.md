# fabric-ops

Research and tooling for deploying and administering **Microsoft Fabric**: provisioning
workspaces and their items, and managing the content and users of the platform.

**Status: scoping.** The design is being settled by interview before any code is written.
Open decisions live in the grilling thread; settled ones land in `GLOSSARY.md` and
`docs/adr/`.

## What lives where

| Path | Purpose |
| --- | --- |
| `docs/research/` | Cited research notes, one file per question. Index in `docs/research/README.md`. |
| `docs/adr/` | Architecture decision records — one file per hard-to-reverse decision. |
| `GLOSSARY.md` | The project's Fabric vocabulary, so terms stop drifting. |
| `AGENTS.md` | Conventions for agents (and humans) working in this repo. |

## Ground rules

- **No unverified Fabric claim.** Tenant settings, API limits, permission models and role
  names are the things we most often get wrong from memory. Every such claim in
  `docs/research/` carries a link to Microsoft Learn.
- **Research feeds decisions, not code.** A research note ends in what it settles, what it
  rules out, and what it leaves open.
- **Nothing here is a replacement for the portal.** Anything one-off or unrepeatable is
  documented, not automated.

## Not yet decided

Language and deployment mechanism (REST + `fabric-cicd`, Fabric Git integration and
deployment pipelines, or a Terraform provider), the identity used by automation, and the
environment topology. See the grilling thread.
