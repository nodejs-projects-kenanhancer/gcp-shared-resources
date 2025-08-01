#!/bin/bash

# ============================================================================
# GCP Provider Module for Terraform Initialization
#
# Purpose: Handle GCP-specific operations for Terraform backend
# Author: Kenan Hancer
# Version: 2.0.0 (Interface Pattern)
# ============================================================================

# ============================================================================
# CONFIGURATION
# ============================================================================

GCP_DEFAULT_REGION="europe-west2"
GCP_DEFAULT_BUCKET_PREFIX="terraform-state-bucket"
GCP_LIFECYCLE_NUM_NEWER_VERSIONS=3
GCP_LIFECYCLE_DAYS_SINCE_NONCURRENT=90

# ============================================================================
# GCP-SPECIFIC VARIABLES
# ============================================================================

# These will be set by parse_arguments
GCP_BUCKET_NAME=""
GCP_ENCRYPTION_KEY=""
GCP_PROJECT_ID=""
GCP_REGION=""

# ============================================================================
# PROVIDER INTERFACE IMPLEMENTATION
# ============================================================================

# Print usage information for this provider
print_usage() {
    cat <<EOF
GCP Provider Options:
    -k, --encryption-key KEY     Key used for state file encryption (REQUIRED)
    -i, --project-id ID          Google Cloud Project ID (REQUIRED)
    -b, --bucket-name NAME       Name of the GCS bucket for Terraform state storage
                                 (default: $GCP_DEFAULT_BUCKET_PREFIX-<project-id>)
    -r, --region REGION          GCS bucket region (default: $GCP_DEFAULT_REGION)

GCP Examples:
    # Basic usage
    $SCRIPT_NAME -p gcp -d terraform -k my-key -i my-project-id

    # With custom bucket and region
    $SCRIPT_NAME -p gcp -d terraform -k my-key -i my-project-id -b my-bucket -r us-central1

    # With application name
    $SCRIPT_NAME -p gcp -d terraform -k my-key -i my-project-id -a my-app

EOF
}

# Parse provider-specific arguments
parse_arguments() {
    GCP_REGION="$GCP_DEFAULT_REGION"

    while [ $# -gt 0 ]; do
        case $1 in
        -b | --bucket-name)
            GCP_BUCKET_NAME="$2"
            shift 2
            ;;
        -k | --encryption-key)
            GCP_ENCRYPTION_KEY="$2"
            shift 2
            ;;
        -i | --project-id)
            GCP_PROJECT_ID="$2"
            shift 2
            ;;
        -r | --region)
            GCP_REGION="$2"
            shift 2
            ;;
        *)
            log_error "Unknown GCP parameter: $1"
            print_usage
            return 1
            ;;
        esac
    done

    return 0
}

# Validate required arguments
validate_required_args() {
    local terraform_dir="$1"
    local missing_args=()

    # Check each required argument
    if [ -z "$terraform_dir" ]; then
        missing_args+=("terraform-dir")
    fi

    if [ -z "$GCP_ENCRYPTION_KEY" ]; then
        missing_args+=("encryption-key")
    fi

    if [ -z "$GCP_PROJECT_ID" ]; then
        missing_args+=("project-id")
    fi

    # Report errors if any
    if [ ${#missing_args[@]} -gt 0 ]; then
        # Join array elements with comma and space
        local missing_list=$(
            IFS=', '
            echo "${missing_args[*]}"
        )
        log_error "Missing required GCP arguments: $missing_list"
        echo # blank line for readability
        print_usage
        return 1
    fi

    return 0
}

# Check provider-specific dependencies
check_dependencies() {
    if ! command -v gcloud >/dev/null 2>&1; then
        log_error "Google Cloud SDK (gcloud) is not installed"
        log_info "Please install it using one of these methods:"
        echo "  • macOS: brew install --cask google-cloud-sdk" >&2
        echo "  • Ubuntu/Debian: sudo apt-get install google-cloud-cli" >&2
        echo "  • RHEL/CentOS: sudo yum install google-cloud-cli" >&2
        echo "  • All platforms: curl https://sdk.cloud.google.com | bash" >&2
        echo "  • Documentation: https://cloud.google.com/sdk/docs/install" >&2
        return 1
    fi
    return 0
}

# Validate authentication
validate_auth() {
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="get(account)" 2>/dev/null | grep -q "@"; then
        log_error "Not authenticated with GCP. Please run 'gcloud auth login'"
        return 1
    fi

    # Check if project exists and is accessible
    if ! gcloud projects describe "$GCP_PROJECT_ID" >/dev/null 2>&1; then
        log_error "GCP Project '$GCP_PROJECT_ID' not found or not accessible"
        log_info "Please check the GCP Project ID and your permissions"
        return 1
    fi

    return 0
}

# Ensure backend storage exists
ensure_backend_storage() {
    local user_email
    user_email=$(get_user_email)

    # Generate bucket name if needed
    GCP_BUCKET_NAME=$(generate_bucket_name "$GCP_BUCKET_NAME" "$GCP_PROJECT_ID")

    if bucket_exists "$GCP_BUCKET_NAME"; then
        log_info "GCP Bucket gs://${GCP_BUCKET_NAME} already exists"
    else
        if ! create_bucket "$GCP_BUCKET_NAME" "$GCP_PROJECT_ID" "$GCP_REGION"; then
            return 1
        fi
    fi

    # Always ensure permissions are set
    grant_bucket_permissions "$GCP_BUCKET_NAME" "$user_email"
    return $?
}

# Generate backend configuration
generate_backend_config() {
    local file_path="$1"
    local env_config="$2" # Now expects JSON object

    local state_prefix
    if [ -n "$env_config" ] && [ "$env_config" != "null" ] && [ "$env_config" != "{}" ]; then
        state_prefix=$(echo "$env_config" | jq -r '.state_prefix // empty')
    fi

    if [ -z "$state_prefix" ]; then
        state_prefix="$ARG_TERRAFORM_DIR/default"
        log_warning "Using default state prefix: $state_prefix"
    fi

    log_info "STATE_PREFIX: $state_prefix"
    log_info "Generating GCP backend configuration..."

    cat >"$file_path" <<EOF
bucket = "$GCP_BUCKET_NAME"
prefix = "$state_prefix"
encryption_key = "$GCP_ENCRYPTION_KEY"
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
        set_env_property --file "$tfvar_file" --key gcp_project_id --value "$GCP_PROJECT_ID"
    else
        log_warning "set_env_property.sh not found, skipping tfvars update"
    fi

    return 0
}

# ============================================================================
# GCP-SPECIFIC HELPER FUNCTIONS
# ============================================================================

get_user_email() {
    gcloud config get-value account
}

generate_bucket_name() {
    local bucket_name="$1"
    local project_id="$2"

    if [ -z "$bucket_name" ]; then
        bucket_name="${GCP_DEFAULT_BUCKET_PREFIX}-${project_id}"
        log_info "Generated GCP bucket name: $bucket_name"
    elif [ "${bucket_name#*-$project_id}" = "$bucket_name" ]; then
        bucket_name="${bucket_name}-${project_id}"
        log_info "Appended GCP Project ID to bucket name: $bucket_name"
    fi

    echo "$bucket_name"
}

bucket_exists() {
    local bucket_name="$1"
    gcloud storage buckets describe "gs://${bucket_name}" >/dev/null 2>&1
}

create_lifecycle_policy() {
    local temp_file="$1"

    cat >"$temp_file" <<EOF
{
  "lifecycle": {
    "rule": [{
      "action": {
        "type": "Delete"
      },
      "condition": {
        "numNewerVersions": $GCP_LIFECYCLE_NUM_NEWER_VERSIONS,
        "daysSinceNoncurrentTime": $GCP_LIFECYCLE_DAYS_SINCE_NONCURRENT
      }
    }]
  }
}
EOF
}

create_bucket() {
    local bucket_name="$1"
    local project_id="$2"
    local region="$3"

    log_info "Creating GCP bucket gs://${bucket_name}..."

    # Create bucket with uniform bucket-level access
    if ! gcloud storage buckets create "gs://${bucket_name}" \
        --project="${project_id}" \
        --location="${region}" \
        --uniform-bucket-level-access; then
        log_error "Failed to create GCP bucket gs://${bucket_name}"
        return 1
    fi

    # Enable versioning
    log_info "Enabling versioning..."
    if ! gcloud storage buckets update "gs://${bucket_name}" --versioning; then
        log_warning "Failed to enable versioning on GCP bucket gs://${bucket_name}"
    fi

    # Set lifecycle policy
    log_info "Setting lifecycle policy..."
    local lifecycle_file="/tmp/lifecycle-$$.json"
    create_lifecycle_policy "$lifecycle_file"

    if ! gcloud storage buckets update "gs://${bucket_name}" --lifecycle-file="$lifecycle_file"; then
        log_warning "Failed to set lifecycle policy on GCP bucket gs://${bucket_name}"
    fi
    rm -f "$lifecycle_file"

    log_success "GCP Bucket gs://${bucket_name} created successfully"
    return 0
}

grant_bucket_permissions() {
    local bucket_name="$1"
    local user_email="$2"

    log_info "Granting Storage Object Admin permissions to ${user_email}..."

    local member_type="user"
    case "$user_email" in
    *"iam.gserviceaccount.com"*)
        member_type="serviceAccount"
        ;;
    esac

    if ! gcloud storage buckets add-iam-policy-binding "gs://${bucket_name}" \
        --member="${member_type}:${user_email}" \
        --role="roles/storage.objectAdmin"; then
        log_warning "Failed to grant permissions to ${user_email}"
        return 1
    fi

    return 0
}
