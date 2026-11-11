# Research notes

One question per file. The point is a defensible answer with a link, not a summary of the
docs.

## Index

| Note | Question it answers | Status |
| --- | --- | --- |
| [`deployment-mechanism-comparison.md`](deployment-mechanism-comparison.md) | Which way should a repo deploy and promote Fabric content, given it must also administer workspace users and roles? | answered 2026-11-11 |

## Adding a note

1. Copy `TEMPLATE.md` to `<topic>-<question>.md`.
2. Answer the question, citing Microsoft Learn or the official `microsoft/*` repo next to
   each claim that matters.
3. Fill in "What this settles" and "What this does not establish". A note with no
   "does not establish" section is usually overconfident.
4. Add a row to the index above.

## Open questions

Collected during grilling; promoted to a note when they start blocking a decision.

- Which Fabric items can round-trip through Git integration, and which cannot?
- What exactly does the deployment-pipeline API let you do that Git integration does not?
- Which admin operations need tenant admin versus workspace Admin?
- What is the current state of the Fabric Terraform provider?
- How do service principals get authorised for the admin APIs, and what breaks when they
  are not?
