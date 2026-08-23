#!/bin/bash
# set -x

# Add zsh compatibility
if [ -n "$ZSH_VERSION" ]; then
    emulate -L bash
fi

# Print usage information
print_usage() {
    echo "Description:"
    echo " Check for existing GCP resources and import them into Terraform state"
    echo " Handles both for_each and non-for_each resource formats"
    echo
    echo "Usage:"
    echo " check_resources [-p|--project-id <project-id>] [-i|--pool-id <pool-id>] [-v|--provider-id <provider-id>]"
    echo " [-s|--service-account <service-account>] [-d|--directory <terraform-dir>]"
    echo
    echo "Arguments:"
    echo " -p, --project-id       Google Cloud Project ID"
    echo " -i, --pool-id          Workload Identity Pool ID"
    echo " -v, --provider-id      Workload Identity Provider ID"
    echo " -s, --service-account  Service Account name (default: github-actions-sa)"
    echo " -d, --directory        Directory containing Terraform configuration (default: current directory)"
    echo " -h, --help             Show this help message"
    echo
    echo "Example:"
    echo " check_resources -p my-gcp-project -i github-id-pool -v github-id-provider"
    echo " check_resources --project-id=my-gcp-project --pool-id=github-id-pool --provider-id=github-id-provider --service-account=custom-sa"
}

# Function to check if resource exists in state with either for_each or not
check_state() {
    local resource_type=$1
    local resource_name=$2
    local terraform_dir=$3

    # Use terraform command with directory if specified
    local tf_cmd="terraform"
    if [ -n "$terraform_dir" ]; then
        tf_cmd="terraform -chdir=$terraform_dir"
    fi

    # Get the full state list for debugging
    echo "Terraform state contains:"
    $tf_cmd state list
    if [ $? -ne 0 ]; then
        echo "Error listing terraform state"
        return 1
    fi

    # Check non-for_each version
    if $tf_cmd state list 2>/dev/null | grep -q "${resource_type}\.${resource_name}$"; then
        echo "Found as non-for_each"
        return 0
    fi

    # Check for_each version
    if $tf_cmd state list 2>/dev/null | grep -q "${resource_type}\.${resource_name}\["; then
        echo "Found as for_each"
        return 0
    fi

    # Not in state
    echo "Not found in state"
    return 1
}

# Function to clean and import a resource
clean_and_import() {
    local resource_type=$1
    local resource_name=$2
    local import_id=$3
    local terraform_dir=$4
    local success=0

    echo "Cleaning state for ${resource_type}.${resource_name}..."

    # Use terraform command with directory if specified
    local tf_cmd="terraform"
    if [ -n "$terraform_dir" ]; then
        tf_cmd="terraform -chdir=$terraform_dir"
    fi

    # Remove all versions of this resource from state
    $tf_cmd state list 2>/dev/null | grep "${resource_type}\.${resource_name}" | while read -r state_path; do
        echo "Removing $state_path"
        $tf_cmd state rm "$state_path"
        if [ $? -ne 0 ]; then
            echo "Warning: Failed to remove $state_path from state"
        fi
    done

    # Import resource
    echo "Importing ${resource_type}.${resource_name}..."
    $tf_cmd import "${resource_type}.${resource_name}" "$import_id"
    if [ $? -ne 0 ]; then
        echo "Import failed. The resource may not exist or may not be accessible."
        success=1
    else
        echo "Import successful"
    fi

    return $success
}

# Function to check for required commands
check_dependencies() {
    local missing_deps=()

    for cmd in gcloud terraform; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "Error: Required commands not found: ${missing_deps[*]}"
        return 1
    fi

    return 0
}

# Function to validate GCP authentication
validate_gcp_auth() {
    local project_id=$1

    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="get(account)" 2>/dev/null | grep -q "@"; then
        echo "Error: Not authenticated with GCP. Please run 'gcloud auth login'"
        return 1
    fi

    # Check if project exists and is accessible
    if ! gcloud projects describe "$project_id" >/dev/null 2>&1; then
        echo "Error: Project $project_id not found or not accessible"
        return 1
    fi

    return 0
}

# Main function to check and import resources
check_resources() {
    # Initialize variables with defaults
    local PROJECT_ID=""
    local POOL_ID=""
    local PROVIDER_ID=""
    local SERVICE_ACCOUNT="github-actions-sa"
    local TERRAFORM_DIR=""
    local overall_status=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
        -p | --project-id)
            if [[ "$2" == -* || -z "$2" ]]; then
                echo "Error: Argument for $1 is missing" >&2
                return 1
            fi
            PROJECT_ID="$2"
            shift 2
            ;;
        --project-id=*)
            PROJECT_ID="${1#*=}"
            shift
            ;;
        -i | --pool-id)
            if [[ "$2" == -* || -z "$2" ]]; then
                echo "Error: Argument for $1 is missing" >&2
                return 1
            fi
            POOL_ID="$2"
            shift 2
            ;;
        --pool-id=*)
            POOL_ID="${1#*=}"
            shift
            ;;
        -v | --provider-id)
            if [[ "$2" == -* || -z "$2" ]]; then
                echo "Error: Argument for $1 is missing" >&2
                return 1
            fi
            PROVIDER_ID="$2"
            shift 2
            ;;
        --provider-id=*)
            PROVIDER_ID="${1#*=}"
            shift
            ;;
        -s | --service-account)
            if [[ "$2" == -* || -z "$2" ]]; then
                echo "Error: Argument for $1 is missing" >&2
                return 1
            fi
            SERVICE_ACCOUNT="$2"
            shift 2
            ;;
        --service-account=*)
            SERVICE_ACCOUNT="${1#*=}"
            shift
            ;;
        -d | --directory)
            if [[ "$2" == -* || -z "$2" ]]; then
                echo "Error: Argument for $1 is missing" >&2
                return 1
            fi
            TERRAFORM_DIR="$2"
            shift 2
            ;;
        --directory=*)
            TERRAFORM_DIR="${1#*=}"
            shift
            ;;
        -h | --help)
            print_usage
            return 0
            ;;
        *)
            echo "Error: Unknown parameter $1" >&2
            print_usage
            return 1
            ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$PROJECT_ID" || -z "$POOL_ID" || -z "$PROVIDER_ID" ]]; then
        echo "Error: Missing required arguments" >&2
        print_usage
        return 1
    fi

    # Check dependencies
    check_dependencies
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Validate GCP authentication
    validate_gcp_auth "$PROJECT_ID"
    if [ $? -ne 0 ]; then
        return 1
    fi

    echo "Checking for existing resources in project $PROJECT_ID..."

    # Check for service account existence and state
    if gcloud iam service-accounts describe ${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com --project=${PROJECT_ID} &>/dev/null; then
        # Check if the service account is disabled (soft-deleted)
        SA_DISABLED=$(gcloud iam service-accounts describe ${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com --project=${PROJECT_ID} --format="value(disabled)")

        if [ "$SA_DISABLED" == "True" ] || [ "$SA_DISABLED" == "true" ]; then
            echo "⚠️ Service account exists but is disabled (soft-deleted)"
            echo "❌ A new service account will be created by terraform"
        else
            echo "✅ Service account exists and is active"

            # Check state and import if needed
            echo "Checking terraform state for service account..."
            echo "Running check: check_state \"google_service_account\" \"github_actions_sa\" \"$TERRAFORM_DIR\""
            SA_STATE=$(check_state "google_service_account" "github_actions_sa" "$TERRAFORM_DIR")
            check_status=$?
            echo "Debug - SA_STATE value: $SA_STATE (status: $check_status)"

            if [ "$SA_STATE" == "Not found in state" ] || [ $check_status -ne 0 ]; then
                echo "Service account not in terraform state, importing..."
                clean_and_import "google_service_account" "github_actions_sa" "projects/${PROJECT_ID}/serviceAccounts/${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" "$TERRAFORM_DIR"
                if [ $? -ne 0 ]; then
                    overall_status=1
                fi
            elif [ "$SA_STATE" == "Found as for_each" ]; then
                echo "Service account in terraform state with for_each, cleaning up..."
                clean_and_import "google_service_account" "github_actions_sa" "projects/${PROJECT_ID}/serviceAccounts/${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" "$TERRAFORM_DIR"
                if [ $? -ne 0 ]; then
                    overall_status=1
                fi
            else
                echo "Service account already in terraform state (non-for_each version)"
            fi
        fi
    else
        echo "❌ Service account does not exist, will be created by terraform"
    fi

    # Check for workload identity pool existence and state
    if gcloud iam workload-identity-pools describe ${POOL_ID} --project=${PROJECT_ID} --location=global &>/dev/null; then
        # Check the state of the pool
        POOL_STATE=$(gcloud iam workload-identity-pools describe ${POOL_ID} --project=${PROJECT_ID} --location=global --format="value(state)")

        if [ "$POOL_STATE" == "DELETED" ] || [ "$POOL_STATE" == "DELETING" ]; then
            echo "⚠️ Workload identity pool exists but is in ${POOL_STATE} state (soft-deleted)"
            echo "❌ A new workload identity pool will be created by terraform"
        else
            echo "✅ Workload identity pool exists and is in ${POOL_STATE} state"

            # Check state and import if needed
            echo "Checking terraform state for workload identity pool..."
            WIP_STATE=$(check_state "google_iam_workload_identity_pool" "github_pool" "$TERRAFORM_DIR")
            check_status=$?
            echo "Debug - WIP_STATE value: $WIP_STATE (status: $check_status)"

            if [ "$WIP_STATE" == "Not found in state" ] || [ $check_status -ne 0 ]; then
                echo "Workload identity pool not in terraform state, importing..."
                clean_and_import "google_iam_workload_identity_pool" "github_pool" "projects/${PROJECT_ID}/locations/global/workloadIdentityPools/${POOL_ID}" "$TERRAFORM_DIR"
                if [ $? -ne 0 ]; then
                    overall_status=1
                fi
            else
                echo "Workload identity pool already in terraform state"
            fi
        fi
    else
        echo "❌ Workload identity pool does not exist, will be created by terraform"
    fi

    # Check for workload identity provider existence and state
    if gcloud iam workload-identity-pools providers describe ${PROVIDER_ID} --project=${PROJECT_ID} --location=global --workload-identity-pool=${POOL_ID} &>/dev/null; then
        # Check the state of the provider
        PROVIDER_STATE=$(gcloud iam workload-identity-pools providers describe ${PROVIDER_ID} --project=${PROJECT_ID} --location=global --workload-identity-pool=${POOL_ID} --format="value(state)")

        if [ "$PROVIDER_STATE" == "DELETED" ] || [ "$PROVIDER_STATE" == "DELETING" ]; then
            echo "⚠️ Workload identity provider exists but is in ${PROVIDER_STATE} state (soft-deleted)"
            echo "❌ A new workload identity provider will be created by terraform"
        else
            echo "✅ Workload identity provider exists and is in ${PROVIDER_STATE} state"

            # Check state and import if needed
            echo "Checking terraform state for workload identity provider..."
            WIP_PROVIDER_STATE=$(check_state "google_iam_workload_identity_pool_provider" "github_provider" "$TERRAFORM_DIR")
            check_status=$?
            echo "Debug - WIP_PROVIDER_STATE value: $WIP_PROVIDER_STATE (status: $check_status)"

            if [ "$WIP_PROVIDER_STATE" == "Not found in state" ] || [ $check_status -ne 0 ]; then
                echo "Workload identity provider not in terraform state, importing..."
                clean_and_import "google_iam_workload_identity_pool_provider" "github_provider" "projects/${PROJECT_ID}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}" "$TERRAFORM_DIR"
                if [ $? -ne 0 ]; then
                    overall_status=1
                fi
            else
                echo "Workload identity provider already in terraform state"
            fi
        fi
    else
        echo "❌ Workload identity provider does not exist, will be created by terraform"
    fi

    if [ $overall_status -eq 0 ]; then
        echo "Resource check and import complete! All operations successful."
    else
        echo "Resource check and import complete with errors. Some operations failed."
    fi

    return $overall_status
}

# If script is being run directly (not sourced), execute with provided arguments
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
    check_resources "$@"
    exit $?
fi
