#!/bin/bash

print_usage() {
    echo "Description:"
    echo " Initializes Terraform configuration with remote state backend configuration"
    echo " and creates GCS bucket if it doesn't exist"
    echo
    echo "Usage:"
    echo " init_terraform [-b|--bucket-name <bucket-name>] -k|--encryption-key <encryption-key> -d|--terraform-dir <terraform-dir> -p|--project-id <project-id> [-r|--region <region>]"
    echo
    echo "Arguments:"
    echo " -b, --bucket-name    Name of the GCS bucket for Terraform state storage (optional, will be generated from project-id if not provided)"
    echo " -k, --encryption-key Key used for state file encryption"
    echo " -d, --terraform-dir  Directory containing Terraform configuration files"
    echo " -p, --project-id     Google Cloud Project ID"
    echo " -r, --region         GCS bucket region (default: us-central1)"
    echo
    echo "Example:"
    echo " init_terraform -k my-encryption-key -d terraform -p my-gcp-project"
    echo " init_terraform --bucket-name custom-bucket --encryption-key my-encryption-key --terraform-dir terraform --project-id my-gcp-project --region us-east1"
}

# Function to check for required commands
check_dependencies() {
    local missing_deps=()

    for cmd in gcloud gsutil terraform git; do
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

# Function to create and configure GCS bucket
create_bucket_if_not_exists() {
    local bucket_name=$1
    local project_id=$2
    local region=$3
    local user_email=$(gcloud config get-value account)

    # Check if bucket exists
    if ! gsutil ls -b "gs://${bucket_name}" &>/dev/null; then
        echo "Bucket gs://${bucket_name} does not exist. Creating..."

        # Create the bucket with uniform bucket-level access
        if ! gsutil mb -p "${project_id}" -l "${region}" "gs://${bucket_name}"; then
            echo "Error: Failed to create bucket gs://${bucket_name}"
            return 1
        fi

        # Enable uniform bucket-level access
        if ! gsutil uniformbucketlevelaccess set on "gs://${bucket_name}"; then
            echo "Warning: Failed to enable uniform bucket-level access on bucket gs://${bucket_name}"
        fi

        # Enable versioning
        if ! gsutil versioning set on "gs://${bucket_name}"; then
            echo "Warning: Failed to enable versioning on bucket gs://${bucket_name}"
        fi

        # Set lifecycle policy
        cat >/tmp/lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [{
      "action": {
        "type": "Delete"
      },
      "condition": {
        "numNewerVersions": 3,
        "daysSinceNoncurrentTime": 90
      }
    }]
  }
}
EOF
        if ! gsutil lifecycle set /tmp/lifecycle.json "gs://${bucket_name}"; then
            echo "Warning: Failed to set lifecycle policy on bucket gs://${bucket_name}"
        fi
        rm -f /tmp/lifecycle.json

        echo "Bucket gs://${bucket_name} created successfully with versioning enabled"
    else
        echo "Bucket gs://${bucket_name} already exists"
    fi

    # Grant permissions to the current user
    echo "Granting Storage Object Admin permissions to ${user_email}..."
    if [[ "$user_email" == *"iam.gserviceaccount.com" ]]; then
        # Handle service account
        if ! gsutil iam ch "serviceAccount:${user_email}:roles/storage.objectAdmin" "gs://${bucket_name}"; then
            echo "Warning: Failed to grant permissions to ${user_email}"
            return 1
        fi
    else
        # Handle regular user
        if ! gsutil iam ch "user:${user_email}:roles/storage.objectAdmin" "gs://${bucket_name}"; then
            echo "Warning: Failed to grant permissions to ${user_email}"
            return 1
        fi
    fi

    return 0
}

init_terraform() {
    # Initialize variables
    local bucket_name=""
    local encryption_key=""
    local terraform_dir=""
    local project_id=""
    local region="europe-north1" # Default region
    local app_name=""

    # Parse named arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
        -b | --bucket-name)
            bucket_name="$2"
            shift 2
            ;;
        -k | --encryption-key)
            encryption_key="$2"
            shift 2
            ;;
        -d | --terraform-dir)
            terraform_dir="$2"
            shift 2
            ;;
        -p | --project-id)
            project_id="$2"
            shift 2
            ;;
        -r | --region)
            region="$2"
            shift 2
            ;;
        -a | --app-name)
            app_name="$2"
            shift 2
            ;;
        -h | --help)
            print_usage
            return 0
            ;;
        *)
            echo "Error: Unknown parameter $1"
            print_usage
            return 1
            ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$encryption_key" || -z "$terraform_dir" || -z "$project_id" ]]; then
        echo "Error: Missing required arguments"
        print_usage
        return 1
    fi

    # Check dependencies
    if ! check_dependencies; then
        return 1
    fi

    # Validate GCP authentication
    if ! validate_gcp_auth "$project_id"; then
        return 1
    fi

    # Generate bucket name if not provided
    if [[ -z "$bucket_name" ]]; then
        bucket_name="terraform-state-bucket-${project_id}"
        echo "Generated bucket name: $bucket_name"
    else
        # If bucket name is provided, append project ID if not already present
        if [[ "$bucket_name" != *"-$project_id" ]]; then
            bucket_name="${bucket_name}-${project_id}"
            echo "Appended project ID to bucket name: $bucket_name"
        fi
    fi

    # Create bucket if it doesn't exist
    if ! create_bucket_if_not_exists "$bucket_name" "$project_id" "$region"; then
        echo "Error: Failed to create/verify bucket"
        return 1
    fi

    # Determine the absolute path of the script
    local script_path="$(
        cd "$(dirname "${BASH_SOURCE[0]}")" || exit
        pwd -P
    )"

    # Find the project root
    local root_dir="$(cd "$script_path" && while [[ "$PWD" != "/" ]]; do
        if [[ -d "$terraform_dir" && -d "scripts" ]]; then
            pwd
            break
        fi
        cd ..
    done)"

    # Get repository info
    local repo_name=$(basename -s .git "$(git config --get remote.origin.url)")
    local developer_name=${GITHUB_ACTOR:-$(git config user.name | tr -d ' ')}
    local developer_github_id=${GITHUB_ACTOR_ID:-$(gh api user 2>/dev/null | jq -r '.id')}
    local target_dir="$root_dir/$terraform_dir"
    local backend_config="$target_dir/backend-config.hcl"
    local scripts_dir="$root_dir/scripts"
    local tfvar_file="$target_dir/terraform.tfvars"
    local branch_name=""

    # Get branch or tag name
    branch_name="refs/heads/$(git rev-parse --abbrev-ref HEAD)"

    # Only use tag if we're in detached HEAD state (not on a branch)
    if [[ "$branch_name" == "refs/heads/HEAD" ]]; then
        if [ -n "$(git tag --points-at HEAD)" ]; then
            branch_name="refs/tags/$(git tag --points-at HEAD)"
        fi
    fi

    # Debug information
    echo "Configuration:"
    echo "- REPO_NAME: $repo_name"
    echo "- DEVELOPER_NAME: $developer_name"
    echo "- DEVELOPER_GITHUB_ID: $developer_github_id"
    echo "- BRANCH_NAME: $branch_name"
    echo "- ROOT_DIR: $root_dir"
    echo "- TARGET_DIR: $target_dir"
    echo "- TERRAFORM_DIR: $terraform_dir"
    echo "- BACKEND_CONFIG: $backend_config"
    echo "- SCRIPTS_DIR: $scripts_dir"
    echo "- PROJECT_ID: $project_id"
    echo "- BUCKET_NAME: $bucket_name"
    echo "- REGION: $region"
    echo "- APPLICATION_NAME: $app_name"

    # Validate terraform directory exists
    if [ ! -d "$target_dir" ]; then
        echo "Error: Directory $terraform_dir not found"
        return 1
    fi

    # Source the environment config script
    source "$scripts_dir/get_environment_config.sh"

    # Get state prefix from environment config
    output=$(get_environment_config "$repo_name" "$terraform_dir" "$branch_name" "$developer_github_id" ${app_name:+$app_name})
    echo "Environment config output: $output"

    skip=$(echo "$output" | grep "skip" | cut -d'=' -f2)
    if [ "$skip" != "true" ]; then
        state_prefix=$(echo "$output" | grep "state_prefix" | cut -d'=' -f2)
        echo "STATE_PREFIX: $state_prefix"

        # Generate backend config
        echo "Generating $backend_config..."
        cat >"$backend_config" <<EOF
bucket = "$bucket_name"
prefix = "$state_prefix"
encryption_key = "$encryption_key"
EOF
        echo "Backend config generated:"
        cat "$backend_config"

        # Source the set_env_property script
        source "$scripts_dir/set_env_property.sh"

        set_env_property --file $tfvar_file --key BASIC_SETTINGS__GCP_PROJECT_ID --value $project_id

        # Initialize terraform with backend config
        echo "Initializing Terraform..."
        if ! terraform -chdir="$target_dir" init -reconfigure -backend-config="$backend_config"; then
            echo "Error: Terraform initialization failed"
            return 1
        fi

        echo "Terraform initialization completed successfully"
    else
        echo "Skipping Terraform initialization (skip=true)"
    fi
}

# If script is being run directly (not sourced), execute with provided arguments
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
    init_terraform "$@"
fi
