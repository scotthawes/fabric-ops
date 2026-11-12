# Connecting the Fabric MCP servers

**Dated 2026-11-12.** Microsoft ships remote Fabric MCPs; there is no local server to install. This
page records what they are, how they authenticate, and the one failure mode that looks like a bug
but isn't.

## The three servers

From `microsoft/skills-for-fabric` (`.mcp.json`), all over HTTP:

| Name here | URL | What it exposes |
| --- | --- | --- |
| `fabric-powerbi` | `https://api.fabric.microsoft.com/v1/mcp/powerbi/authoring` | Semantic-model / Power BI authoring tools |
| `fabric-sql` | `https://api.fabric.microsoft.com/v1/mcp/dataPlane/sqlEndpoint` | `execute_query` only — the SQL analytics endpoint |
| `fabric-iq` | `https://fabriciq.svc.cloud.microsoft/v1/mcp/fabriciq` | Fabric IQ; requires the `X-VARIANTS: Fabric.Routing.FabricIQ.V1` header |

They are configured in this repository's `opencode.json` as `remote` servers with a shared bearer
header read from a file.

## Authentication

The servers accept an **Azure CLI token for the Fabric resource**. There is no client secret and no
app registration:

```bash
az login --tenant <work-tenant-id> --scope https://api.fabric.microsoft.com/.default
~/.config/opencode/scripts/fabric-token.sh   # writes ~/.secrets/fabric-token
```

Then start a new session — opencode reads the token file at startup. Tokens last roughly 60–90
minutes, so a long Fabric session will expire and need the script rerun plus a restart.

`~/.secrets/fabric-token` is git-ignored by convention and must never be committed.

## The failure mode that is not a bug

If the token is missing, expired, or belongs to a tenant without Fabric access, the server answers
`401` — and opencode then falls back to OAuth discovery. Azure's discovery document contains a
literal `{tenantid}` placeholder, so the fallback fails with:

```
Issuer mismatch in authorization server metadata (RFC 8414 §3.3):
expected "https://login.microsoftonline.com/organizations/v2.0",
received "https://login.microsoftonline.com/{tenantid}/v2.0"
```

Read that as **"no usable token"**, not "the server is broken". Fix the token, not the config.

## What this repository can and cannot verify

The machine this pack was written on is signed into a personal tenant with no Fabric capacity, and
`az account get-access-token --resource https://api.fabric.microsoft.com` fails with *"interactive
authentication is needed"*. So all three servers register correctly and none can connect from here.
They will connect from the work machine, after the login above.

## Write access, deliberately

These servers can mutate a live tenant. In a research repository that is a bigger risk than in the
work repo, so treat tool calls as you would a CLI: read first, and do not let an exploratory question
turn into an `updateDefinition`. The evidence trail in `docs/` assumes nothing was changed by
exploration.
