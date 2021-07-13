# Log into an Azure tenant using a service principal
az login --service-principal -u $ARM_CLIENT_ID -p $ARM_CLIENT_SECRET --tenant $ARM_TENANT_ID

# Create a new Azure resource group
$rsgExists = az group exists -n $STATE_RG_NAME
if ($rsgExists -eq 'false') {
    az group create -l $LOCATION -n $STATE_RG_NAME
}

# Create a new blob storage account
az storage account create -n $STATE_STOR_NAME -g $STATE_RG_NAME -l $LOCATION --sku Standard_LRS

# Create a container into the newly created storage account
az storage container create -n $CONTAINER_NAME -g $STATE_RG_NAME --account-name $STATE_STOR_NAME
