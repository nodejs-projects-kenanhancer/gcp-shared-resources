#!/bin/bash

# ============================================================================
# Azure Provider Module for Terraform Initialization
#
# Purpose: Handle Azure-specific operations for Terraform backend
# Author: Kenan Hancer
# Version: 2.0.0 (Interface Pattern)
# ============================================================================

# ============================================================================
# CONFIGURATION
# ============================================================================

AZURE_DEFAULT_LOCATION="uksouth"
AZURE_DEFAULT_STORAGE_PREFIX="tfstate"
AZURE_DEFAULT_CONTAINER_NAME="tfstate"
AZURE_DEFAULT_RESOURCE_GROUP="terraform-state-rg"
AZURE_LIFECYCLE_DAYS=90

# ============================================================================
# AZURE-SPECIFIC VARIABLES
# ============================================================================

# These will be set by parse_arguments
AZURE_STORAGE_ACCOUNT=""
AZURE_CONTAINER_NAME=""
AZURE_SUBSCRIPTION_ID=""
AZURE_RESOURCE_GROUP=""
AZURE_LOCATION=""
AZURE_ACCESS_KEY=""
AZURE_TAGS=""

# ============================================================================
# PROVIDER INTERFACE IMPLEMENTATION
# ============================================================================

# Print usage information for this provider
print_usage() {
    cat <<EOF
Azure Provider Options:
    -s, --subscription ID        Azure subscription ID (or use ARM_SUBSCRIPTION_ID env var) (REQUIRED)
    -g, --storage-account NAME   Storage account name for Terraform state
                                 (default: $AZURE_DEFAULT_STORAGE_PREFIX<random>)
    -c, --container-name NAME    Container name in storage account
                                 (default: $AZURE_DEFAULT_CONTAINER_NAME)
    -r, --resource-group NAME    Resource group name (created if doesn't exist)
                                 (default: $AZURE_DEFAULT_RESOURCE_GROUP)
    -l, --location LOCATION      Azure location (default: $AZURE_DEFAULT_LOCATION)
    -k, --access-key KEY         Storage account access key (retrieved if not provided)
    -t, --tags TAGS              Tags in format "key1=value1,key2=value2"

Azure Examples:
    # Basic usage with subscription ID
    $SCRIPT_NAME -p azure -d terraform -s xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

    # With custom storage account and resource group
    $SCRIPT_NAME -p azure -d terraform -s <subscription-id> -g mystorageaccount -r my-rg

    # With custom location and tags
    $SCRIPT_NAME -p azure -d terraform -s <subscription-id> -l westeurope -t "env=prod,team=devops"

Environment Variables:
    ARM_SUBSCRIPTION_ID          Azure subscription ID (alternative to -s option)
    ARM_TENANT_ID               Azure tenant ID
    ARM_CLIENT_ID               Service principal client ID
    ARM_CLIENT_SECRET           Service principal client secret

EOF
}

# Parse provider-specific arguments
parse_arguments() {
    AZURE_CONTAINER_NAME="$AZURE_DEFAULT_CONTAINER_NAME"
    AZURE_RESOURCE_GROUP="$AZURE_DEFAULT_RESOURCE_GROUP"
    AZURE_LOCATION="$AZURE_DEFAULT_LOCATION"

    while [ $# -gt 0 ]; do
        case $1 in
        -g | --storage-account)
            AZURE_STORAGE_ACCOUNT="$2"
            shift 2
            ;;
        -c | --container-name)
            AZURE_CONTAINER_NAME="$2"
            shift 2
            ;;
        -s | --subscription)
            AZURE_SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -r | --resource-group)
            AZURE_RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l | --location)
            AZURE_LOCATION="$2"
            shift 2
            ;;
        -k | --access-key)
            AZURE_ACCESS_KEY="$2"
            shift 2
            ;;
        -t | --tags)
            AZURE_TAGS="$2"
            shift 2
            ;;
        *)
            log_error "Unknown Azure parameter: $1"
            print_usage
            return 1
            ;;
        esac
    done

    # Use environment variable if subscription not provided
    AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-$ARM_SUBSCRIPTION_ID}"

    return 0
}

# Validate required arguments
validate_required_args() {
    local terraform_dir="$1" # Fixed: removed asterisks
    local missing_args=()

    # Check each required argument
    if [ -z "$terraform_dir" ]; then
        missing_args+=("terraform-dir")
    fi

    if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
        missing_args+=("subscription")
    fi

    # Report errors if any
    if [ ${#missing_args[@]} -gt 0 ]; then
        local missing_list=$(
            IFS=', '
            echo "${missing_args[*]}"
        )
        log_error "Missing required Azure arguments: $missing_list"
        echo # blank line for readability
        print_usage
        return 1
    fi

    return 0
}

# Check provider-specific dependencies
check_dependencies() {
    if ! command -v az >/dev/null 2>&1; then
        log_error "Azure CLI (az) is not installed"
        log_info "Please install it using one of these methods:"
        echo "  • macOS: brew install azure-cli" >&2
        echo "  • Linux: See https://aka.ms/InstallAzureCLI" >&2
        echo "  • Windows: Download from https://aka.ms/installazurecliwindows" >&2
        return 1
    fi
    return 0
}

# Validate authentication
validate_auth() {
    # Check if user is logged in
    if ! az account show >/dev/null 2>&1; then
        log_error "Not authenticated with Azure. Please run 'az login'"
        return 1
    fi

    # Set subscription
    if ! az account set --subscription "$AZURE_SUBSCRIPTION_ID" 2>/dev/null; then
        log_error "Failed to set subscription '$AZURE_SUBSCRIPTION_ID'"
        log_info "Please check the subscription ID and your permissions"
        return 1
    fi

    # Verify subscription is active
    local state
    state=$(az account show --query state -o tsv)
    if [ "$state" != "Enabled" ]; then
        log_error "Subscription '$AZURE_SUBSCRIPTION_ID' is not enabled (state: $state)"
        return 1
    fi

    return 0
}

# Ensure backend storage exists
ensure_backend_storage() {
    # Generate storage account name if needed
    AZURE_STORAGE_ACCOUNT=$(generate_storage_account_name "$AZURE_STORAGE_ACCOUNT" "$AZURE_DEFAULT_STORAGE_PREFIX")

    # Ensure resource group exists
    if resource_group_exists "$AZURE_RESOURCE_GROUP"; then
        log_info "Resource group $AZURE_RESOURCE_GROUP already exists"
    else
        if ! create_resource_group "$AZURE_RESOURCE_GROUP" "$AZURE_LOCATION" "$AZURE_TAGS"; then
            return 1
        fi
    fi

    # Ensure storage account exists
    if storage_account_exists "$AZURE_STORAGE_ACCOUNT"; then
        log_info "Storage account $AZURE_STORAGE_ACCOUNT already exists"
    else
        if ! create_storage_account "$AZURE_STORAGE_ACCOUNT" "$AZURE_RESOURCE_GROUP" "$AZURE_LOCATION" "$AZURE_TAGS"; then
            return 1
        fi
    fi

    # Get storage account key if not provided
    if [ -z "$AZURE_ACCESS_KEY" ]; then
        log_info "Retrieving storage account access key..."
        AZURE_ACCESS_KEY=$(get_storage_account_key "$AZURE_STORAGE_ACCOUNT" "$AZURE_RESOURCE_GROUP")
        if [ -z "$AZURE_ACCESS_KEY" ]; then
            log_error "Failed to retrieve storage account access key"
            return 1
        fi
    fi

    # Ensure container exists
    if container_exists "$AZURE_STORAGE_ACCOUNT" "$AZURE_CONTAINER_NAME" "$AZURE_ACCESS_KEY"; then
        log_info "Container $AZURE_CONTAINER_NAME already exists"
    else
        if ! create_container "$AZURE_STORAGE_ACCOUNT" "$AZURE_CONTAINER_NAME" "$AZURE_ACCESS_KEY"; then
            return 1
        fi
    fi

    return 0
}

# Generate backend configuration
generate_backend_config() {
    local file_path="$1"
    local env_config="$2" # Now expects JSON object

    local state_key
    if [ -n "$env_config" ] && [ "$env_config" != "null" ] && [ "$env_config" != "{}" ]; then
        local state_prefix=$(echo "$env_config" | jq -r '.state_prefix // empty')
        if [ -n "$state_prefix" ]; then
            state_key="${state_prefix}.tfstate"
        fi
    fi

    if [ -z "$state_key" ]; then
        state_key="$ARG_TERRAFORM_DIR/default.tfstate"
        log_warning "Using default state key: $state_key"
    fi

    log_info "STATE_KEY: $state_key"
    log_info "Generating Azure backend configuration..."

    cat >"$file_path" <<EOF
resource_group_name  = "$AZURE_RESOURCE_GROUP"
storage_account_name = "$AZURE_STORAGE_ACCOUNT"
container_name       = "$AZURE_CONTAINER_NAME"
key                  = "$state_key"
access_key           = "$AZURE_ACCESS_KEY"
EOF

    log_info "Backend config generated at: $file_path"
    return 0
}

# Update terraform variables
update_tfvars() {
    local tfvar_file="$1"
    local scripts_dir="$2"

    if [ -f "$scripts_dir/set_env_property.sh" ]; then
        . "$scripts_dir/set_env_property.sh"
        set_env_property --file "$tfvar_file" --key azure_location --value "$AZURE_LOCATION"
        set_env_property --file "$tfvar_file" --key azure_subscription_id --value "$AZURE_SUBSCRIPTION_ID"
    else
        log_warning "set_env_property.sh not found, skipping tfvars update"
    fi

    return 0
}

# ============================================================================
# AZURE-SPECIFIC HELPER FUNCTIONS
# ============================================================================

generate_storage_account_name() {
    local storage_account="$1"
    local prefix="$2"

    if [ -z "$storage_account" ]; then
        # Generate a unique name (max 24 chars, lowercase alphanumeric only)
        local random_suffix
        random_suffix=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 8)
        storage_account="${prefix}${random_suffix}"

        # Ensure it's max 24 characters
        storage_account=$(echo "$storage_account" | cut -c1-24)

        log_info "Generated Azure storage account name: $storage_account"
    fi

    # Validate storage account name
    if ! echo "$storage_account" | grep -qE '^[a-z0-9]{3,24}$'; then
        log_error "Invalid storage account name: $storage_account"
        log_info "Storage account names must be 3-24 characters, lowercase letters and numbers only"
        return 1
    fi

    echo "$storage_account"
}

resource_group_exists() {
    local rg_name="$1"
    az group exists --name "$rg_name" | grep -q "true"
}

create_resource_group() {
    local rg_name="$1"
    local location="$2"
    local tags="$3"

    log_info "Creating resource group: $rg_name..."

    local tag_args=""
    if [ -n "$tags" ]; then
        tag_args="--tags $tags"
    fi

    if ! az group create \
        --name "$rg_name" \
        --location "$location" \
        $tag_args \
        --output none; then
        log_error "Failed to create resource group: $rg_name"
        return 1
    fi

    log_success "Resource group $rg_name created successfully"
    return 0
}

storage_account_exists() {
    local storage_account="$1"
    az storage account show --name "$storage_account" >/dev/null 2>&1
}

create_storage_account() {
    local storage_account="$1"
    local rg_name="$2"
    local location="$3"
    local tags="$4"

    log_info "Creating storage account: $storage_account..."

    local tag_args=""
    if [ -n "$tags" ]; then
        tag_args="--tags $tags"
    fi

    # Create storage account with secure defaults
    if ! az storage account create \
        --name "$storage_account" \
        --resource-group "$rg_name" \
        --location "$location" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --https-only true \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --enable-infrastructure-encryption \
        $tag_args \
        --output none; then
        log_error "Failed to create storage account: $storage_account"
        return 1
    fi

    # Enable blob versioning
    log_info "Enabling blob versioning..."
    if ! az storage account blob-service-properties update \
        --account-name "$storage_account" \
        --resource-group "$rg_name" \
        --enable-versioning true \
        --output none; then
        log_warning "Failed to enable blob versioning"
    fi

    # Set lifecycle management policy
    log_info "Setting lifecycle management policy..."
    local lifecycle_policy="/tmp/lifecycle-policy-$$.json"
    create_lifecycle_policy "$lifecycle_policy"

    if ! az storage account management-policy create \
        --account-name "$storage_account" \
        --resource-group "$rg_name" \
        --policy "@$lifecycle_policy" \
        --output none; then
        log_warning "Failed to set lifecycle policy"
    fi
    rm -f "$lifecycle_policy"

    log_success "Storage account $storage_account created successfully"
    return 0
}

create_lifecycle_policy() {
    local temp_file="$1"

    cat >"$temp_file" <<EOF
{
  "rules": [
    {
      "enabled": true,
      "name": "terraform-state-lifecycle",
      "type": "Lifecycle",
      "definition": {
        "actions": {
          "version": {
            "delete": {
              "daysAfterCreationGreaterThan": $AZURE_LIFECYCLE_DAYS
            }
          },
          "baseBlob": {
            "delete": {
              "daysAfterModificationGreaterThan": 365
            }
          }
        },
        "filters": {
          "blobTypes": [
            "blockBlob"
          ]
        }
      }
    }
  ]
}
EOF
}

get_storage_account_key() {
    local storage_account="$1"
    local rg_name="$2"

    az storage account keys list \
        --account-name "$storage_account" \
        --resource-group "$rg_name" \
        --query "[0].value" \
        --output tsv
}

container_exists() {
    local storage_account="$1"
    local container_name="$2"
    local access_key="$3"

    az storage container exists \
        --account-name "$storage_account" \
        --account-key "$access_key" \
        --name "$container_name" \
        --query exists \
        --output tsv | grep -q "true"
}

create_container() {
    local storage_account="$1"
    local container_name="$2"
    local access_key="$3"

    log_info "Creating container: $container_name..."

    if ! az storage container create \
        --account-name "$storage_account" \
        --account-key "$access_key" \
        --name "$container_name" \
        --output none; then
        log_error "Failed to create container: $container_name"
        return 1
    fi

    log_success "Container $container_name created successfully"
    return 0
}
