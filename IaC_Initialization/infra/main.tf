terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.6.0"
    }
  }
}


provider "azurerm" {
  features {}
  subscription_id = var.subscription_id

}

data "azurerm_client_config" "current" {}


resource "azurerm_resource_group" "etl_rg" {
  name     = "rgazdatengtfg"
  location = "East US"

  tags = {
    ENV = "PROD"
  }
}

# Create Storage Account (Data Lake)
resource "azurerm_storage_account" "data_lake" {
  name                     = "stazdatengtfg"
  resource_group_name      = "${azurerm_resource_group.etl_rg.name}"
  location                 = "${azurerm_resource_group.etl_rg.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  is_hns_enabled = true # enable_hierarchical_namespace

  tags = {
    ENV = "PROD"
  }

}


resource "azurerm_storage_data_lake_gen2_filesystem" "data_lake_container" {
  name               = "data"
  storage_account_id = "${azurerm_storage_account.data_lake.id}"
}

# Grant the Synapse workspace Managed Identity access to the Data Lake using Azure RBAC (e.g., Storage Blob Data Contributor role).
resource "azurerm_role_assignment" "datalake_from_synapse" {
  scope                = azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id

}



# Create Azure Synapse Workspace
resource "azurerm_synapse_workspace" "synapse" {
  name                = "synwazdatengtfg"
  resource_group_name = "${azurerm_resource_group.etl_rg.name}"
  location            = "${azurerm_resource_group.etl_rg.location}"
  storage_data_lake_gen2_filesystem_id = "${azurerm_storage_data_lake_gen2_filesystem.data_lake_container.id}"
  sql_administrator_login          = "synapseadmin"
  sql_administrator_login_password = var.synapse_sql_admin

  managed_resource_group_name = "rgmngsynazdatengtfg"


  identity {
    type = "SystemAssigned"
  }

  tags = {
    ENV = "PROD"
  }

  depends_on = [azurerm_role_assignment.datalake_from_synapse]

}


# Spark Pool
resource "azurerm_synapse_spark_pool" "example" {
  name                 = "sparkpool"
  synapse_workspace_id = azurerm_synapse_workspace.synapse.id
  node_size_family     = "MemoryOptimized"
  node_size            = "Small"
  cache_size           = 100

  auto_scale {
    max_node_count = 8
    min_node_count = 3
  }

  auto_pause {
    delay_in_minutes = 5
  }


  spark_config {
    content  = <<EOF
spark.shuffle.spill                true
EOF
    filename = "config.txt"
  }

  spark_version = 3.4

  tags = {
    ENV = "PROD"
  }
}

# SQL Dedicated Pool
resource "azurerm_synapse_sql_pool" "sql_pool" {
  name                = "sqlpool"
  sku_name            = "DW100c"
  synapse_workspace_id = azurerm_synapse_workspace.synapse.id
  storage_account_type = "LRS"
  geo_backup_policy_enabled = false
  tags = {
      ENV = "PROD"
    }

}


resource "azurerm_synapse_workspace_aad_admin" "aad_admin" {
  synapse_workspace_id = azurerm_synapse_workspace.synapse.id
  login                = "AzureAD Admin"
  object_id            = data.azurerm_client_config.current.object_id
  tenant_id            = data.azurerm_client_config.current.tenant_id

}

resource "azurerm_synapse_firewall_rule" "synapse_firewall" {
    name = "MyIP"
    synapse_workspace_id = azurerm_synapse_workspace.synapse.id
    start_ip_address = var.ip_address
    end_ip_address = var.ip_address
}

