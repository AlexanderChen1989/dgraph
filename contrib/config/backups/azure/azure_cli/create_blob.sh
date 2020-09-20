#!/usr/bin/env bash

## Check for Azure CLI command
command -v az > /dev/null || \
  { echo "'az' command not not found" 1>&2; exit 1; }
command -v jq > /dev/null || \
  { echo "'jq' command not not found" 1>&2; exit 1; }

## Defaults
MY_CONTAINER_NAME=${MY_CONTAINER_NAME:-$1}
MY_STORAGE_ACCT=${MY_STORAGE_ACCT:-""}
MY_RESOURCE_GROUP=${MY_RESOURCE_GROUP:=""}
MY_LOCATION=${MY_LOCATION:-"eastus2"}
MY_ACCOUNT_ID="$(az account show | jq '.id' -r)"
CREATE_MINIO_ENV={$CREATE_MINIO_ENV:-"true"}

if [[ -z "${MY_CONTAINER_NAME}" ]]; then
  if (( $# < 1 )); then
    printf "[ERROR]: Need at least one parameter or define 'MY_CONTAINER_NAME'\n\n" 1>&2
    printf "Usage:\n\t$0 <container-name>\n\tMY_CONTAINER_NAME=<container-name> $0\n" 1>&2
    exit 1
  fi
fi

if [[ -z "${MY_STORAGE_ACCT}" ]]; then
  printf "[ERROR]: The env var of 'MY_STORAGE_ACCT' was not defined. Exiting\n" 1>&2
  exit 1
fi

if [[ -z "${MY_RESOURCE_GROUP}" ]]; then
  printf "[ERROR]: The env var of 'MY_RESOURCE_GROUP' was not defined. Exiting\n" 1>&2
  exit 1
fi




## create resource (idempotently)
if ! az group list | jq '.[].name' -r | grep -q ${MY_RESOURCE_GROUP}; then
  echo "[INFO]: Creating Resource Group '${MY_RESOURCE_GROUP}' at Location '${MY_LOCATION}'"
  az group create --name=${MY_RESOURCE_GROUP} --location=${MY_LOCATION}
fi

## create globally unique storage account (idempotently)
if ! az storage account list | jq '.[].name' -r | grep -q ${MY_STORAGE_ACCT}; then
  echo "[INFO]: Creating Storage Account '${MY_STORAGE_ACCT}'"
  az storage account create \
    --name ${MY_STORAGE_ACCT} \
    --resource-group ${MY_RESOURCE_GROUP} \
    --location ${MY_LOCATION} \
    --sku Standard_ZRS \
    --encryption-services blob
fi

## Use Azure AD Account to Authorize Operation
az ad signed-in-user show --query objectId -o tsv | az role assignment create \
    --role "Storage Blob Data Contributor" \
    --assignee @- \
    --scope "/subscriptions/${MY_ACCOUNT_ID}/resourceGroups/${MY_RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${MY_STORAGE_ACCT}" > /dev/null

## Create Container Using Credentials
if ! az storage container list \
 --account-name ${MY_STORAGE_ACCT} \
 --auth-mode login | jq '.[].name' -r | grep -q ${MY_CONTAINER_NAME}
then
  echo "[INFO]: Creating Storage Container '${MY_CONTAINER_NAME}'"
  az storage container create \
    --account-name ${MY_STORAGE_ACCT} \
    --name ${MY_CONTAINER_NAME} \
    --auth-mode login
fi

if [[ "${CREATE_MINIO_ENV}" =~ true|(y)es ]]; then
  echo "[INFO]: Creating minio.env file"
  ./create_minio_env.sh
fi
