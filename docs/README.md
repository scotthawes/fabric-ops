# docs/

The map of this pack. Everything here is research, decision or synthesis — nothing deploys.

## Where to start

| If you want… | Read |
| --- | --- |
| To know what to build and what to do by hand | [`guides/what-goes-where.md`](guides/what-goes-where.md) |
| To know what Fabric will let you automate | [`guides/automation-coverage.md`](guides/automation-coverage.md) |
| The platform's shape in one page | [`maps/fabric-system-map.md`](maps/fabric-system-map.md) |
| The design argued, area by area | [`recommendations/`](recommendations/) — 01 identity, 02 capacity, 03 deployment, 04 governance |
| The decisions and what they cost | [`adr/`](adr/) — 0001 to 0008 |
| What a human must verify in the tenant | [`runbook/01-work-tenant-checklist.md`](runbook/01-work-tenant-checklist.md) |
| How the described platform behaves once running | [`runbook/02-steady-state.md`](runbook/02-steady-state.md), from [`specs/0002`](specs/0002-platform-operations.md) |
| Artefacts to adapt for the work repo | [`reference/`](reference/) — pipeline YAML, Terraform, naming, layout, API census |
| Which API surfaces we have actually collected | [`reference/api-surface-coverage.md`](reference/api-surface-coverage.md) |
| Which platforms we depend on, and what is unverified | [`reference/platform-operations-register.md`](reference/platform-operations-register.md) |
| The evidence behind a claim | [`research/`](research/) — one note per question, each dated and cited; the [index](research/README.md) is the list |
| Something for a manager | [`stakeholder-summary.md`](stakeholder-summary.md) |
| How to connect an AI agent to Fabric | [`guides/fabric-mcp.md`](guides/fabric-mcp.md) |

## The three kinds of document here

- **Research** (`research/`) answers one question against Microsoft's own pages, and says what it
  could not establish. It is allowed to be wrong and then corrected — several notes carry dated
  correction sections where a later note overturned them.
- **Decisions** (`adr/`) record a choice and its cost. If a decision is reversible cheaply, it is not
  an ADR. ADR 0001 says why this repository holds no code.
- **Synthesis** (`guides/`, `maps/`, `recommendations/`, `specs/`) is the compressed form for someone
  who will not read the research. Synthesis is allowed to be incomplete, but must say so — the
  automation matrix lists what it has not assessed rather than implying completeness.

## What is settled, and what is not

**Settled:** the mechanism split (Terraform for containers, `fabric-cicd` for definitions, humans for
relationships), the identity model, the promotion model, the capacity decision, the access model, and
the automation verdicts for roughly 50 action families and all 825 API operations.

**Not settled, and not settleable by reading:** the open questions in
[`research/backlog.md`](research/backlog.md) — whether a service principal needs a licence, whether an
SP can hold capacity Contributor, whether a group of only SPs satisfies the admin API allow-lists,
what the tenant's network posture actually is, and similar. Each needs a tenant, a billing answer, or
a Learn page that does not exist yet. Nothing in this pack should be treated as final until they are
answered.

**And a floor under that:** some of those questions can only be answered by *performing a deployment*,
which this project will never do — research-only is the charter, not a waiting room
([ADR 0001, amendment 2026-11-12](adr/0001-research-artefact-not-deployment-tool.md)). For those, no
answer is coming. The surrounding claims are the pack's best reading of the documentation and are
labelled as such; read them as "established by documentation, unverified in a tenant", and do not wait
for a confirmation that will not arrive.

## Maintaining it

- One question per research file; one decision per ADR; never renumber either.
- Date every claim, and date corrections rather than silently rewriting (see the correction blocks in
  `research/gateway-and-connectivity.md`, `governance-access-and-workspace-roles.md` and
  `sensitivity-labels-lifecycle.md`).
- When a note changes a decision, amend the ADR — a note without an ADR update is how two documents
  start disagreeing.
- Regenerate the API census rather than editing it: `python3 reference/refresh-api-operations.py`.
- The conventions agents follow are in [`../AGENTS.md`](../AGENTS.md).
