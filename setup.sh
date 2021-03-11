#!/bin/bash
export TERRAGOAT_RESOURCE_GROUP="TerraGoatRG"
export TERRAGOAT_STATE_STORAGE_ACCOUNT="terragoatmodsa"
export TERRAGOAT_STATE_CONTAINER="mydevsecops"
export TF_VAR_environment="dev"
export TF_VAR_region="westus"
outfile=".log/"


# Create resource group
echo -n "Resource group ..."
az group create --location $TF_VAR_region --name $TERRAGOAT_RESOURCE_GROUP >> $outfile"/setupoutput.log" && echo "OK"
exit
# Create storage account
az storage account create --name $TERRAGOAT_STATE_STORAGE_ACCOUNT --resource-group $TERRAGOAT_RESOURCE_GROUP --location $TF_VAR_region --sku Standard_LRS --kind StorageV2 --https-only true --encryption-services blob >> $outfile"setupoutput.log" && echo "Storage account ...OK"

# Get storage account key
echo -n "Storage account key ..."
ACCOUNT_KEY=$(az storage account keys list --resource-group $TERRAGOAT_RESOURCE_GROUP --account-name $TERRAGOAT_STATE_STORAGE_ACCOUNT --query [0].value -o tsv) >> $outfile"setupoutput.log" && echo "OK"

# Create blob container
echo -n "Blob container ..."
az storage container create --name $TERRAGOAT_STATE_CONTAINER --account-name $TERRAGOAT_STATE_STORAGE_ACCOUNT --account-key $ACCOUNT_KEY >> $outfile"setupoutput.log" && echo "OK"

# Fetch object_id
objectId=$(az ad signed-in-user show --query objectId)
if [ -f "variables.tf" ] && [ $(cat "variables.tf" | grep 'object_id' | wc -l) -eq 1 ]
then
        echo "objectId variable already exists."
else
        echo -n "Pushing objectId into variables.tf ..."
        echo '
variable "object_id" {
  type        = string
  description = "The object ID of the current user"
  default     = '$objectId'
}' >> variables.tf && echo "OK"
fi


echo -n "Terraform init ..."
terraform init -reconfigure -backend-config="resource_group_name=$TERRAGOAT_RESOURCE_GROUP" \
    -backend-config "storage_account_name=$TERRAGOAT_STATE_STORAGE_ACCOUNT" \
    -backend-config="container_name=$TERRAGOAT_STATE_CONTAINER" \
    -backend-config "key=$TF_VAR_environment.terraform.tfstate" >> $outfile"setupoutput.log && echo "OK"


if ! [ -d .logs ]; then
    mkdir .logs
fi
echo -n "Exporting plan ..."
terraform plan > .logs/tfplan && echo "OK"

read -p "Apply ? (Launch scripts = create the environement) [Y/N] " resp
if [ "$resp" == "Y" ] || [ "$resp" == "y" ] || [ "$resp" == "yes" ] || [ "$resp" == "Yes" ]
then
    terraform apply .logs/tfplan

fi



read -p "Destroy ? (Erase everything you just created)[Y/N] " resp
if [ "$resp" == "Y" ] || [ "$resp" == "y" ] || [ "$resp" == "yes" ] || [ "$resp" == "Yes" ]
then
    terraform destroy -auto-approve
    az group delete --resource-group $TERRAGOAT_RESOURCE_GROUP --yes
    az group delete --resource-group "terragoat-"$TF_VAR_environment --yes 
    az group delete --resource-group "NetworkWatcherRG" --yes
fi

