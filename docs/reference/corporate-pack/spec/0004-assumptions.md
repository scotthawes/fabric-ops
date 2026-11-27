# 0004 — Assumptions, probes and fallbacks

**Pack: 2026-11-27.1 · illustrative, not runnable from fabric-ops (ADR 0001)**

**Dated 2026-11-26.** The corporate machine cannot answer questions: there is no report channel, and
asking the tenant would breach the rules under which this pack exists. So every fact the pack cannot
know is handled three ways, in this order:

1. **Assume the safe branch** — the option that still works if the answer is the unfavourable one.
2. **Probe it** — a read-only check the pipeline runs, which fails with a named code.
3. **Ship the fallback** — the alternative path is already written, not promised.

A question that is answered by none of the three is not a gap in the pack; it is a gap in the
destination and belongs in [`0003-open-questions.md`](0003-open-questions.md) as explicitly out of
scope.

## What changed to absorb the unknowns

| Was assumed | Now assumed by default | Why |
| --- | --- | --- |
| The admin SP creates the Fabric domains | **A human creates the domains; the pipeline assigns workspaces through the Core API** (`scripts/assign_domains.py`). Terraform domain creation is an optional root, off by default. | Removes the dependence on whether an SP can hold Fabric administrator. The Core path needs only workspace admin plus domain contributor/admin. |
| A scheduled pause is available on nonprod | **No scheduled pause anywhere.** Pause is a manual, out-of-band action. | Removes #19 (refresh behaviour when paused) and #20 (reservation billing while paused) from the design. |
| The capacity's overage default can be relied on | **Overage is written explicitly** through `azapi` after creation, then read back. | Removes #23 (what a Terraform-created capacity defaults to). |
| The admin SP holds capacity Contributor | **The SP is a capacity administrator** through `administration_members`. | Removes #15; the provider documents the member as a user or service principal. |
| Viewers may read on a Free licence at F64 | **Every viewer is assumed to hold Pro or PPU.** F64's Free-viewer benefit is a bonus, not a dependency. | Removes the licence cliff from the sizing decision. |
| The SP can create ADO repositories | **A human creates one repository per nonprod workspace** from a template; the pipeline only binds. | Repository-create permission is not documented for an SP. |
| A service principal needs no Fabric licence | **Assumed none**, with a mapped 401/403 that names the licence action. | Absence of a stated requirement is the only evidence; the probe catches the contrary. |

## The assumption table

| ID | Question | Assumption adopted | Probe (read-only) | If the probe disagrees |
| --- | --- | --- | --- | --- |
| OQ-01 | SP Fabric licence (#14) | No licence needed | `GET /v1/capacities` as the SP | `PROBE-LICENCE`: assign Pro/PPU to the SP (human), rerun |
| OQ-02 | SP capacity Contributor (#15) | Not needed; admin membership | `GET /v1/capacities` returns both capacities | `PROBE-CAPACITY`: check `administration_members` |
| OQ-03 | Refresh while paused (#19) | Never auto-pause | none — policy | A human pause is a separate, documented operation |
| OQ-04 | Reservation billing while paused (#20) | No reservation; never auto-pause | none — policy | If finance reports a reservation, pause stays unavailable |
| OQ-05 | Overage default (#23) | Set explicitly after create | `azapi` read of `properties.overage` | the read-back is the check; re-apply the explicit setting |
| OQ-06 | SP may hold Fabric administrator | **Assume no** | `GET /v1/admin/domains` | `PROBE-ADMIN`: domains stay human-created; Core assignment is already the default |
| OQ-07 | SP may create ADO repositories | Assume no | none — process | Human creates the repository from the template in run-book 00 |
| OQ-08 | Graph consent granted | Assume yes, granted in bootstrap | `GET /groups?$top=1` (read) | `PROBE-GRAPH`: the consent step is incomplete; group create will 403 |
| OQ-09 | 64-CU quota for F64 | Assume available | capacity create returns; quota error otherwise | a quota error at capacity create: request quota, or start at F32 and record the licensing change |
| OQ-10 | Viewers hold Pro/PPU | Assume yes | none — policy | If not, prod viewers cannot read; that is a licensing purchase, not a pack change |
| OQ-11 | DR posture | Not promised | none | Out of scope; see `business-continuity-what-does-fabric-guarantee.md` |

## What the pipeline probes

A `Probe` stage runs before `Platform`, with no environment and no state. It writes `probe.json` and
fails with one code per missing prerequisite:

| Code | Check | Blocks |
| --- | --- | --- |
| `PROBE-AUTH` | ARM token; `az account show` | everything |
| `PROBE-FABRIC` | `GET /v1/capacities` | Platform and everything after |
| `PROBE-DOMAINS` | `GET /v1/domains` | the optional domains root and the assignment job |
| `PROBE-GRAPH` | `GET /groups?$top=1` | Nonprod group creation |
| `PROBE-PROVIDER` | `Microsoft.Fabric` registration state | Platform |
| `PROBE-ADMIN` | `GET /v1/admin/domains` (expected 403) | nothing — it *selects* the domain path |

`PROBE-ADMIN` is the one probe whose failure is information: a 403 confirms A6 and the pipeline uses
the Core assignment path. A 200 means the optional Terraform domain root may be enabled, but nothing
depends on it.

## What is deliberately not probed

- **Anything that writes.** No scratch group, no test workspace, no `assignToDomain` call. A probe
  that creates an object is a deployment.
- **Billing and reservations.** No read-only API is documented for the reservation terms; the policy
  is "do not pause", which makes the answer irrelevant.
- **Tenant settings.** A tenant setting is observed by its effect (the API call succeeding), not by
  reading the admin portal. `PROBE-FABRIC` is the effect.
- **Viewer licences.** Reading licence assignments is a Graph query against users, not a Fabric
  question; the design assumes Pro/PPU and never depends on the answer.

## The rule for a future finding

If the corporate session discovers a fact that contradicts an assumption, it changes behaviour in
**one** place: the matching probe or the policy row above. It does not reopen a decision, and it does
not require a question back to this repository. A finding that cannot be expressed as a probe, a
policy or a fallback is out of scope for this pack.
