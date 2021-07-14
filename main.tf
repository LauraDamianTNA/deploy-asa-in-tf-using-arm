# Create a resource group for below resources
resource "azurerm_resource_group" "rgsa" {
  name     = "stream-analytics-rg"
  location = var.LOCATION
}

# Create an Azure Event Hub Namespace and corresponding Event Hub for data input into Azure Stream Analytics
resource "azurerm_eventhub_namespace" "ehnamespace" {
  name                = "ldinput-event-hub-namespace"
  location            = var.LOCATION
  resource_group_name = var.RG_NAME
  sku                 = "Standard"
}

resource "azurerm_eventhub" "eh" {
  name                = "ldinput-event-hub"
  namespace_name      = azurerm_eventhub_namespace.ehnamespace.name
  resource_group_name = var.RG_NAME
  partition_count     = 2
  message_retention   = 1
}

resource "azurerm_eventhub_consumer_group" "ehconsumergroup" {
  name                = "ldinput-event-hub-consumer-group"
  namespace_name      = azurerm_eventhub_namespace.ehnamespace.name
  eventhub_name       = azurerm_eventhub.eh.name
  resource_group_name = var.RG_NAME
}

resource "azurerm_eventhub_authorization_rule" "ehsend" {
  name                = "ldinput-event-hub-authorization"
  namespace_name      = azurerm_eventhub_namespace.ehnamespace.name
  eventhub_name       = azurerm_eventhub.eh.name
  resource_group_name = var.RG_NAME
  listen              = false
  send                = true
}

# Generate a random password
resource "random_password" "dbpassword" {
  length           = 17
  special          = true
  min_special      = 1
  min_numeric      = 1
  min_upper        = 1
  min_lower        = 1
  override_special = "$%&-_+{}<>"
}

# Create an Azure SQL Database to store reference data
resource "azurerm_sql_server" "sqlserver" {
  name                         = "ldsqlserver-refdata-event-hub"
  resource_group_name          = var.RG_NAME
  location                     = var.LOCATION
  version                      = "12.0"
  administrator_login          = var.administrator_login
  administrator_login_password = random_password.dbpassword.result
}

resource "azurerm_sql_database" "sqldb" {
  name                = "sqldb-refdata-eventhub"
  resource_group_name = var.RG_NAME
  location            = var.LOCATION
  server_name         = azurerm_sql_server.sqlserver.name
}

# Create an Azure Service Bus Namespace and Topic for data output
resource "azurerm_servicebus_namespace" "sb" {
  name                = "ldservicebus-output"
  location            = var.LOCATION
  resource_group_name = var.RG_NAME
  sku                 = "Standard"
}

resource "azurerm_servicebus_topic" "sbtopic" {
  name                = "ldsb-output-topic"
  resource_group_name = var.RG_NAME
  namespace_name      = azurerm_servicebus_namespace.sb.name
}

resource "azurerm_servicebus_topic_authorization_rule" "sbtopicauthrulewrite" {
  name                = "ldsb-output-topic-auth-rule-write"
  namespace_name      = azurerm_servicebus_namespace.sb.name
  topic_name          = azurerm_servicebus_topic.sbtopic.name
  resource_group_name = var.RG_NAME
  listen              = false
  send                = true
  manage              = false
}

# Create an Azure blob storage account for Azure Stream Analytics
resource "azurerm_storage_account" "ehstor" {
  name                     = "ldehstorage1"
  resource_group_name      = var.RG_NAME
  location                 = var.LOCATION
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

# Define ARM deployment template for the Azure Stream Analytics deployment
resource "azurerm_resource_group_template_deployment" "azure_stream_analytics" {
  name                = "azure_stream_analytics"
  resource_group_name = var.RG_NAME
  deployment_mode     = "Incremental"
  parameters_content = jsonencode({
    "parameterBlock" : {
      "value" : {
        "asa_query" : file("${path.module}/stream-analytics/asaquery.asaql")
        "name" : "azure_stream_analytics"
        "location" : var.LOCATION
        "server" : azurerm_sql_server.sqlserver.name
        "database" : azurerm_sql_database.sqldb.name
        "user" : var.administrator_login
        "password" : random_password.dbpassword.result
        "referenceQuery" : file("${path.module}/stream-analytics/referencequery.snapshot.sql")
        "refreshRate" : "00:05:00"
        "streamingUnits" : 1
        "eh_consumer_group_name" : azurerm_eventhub_consumer_group.ehconsumergroup.name
        "eh_name" : azurerm_eventhub.eh.name
        "eh_namespace" : azurerm_eventhub_namespace.ehnamespace.name
        "eh_sharedAccessPolicyName" : azurerm_eventhub_authorization_rule.ehsend.name
        "eh_sharedAccessPolicyKey" : azurerm_eventhub_authorization_rule.ehsend.primary_key
        "sb_namespace" : azurerm_servicebus_namespace.sb.name
        "sb_sharedAccessPolicyName" : azurerm_servicebus_topic_authorization_rule.sbtopicauthrulewrite.name
        "sb_sharedAccessPolicyKey" : azurerm_servicebus_topic_authorization_rule.sbtopicauthrulewrite.primary_key
        "sb_topic_name" : azurerm_servicebus_topic.sbtopic.name
        "sa_accountName" : azurerm_storage_account.ehstor.name
        "sa_accountKey" : azurerm_storage_account.ehstor.primary_access_key
      }
    }
  })
  template_content = file("${path.module}/stream-analytics/asa-template.json")
}
