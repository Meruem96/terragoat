# Terragoat

![terragoat-logo](https://user-images.githubusercontent.com/61518622/110116638-0ff37500-7db8-11eb-94f6-8e7151f0112a.png)

## Important notes

* Where to get help: the [Bridgecrew Community Slack](https://slack.bridgecrew.io/?utm_source=github&utm_medium=organic_oss&utm_campaign=terragoat) </br>

TerraGoat is Bridgecrew's "Vulnerable by Design" Terraform repository.</br>

This TerraGoat's version is designed to be deployed on free subscription account.

Before you proceed please take a not of these warning: </br>

>**⚠️ TerraGoat creates intentionally vulnerable resources into your account. DO NOT deploy TerraGoat in a production environment or alongside any sensitive resources.**

## Requirements

### **Azure portal**</br>

* Cloud shell (top right)
* On the azure command line select 'PowerShell' and change it by bash on the top left.

### **Other**

* A shell with:</br>
  * [_installation_](https://learn.hashicorp.com/tutorials/terraform/install-cli) Terraform 0.12
  * [_installation_](https://docs.microsoft.com/fr-fr/cli/azure/install-azure-cli) azure cli
  * [_installation_](https://git-scm.com/book/fr/v2/D%C3%A9marrage-rapide-Installation-de-Git) git


## Setup

### Clone repo

```bash
git clone https://github.com/Meruem96/terragoat.git
```

### Create an Azure Storage Account backend to keep Terraform state

>* ⚠️ A storage account **must have** a unique name whatever the subscription.
> change this line: **_export TERRAGOAT_STATE_STORAGE_ACCOUNT="mydevsecopssa"_** by adding 4+ random digits+letters at the end to avoid errors

```bash
#!/bin/bash
export TERRAGOAT_RESOURCE_GROUP="TerraGoatRG"
export TERRAGOAT_STATE_STORAGE_ACCOUNT="mydevsecopssa"
export TERRAGOAT_STATE_CONTAINER="mydevsecops"
export TF_VAR_environment="dev"
export TF_VAR_region="westus"

# Connect your account
az login

# Create resource group
az group create --location $TF_VAR_region --name $TERRAGOAT_RESOURCE_GROUP

# Create storage account
az storage account create --name $TERRAGOAT_STATE_STORAGE_ACCOUNT --resource-group $TERRAGOAT_RESOURCE_GROUP --location $TF_VAR_region --sku Standard_LRS --kind StorageV2 --https-only true --encryption-services blob

# Get storage account key
ACCOUNT_KEY=$(az storage account keys list --resource-group $TERRAGOAT_RESOURCE_GROUP --account-name $TERRAGOAT_STATE_STORAGE_ACCOUNT --query [0].value -o tsv)

# Create blob container
az storage container create --name $TERRAGOAT_STATE_CONTAINER --account-name $TERRAGOAT_STATE_STORAGE_ACCOUNT --account-key $ACCOUNT_KEY
```

### Apply TerraGoat

```bash
# Enter in the git directory you cloned
cd terragoat

# Init TerraGoat
terraform init -reconfigure -backend-config="resource_group_name=$TERRAGOAT_RESOURCE_GROUP" \
    -backend-config "storage_account_name=$TERRAGOAT_STATE_STORAGE_ACCOUNT" \
    -backend-config="container_name=$TERRAGOAT_STATE_CONTAINER" \
    -backend-config "key=$TF_VAR_environment.terraform.tfstate"

# Apply
terraform apply
```

* **Apply takes ≈ 10 minutes**

### Remove TerraGoat

```bash
terraform destroy

# Delete resource group
az group delete --name $TERRAGOAT_RESOURCE_GROUP
```

>* ⚠️ If an error occured during destroyment like: _Error: deleting Key "terragoat-generated-certificate-dev" [...]_ just do it again:

```bash
terraform destroy
```

## Logs

In analyse purpose, logs can be found in '.logs' folder

* setupoutput.log :: every resource created with azure cli

## Possible errors

### For every possible error listed bellow, restart the script

* Error: retrieving **contact** for KeyVault
* Error 'loading state': Error retrieving keys for Storage Account

## Easy way

```bash
git clone https://github.com/Meruem96/terragoat.git
cd terragoat
bash setup.sh init
```
