#!/bin/bash

# Check if required tools are installed
command -v gh >/dev/null 2>&1 || {
    echo "Error: GitHub CLI (gh) is required but not installed."
    exit 1
}
command -v jq >/dev/null 2>&1 || {
    echo "Error: jq is required but not installed."
    exit 1
}

# Function to display usage
usage() {
    echo "Usage: $0 -s SOURCE_ENV -t TARGET_ENV -r REPOSITORY [-p PAT_TOKEN] [-u]"
    echo "Example: $0 -s dev -t uat -r myorg/myrepo"
    echo ""
    echo "Options:"
    echo "  -s SOURCE_ENV   Source environment to clone from"
    echo "  -t TARGET_ENV   Target environment to clone to"
    echo "  -r REPOSITORY   GitHub repository in format 'owner/repo'"
    echo "  -p PAT_TOKEN    GitHub Personal Access Token (optional if gh is already authenticated)"
    echo "  -u             Update existing variables (optional, default: skip existing)"
    echo "  -h             Display this help message"
    exit 1
}

# Parse command line arguments
while getopts "s:t:r:p:uh" opt; do
    case $opt in
    s) source_env="$OPTARG" ;;
    t) target_env="$OPTARG" ;;
    r) repository="$OPTARG" ;;
    p) pat_token="$OPTARG" ;;
    u) update_existing=true ;;
    h) usage ;;
    ?) usage ;;
    esac
done

# Check required parameters
if [ -z "$source_env" ] || [ -z "$target_env" ] || [ -z "$repository" ]; then
    echo "Error: Missing required parameters"
    usage
fi

# Set GitHub token if provided
if [ ! -z "$pat_token" ]; then
    export GH_TOKEN="$pat_token"
fi

# Function to ensure environment exists
ensure_environment_exists() {
    local env_name="$1"
    echo "Ensuring environment $env_name exists..."

    # Try to create the environment (ignore if it already exists)
    gh api -X PUT "/repos/$repository/environments/$env_name" --silent || {
        echo "Failed to create environment $env_name"
        return 1
    }
    echo "Environment $env_name is ready"
}

# Function to clone variables
clone_variables() {
    echo "Fetching variables from $source_env environment..."
    source_vars=$(gh variable list -e "$source_env" --json name,value -R "$repository") || true

    echo "Fetching existing variables in target environment..."
    target_vars=$(gh variable list -e "$target_env" --json name -R "$repository") || true

    if [ ! -z "$source_vars" ]; then
        echo "Processing variables..."
        echo "$source_vars" | jq -c '.[]' | while read -r var; do
            name=$(echo $var | jq -r '.name')
            value=$(echo $var | jq -r '.value')

            # Check if variable exists in target environment
            if echo "$target_vars" | jq -e --arg name "$name" '.[] | select(.name==$name)' >/dev/null; then
                if [ "$update_existing" = true ]; then
                    echo "Updating existing variable: $name"
                    gh variable set "$name" -e "$target_env" -b"$value" -R "$repository" || echo "Failed to update $name"
                else
                    echo "Skipping existing variable: $name"
                fi
            else
                echo "Creating new variable: $name"
                gh variable set "$name" -e "$target_env" -b"$value" -R "$repository" || {
                    echo "Failed to set $name"
                    # If failed, try to create environment and retry
                    if ensure_environment_exists "$target_env"; then
                        echo "Retrying to set variable $name..."
                        gh variable set "$name" -e "$target_env" -b"$value" -R "$repository" || echo "Failed to set $name again"
                    fi
                }
            fi
        done
    else
        echo "No variables found in $source_env environment or no access to list them"
    fi
}

# Function to list secrets that need to be copied
list_secrets() {
    echo "Fetching secrets from $source_env environment..."
    source_secrets=$(gh secret list -e "$source_env" --json name -R "$repository") || true

    echo "Fetching existing secrets in target environment..."
    target_secrets=$(gh secret list -e "$target_env" --json name -R "$repository") || true

    if [ ! -z "$source_secrets" ]; then
        echo -e "\n=== Secrets that need to be manually copied ==="
        echo "Please copy the following secrets from $source_env to $target_env environment:"
        echo "$source_secrets" | jq -c '.[]' | while read -r secret; do
            name=$(echo $secret | jq -r '.name')

            # Check if secret already exists in target environment
            if echo "$target_secrets" | jq -e --arg name "$name" '.[] | select(.name==$name)' >/dev/null; then
                echo "✓ Secret $name already exists in target environment"
            else
                echo "→ Secret $name needs to be copied"
            fi
        done
        echo -e "===============================================\n"
    else
        echo "No secrets found in $source_env environment or no access to list them"
    fi
}

# Main execution
echo "Starting environment clone from $source_env to $target_env for repository $repository"
echo "Update existing variables: ${update_existing:-false}"

# Ensure target environment exists before starting
if ensure_environment_exists "$target_env"; then
    clone_variables
    list_secrets
else
    echo "Failed to set up target environment. Exiting."
    exit 1
fi
