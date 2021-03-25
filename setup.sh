#!/bin/bash
export TERRAGOAT_RESOURCE_GROUP="TerraGoatRG"
export TERRAGOAT_STATE_CONTAINER="mydevsecops"
export TERRAGOAT_STATE_STORAGE_ACCOUNT="terragoatmodsa"
export TF_VAR_environment="dev"
export TF_VAR_region="westus"
racine=".logs/"
setupoutput=$racine"setupoutput.log"
tfplan=$racine"tfplan"

#### OPTION MESSAGE
echo -e "Usage:"
echo -e "\tStart setup process: bash setup.sh [apply / -a]"
echo -e "\tDestroy environment: bash setup.sh [destroy / -d]"
echo -e "\tPurge environment  : bash setup.sh [purge / -p]"
echo -e "*********************************************************"


# Verify if .logs directory exists
if ! [ -d .logs ]; then
    mkdir .logs
fi

if [ "$1" == "destroy" ] || [ "$1" == "-d" ] 
then
    # Destroy what has been applied + all ressource groups : just to be sure 
    read -p "Destroy ? (Erase everything you just created)[Y/N] " resp
    if [ "$resp" == "Y" ] || [ "$resp" == "y" ] || [ "$resp" == "yes" ] || [ "$resp" == "Yes" ]
    then
        terraform destroy -auto-approve && echo "Terraform destroy complete" || echo "Probleme with terraform destroy. /!\\ Do not destroy resource groups, re destroy /!\\ "; exit

        read -p "Delete resource groups ? (N: If you plan to re apply) [Y/N] " resp
        if [ "$resp" == "Y" ] || [ "$resp" == "y" ] || [ "$resp" == "yes" ] || [ "$resp" == "Yes" ]
        then
            if [[ "$(az group exists --name $TERRAGOAT_RESOURCE_GROUP)" != "false" ]]; then az group delete --resource-group $TERRAGOAT_RESOURCE_GROUP --yes && echo "Resource group erased: $TERRAGOAT_RESOURCE_GROUP "; fi
                
            if [[ "$(az group exists --name terragoat-$TF_VAR_environment)" != "false" ]]; then az group delete --resource-group "terragoat-"$TF_VAR_environment --yes && echo "Resource group erased: terragoat-$TF_VAR_environment"; fi

            if [[ "$(az group exists --name "NetworkWatcherRG")" != "false" ]]; then az group delete --resource-group "NetworkWatcherRG" --yes && echo "Resource group erased: NetworkWatcherRG "; fi
        fi
        exit
    fi

elif [ "$1" == "purge" ] || [ "$1" == "-p" ]
then
    read -p "Purge ? (If you had any error, cancel the apply or you want to clean the env respond Y) [Y/N] " resp
    if [ "$resp" == "Y" ] || [ "$resp" == "y" ] || [ "$resp" == "yes" ] || [ "$resp" == "Yes" ] 
    then
       
        # Delete if resource groups still exists else pass
        if [[ "$(az group exists --name $TERRAGOAT_RESOURCE_GROUP)" != "false" ]]; then az group delete --resource-group $TERRAGOAT_RESOURCE_GROUP --yes && echo "Resource group erased 1/3"; fi
        
        if [[ "$(az group exists --name terragoat-$TF_VAR_environment)" != "false" ]]; then az group delete --resource-group "terragoat-"$TF_VAR_environment --yes && echo "Resource group erased 2/3"; fi
        
        if [[ "$(az group exists --name "NetworkWatcherRG")" != "false" ]]; then az group delete --resource-group "NetworkWatcherRG" --yes && echo "Resource group erased 3/3"; fi

        # Delete log-profiles if still exists else pass
        az monitor log-profiles list --query "[].{id:id, name:name}" > log_profiles
        log_profile_count=$(cat log_profiles | grep "id" | grep -i "terragoat" | wc -l)
        if [[ $log_profile_count -ge 1 ]]; then az monitor log-profiles delete --name $(cat log_profiles | grep 'id' -A1 | grep 'name' | tr -d ' ' | cut -d':' -f2 | tr -d '"') ; fi
        rm log_profiles

        # delete policies, roles, security contact
        az policy assignment delete --name "terragoat-policy-assignment-dev"  
        az policy definition delete --name "terragoat-policy-dev" 

        az role definition list --query "[].{description:description, name:name}" > tmproles
        nb_roles=$(cat tmproles | grep 'This is a custom role created via Terraform' -A1 | grep 'name' | tr -d ' ' | cut -d':' -f2 | wc -l)
        roles=$(cat tmproles | grep 'This is a custom role created via Terraform' -A1 | grep 'name' | tr -d ' ' | cut -d':' -f2)
        rm tmproles
        for nb in $(seq 1 $nb_roles)
        do
            az role definition delete --name $(echo $roles | cut -d' ' -f$nb | tr -d ' ' | tr -d '"') 
        done
        

        az security contact delete --name "default1"  
        echo "Purge complete."
        exit
    fi

elif [ "$1" == "apply" ] || [ "$1" == "-a" ] 
then
    read -p "Init ? (Initialisation of TerraGoat environment) [Y/N] " resp
    if ! ([ "$resp" == "Y" ] || [ "$resp" == "y" ] || [ "$resp" == "yes" ] || [ "$resp" == "Yes" ]); then exit; fi


    # Create resource group
    echo -n "Resource group ..."; echo "Resource group :" >> $setupoutput
    az group create --location $TF_VAR_region --name $TERRAGOAT_RESOURCE_GROUP >> $setupoutput && echo "OK"

    # Create storage account
    echo "Storage account :" >> $setupoutput
    # create storage account if storage account does not exists else change storage account name then create it
    if [[ "$(az storage account check-name --name $TERRAGOAT_STATE_STORAGE_ACCOUNT --query "nameAvailable")" == "false" ]]; then export TERRAGOAT_STATE_STORAGE_ACCOUNT=$TERRAGOAT_STATE_STORAGE_ACCOUNT"$((1000 + $RANDOM % 9999))"; fi  

    az storage account create --name $TERRAGOAT_STATE_STORAGE_ACCOUNT --resource-group $TERRAGOAT_RESOURCE_GROUP --location $TF_VAR_region --sku Standard_LRS --kind StorageV2 --https-only true --encryption-services blob >> $setupoutput && echo "Storage account ...OK"




    # Get storage account key
    echo -n "Storage account key ..."
    ACCOUNT_KEY=$(az storage account keys list --resource-group $TERRAGOAT_RESOURCE_GROUP --account-name $TERRAGOAT_STATE_STORAGE_ACCOUNT --query [0].value -o tsv) >> $setupoutput && echo "OK"
    echo "Storage account key : $ACCOUNT_KEY" >> $setupoutput

    # Create blob container
    echo -n "Blob container ..."; echo "Blob container : " >> $setupoutput
    az storage container create --name $TERRAGOAT_STATE_CONTAINER --account-name $TERRAGOAT_STATE_STORAGE_ACCOUNT --account-key $ACCOUNT_KEY >> $setupoutput && echo "OK"

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


    # Start terraform init with backend configuration
    echo -n "Terraform init ..."; echo "Terraform init : " >> $setupoutput
    terraform init -reconfigure -backend-config="resource_group_name=$TERRAGOAT_RESOURCE_GROUP" \
        -backend-config "storage_account_name=$TERRAGOAT_STATE_STORAGE_ACCOUNT" \
        -backend-config="container_name=$TERRAGOAT_STATE_CONTAINER" \
        -backend-config "key=$TF_VAR_environment.terraform.tfstate" >> $setupoutput && echo "OK"


    # Exporting plan to $tfplan path, that will be used to apply
    echo -n "Exporting plan ..."
    terraform plan -out=$tfplan > ".logs/clearTextplan.log" && echo "OK"

    # Apply = create resources annonced in the plan
    read -p "Apply ? (Launch scripts = create the environement) [Y/N] " resp
    if [ "$resp" == "Y" ] || [ "$resp" == "y" ] || [ "$resp" == "yes" ] || [ "$resp" == "Yes" ]
    then
        start=`date +%s`
        terraform apply $tfplan
        end=`date +%s`
        echo "Apply took $((end-start))s"
    fi


fi




