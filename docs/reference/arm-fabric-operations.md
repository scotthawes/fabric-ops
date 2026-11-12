# ARM surface for Fabric: 13 operations

**Dated 2026-11-12**, from `Azure/azure-rest-api-specs` at
`specification/fabric/resource-manager/Microsoft.Fabric/Fabric/preview/2026-09-01-preview/fabric.json`.
Operations in [`arm-fabric-operations.tsv`](arm-fabric-operations.tsv).

This is the *Azure resource* half of Fabric — the capacity as an ARM resource. It is a separate
surface from `api.fabric.microsoft.com`, with a different base path, a different token audience
(ARM, not Fabric) and a different provider (`Microsoft.Fabric`, not `microsoft/fabric`).

## The operations

| Method | Operation | What it does |
| --- | --- | --- |
| `GET` | `Operations_List` | The provider's own operations list |
| `GET` | `FabricCapacities_ListBySubscription` | All capacities in the subscription |
| `GET` | `FabricCapacities_ListByResourceGroup` | Capacities in a resource group |
| `GET` | `FabricCapacities_Get` | One capacity, including `properties.state` |
| `PUT` | `FabricCapacities_CreateOrUpdate` | Create or replace a capacity |
| `PATCH` | `FabricCapacities_Update` | Update a capacity in place |
| `DELETE` | `FabricCapacities_Delete` | Delete the capacity — the point of no return |
| `POST` | `FabricCapacities_Suspend` | Pause; bills the accrued smoothed backlog |
| `POST` | `FabricCapacities_Resume` | Resume; resumes billing |
| `POST` | `FabricCapacities_CheckNameAvailability` | Name collision check |
| `GET` | `FabricCapacities_ListSkus` | SKUs available in a location |
| `GET` | `FabricCapacities_ListSkusForCapacity` | SKUs a given capacity can move to |
| `GET` | `FabricCapacities_ListUsages` | Quota usage in a location — the CU quota check |

## The correction this surface forces

**Capacity overage is settable through ARM.** The capacity note said overage is "not configurable
through AzureRM", which is true — AzureRM is pinned to API `2023-11-01`. But the preview API version
models it explicitly:

- `FabricCapacityProperties.overage` → `CapacityOverageProperties`
- `FabricCapacityUpdateProperties.overage` → the same shape

So the accurate statement is: **not expressible in `azurerm_fabric_capacity`, but expressible in an
ARM deployment at `2026-09-01-preview`** — which is what `azapi_resource` exists for. That moves
overage from "portal-only" to "automatable with a preview API and an escape hatch", and it is exactly
the kind of finding the earlier note could not produce because it only read the Terraform provider.

It also explains the split cleanly:

| Want | Surface |
| --- | --- |
| Stable, supported, in `terraform plan` | `azurerm_fabric_capacity` (API `2023-11-01`) — no overage |
| Overage, other preview properties | ARM `2026-09-01-preview` via `azapi_resource` |
| Suspend / resume | ARM action, either way |

## What this settles

The capacity lifecycle is **fully automatable** — create, update, delete, suspend, resume, overage —
across two mechanisms: the stable AzureRM resource and a preview ARM escape hatch. What remains
genuinely manual is the *decision*, not the act: what SKU, what overage threshold, when to pause.

## What this does not establish

- Whether AzureRM has since added an overage argument, or whether the `2026-09-01-preview` properties
  survive to a stable version.
- Whether `PATCH` can change `sku.name` in place or forces replacement.
- The exact `CapacityOverageProperties` fields — the model exists in the spec, but this census did not
  read its schema.
