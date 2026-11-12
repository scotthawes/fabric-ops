# fabric-ops

> **A dated snapshot, checked 2026-11-12.** Microsoft Fabric changes monthly and previews
> graduate. Every claim in this repository carries the date it was checked; treat anything more
> than a few months old as a question rather than an answer. This is one project's research record,
> written for its own context, not official guidance and not affiliated with Microsoft.

A research pack for deploying and administering **Microsoft Fabric** in a work tenant:
capacities and tenant settings, workspace lifecycle, item deployment, and the users and roles
that see the content.

**Status: research only.** Nothing here deploys. There is no code, no pipeline and no
credential in this repo — by decision, not by accident (`docs/adr/0001-…`). The audience is a
human who carries the findings into the **work repo**, where an Azure DevOps pipeline with a
service connection does the deploying.

## Why this repo exists

The work tenant is not reachable from the machine this repo was created on, and the work is
delivered in a separate repository. So the thing worth building here is the part that
transfers: a defensible answer to *how* the fabric should be deployed, administered and
governed, with sources a colleague can check in five minutes.

Every claim about Fabric behaviour cites Microsoft Learn or an official `microsoft/*`
repository, and carries the date it was checked. Fabric ships monthly and previews graduate,
so an undated claim is a liability.

## What lives where

| Path | Purpose |
| --- | --- |
| `docs/guides/` | The launch decision sheet, plus the automation coverage matrix: what can run unattended, what needs approval, what is manual. |
| `docs/maps/` | The platform drawn once: layers, containment, and where our automation touches each layer. |
| `docs/specs/` | Synthesis documents: what the research concluded, for whoever builds the work repo. Not a plan for this repo. |
| `docs/stakeholder-summary.md` | One page for a manager or architect: the shape, the cost, the four decisions needed from them. |
| `docs/recommendations/` | Four decision-ready one-pagers, in reading order. Start here. |
| `docs/research/` | Cited research notes, one per question. Index in `docs/research/README.md`. |
| `docs/adr/` | Decisions taken here, with the reasoning that outlived the conversation. |
| `docs/runbook/` | Ordered checks to run in the work tenant, since nothing here is verifiable. |
| `docs/reference/` | Illustrative artefacts for the work repo to adapt — YAML, Terraform, naming, layout — plus the generated API census. |
| `docs/ecosystem/` | What exists on GitHub: a curated index plus the full machine-readable sweep. |
| `GLOSSARY.md` | Project vocabulary — Fabric terms plus ours (work tenant, work repo). |
| `AGENTS.md` | Conventions for anyone, human or agent, working in this repo. |

## Reading order

1. [`docs/README.md`](docs/README.md) — the map of the pack: where to start, what is settled, what
   still needs a tenant.
2. [`docs/guides/what-goes-where.md`](docs/guides/what-goes-where.md) — the launch decision sheet:
   Terraform, pipeline, or manual, and the order to run them.
3. [`docs/maps/fabric-system-map.md`](docs/maps/fabric-system-map.md) — the platform in one page,
   with every layer annotated for what we automate and what stays human.
4. `docs/recommendations/01-…` then `02-…`, `03-…`, `04-…` — the design, in the order it
   depends on itself.
2. `docs/adr/` — why each choice was made, and what it costs.
3. `docs/runbook/01-…` — what a human must confirm in the work tenant before any of it is
   trusted.
4. `docs/research/` — only when you want the citation behind a claim.
5. `docs/ecosystem/` — when you need a tool, a sample or a prior art reference, start with
   [`github-index.md`](docs/ecosystem/github-index.md) rather than searching GitHub: it is
   curated, dated, and says which of the popular repos are archived or star-farmed.

## How findings travel

Research note → decision → handover. A note that settles something gets referenced from the
ADR that records the choice; the ADR is what the person building the work repo reads first.
Anything that cannot be automated is written down as a procedure, because the alternative is
explaining it again in three months.

## Out of scope

- Deploying from here, in any form. No credentials to the work tenant, no service connection.
- Restating the Microsoft documentation. Notes answer questions and record what the docs do
  *not* say.
- Being the work repo. The work repo owns the pipeline, the Terraform state and the
  environment topology; this one suggests and cites.
