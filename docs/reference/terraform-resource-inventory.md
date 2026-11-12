# Terraform resource inventory

**Dated 2026-11-12**, against `microsoft/fabric` **v1.15.1** and `azurerm` **5.13.0**. Source:
[`terraform-provider-surface.md`](../research/terraform-provider-surface.md), which checked the
`v1.15.1` tag rather than `main`.

Two lists, because they answer different questions:

- **§1 is our design** — what the work repo actually manages, per
  [ADR 0003](../adr/0003-terraform-control-plane-fabric-cicd-items.md) and
  [ADR 0007](../adr/0007-terraform-layout-and-pinning.md). Short.
- **§2 is the whole surface** — all 71 `microsoft/fabric` resources plus the `azurerm` one. Long,
  and most of it we deliberately do not use.

## 1. What our design deploys

### Root `terraform/capacity` (own state)

| Resource | Provider | Notes |
| --- | --- | --- |
| `azurerm_resource_group` | azurerm | Holds the capacity |
| `azurerm_fabric_capacity` | azurerm | The F SKU. `name`, `location`, `resource_group_name` are ForceNew; API `2023-11-01`; SKUs `F2`–`F2048`; no suspend/resume, no overage |

### Root `terraform/workspaces` (state key per environment)

| Resource | Provider | Notes |
| --- | --- | --- |
| `data "fabric_capacity"` | `microsoft/fabric` | Data source, not a resource — the capacity GUID the workspace needs |
| `fabric_workspace` | `microsoft/fabric` | One per environment; `capacity_id` is a **Fabric GUID**, not the ARM ID |
| `fabric_workspace_role_assignment` | `microsoft/fabric` | One per workspace group, `Contributor`; Admin stays with named humans |
| `fabric_workspace_git` | `microsoft/fabric` | Dev only; active binding, no import path |

### Optional, and why

| Resource | Would manage | Why it is optional |
| --- | --- | --- |
| `fabric_tenant_setting` | One setting by `setting_name` | Riskiest resource in the provider: tenant-wide, no `import`, `delete_behaviour` defaults to `NoChange`. Only assert settings you intend to own forever |
| `fabric_connection` | A cloud connection, including a `WorkspaceIdentity` credential | Useful once a gated source exists; creating it does not bind it to an item |
| `fabric_shortcut` | A shortcut in a lakehouse | Needs `item_id` of the lakehouse, so it must follow item deployment |
| `fabric_item_job_scheduler` | A schedule on an item job | Schedules are not part of a definition, so this is the only way to version them |

### Deliberately not in Terraform

Items. `fabric-cicd` owns definitions ([ADR 0003](../adr/0003-terraform-control-plane-fabric-cicd-items.md)),
and an item resource fighting a `fabric-cicd` deploy over the same definition is a fault, not a
feature. Also not in Terraform: overage threshold, surge protection, pause/resume, and gateway
bindings — none are expressible or safe.

## 2. Everything `microsoft/fabric` v1.15.1 offers

71 resources and 136 data sources. `(prev)` = preview-gated; `(no SP)` = no service-principal
support. There is **no** `fabric_capacity` resource — capacity is a data source only.

### Control plane — 33 resources

| | | |
| --- | --- | --- |
| `fabric_workspace` | `fabric_workspace_role_assignment` | `fabric_workspace_git` |
| `fabric_workspace_network_communication_policy` | `fabric_workspace_inbound_azure_resource_rules` | `fabric_workspace_outbound_cloud_connection_rules` |
| `fabric_workspace_outbound_gateway_rules` | `fabric_workspace_git_outbound_policy` | `fabric_workspace_firewall_rules` |
| `fabric_workspace_managed_private_endpoint` | `fabric_workspace_encryption` (prev) | `fabric_domain` |
| `fabric_domain_role_assignments` | `fabric_domain_workspace_assignments` (prev) | `fabric_tenant_setting` |
| `fabric_tag` | `fabric_folder` (prev) | `fabric_onelake_data_access_security` (prev) |
| `fabric_connection` | `fabric_connection_role_assignment` | `fabric_gateway` |
| `fabric_gateway_role_assignment` | `fabric_deployment_pipeline` | `fabric_deployment_pipeline_role_assignment` |
| `fabric_spark_workspace_settings` | `fabric_spark_custom_pool` | `fabric_spark_environment_settings` |
| `fabric_warehouse_sql_audit_settings` | `fabric_org_app` | `fabric_org_app_audience` |
| `fabric_external_data_share` | `fabric_item_job_scheduler` | `fabric_shortcut` |

### Item resources — 38, each managing a shell

| Domain | Resources |
| --- | --- |
| Analytics (14) | `fabric_lakehouse`, `fabric_warehouse`, `fabric_warehouse_snapshot` (prev), `fabric_sql_database`, `fabric_snowflake_database`, `fabric_mirrored_database`, `fabric_mirrored_catalog` (prev), `fabric_mirrored_azure_databricks_catalog` (prev), `fabric_cosmos_db`, `fabric_mounted_data_factory`, `fabric_eventhouse`, `fabric_kql_database`, `fabric_kql_queryset`, `fabric_kql_dashboard` |
| Engineering (9) | `fabric_notebook`, `fabric_environment`, `fabric_spark_job_definition`, `fabric_apache_airflow_job`, `fabric_data_pipeline`, `fabric_copy_job`, `fabric_dataflow`, `fabric_variable_library`, `fabric_user_data_function` (prev, no SP) |
| Real-time (9) | `fabric_eventstream`, `fabric_activator` (prev), `fabric_map` (prev), `fabric_ontology` (prev), `fabric_digital_twin_builder` (prev, no SP), `fabric_digital_twin_builder_flow` (prev), `fabric_graphql_api`, `fabric_data_agent`, `fabric_operations_agent` (prev, no SP) |
| BI and ML (6) | `fabric_semantic_model`, `fabric_report`, `fabric_paginated_report`, `fabric_ml_model`, `fabric_ml_experiment`, `fabric_anomaly_detector` (prev, no SP) |

### Data sources worth knowing

136 of them: every resource has a singular data source, 65 have a plural list read, and eleven exist
with **no** resource: `fabric_capacity`, `fabric_capacities`, `fabric_dashboards`, `fabric_datamarts`,
`fabric_mirrored_warehouses`, `fabric_sql_endpoints`, `fabric_lakehouse_table`,
`fabric_lakehouse_tables`, `fabric_eventstream_source_connection`,
`fabric_eventstream_destination_connection`, `fabric_onelake_data_access_securities`.

The plural reads (`fabric_workspaces`, `fabric_notebooks`, `fabric_tenant_settings`, …) are how you
inventory something you did not create — including the seven item types that cannot be deployed at
all.

## 3. Two gates that change the list

- **`preview = true` is provider-wide.** Setting it in a root enables every preview resource in that
  root, which is why [ADR 0007](../adr/0007-terraform-layout-and-pinning.md) isolates preview
  resources rather than mixing them with production containers.
- **Four resources refuse service principals** — `fabric_user_data_function`,
  `fabric_digital_twin_builder`, `fabric_operations_agent`, `fabric_anomaly_detector`. All are
  preview, and the docs say "Please use a User context", which rules them out of an unattended
  pipeline entirely.
