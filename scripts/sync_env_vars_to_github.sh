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

clean_environment=false
# Function to display usage
usage() {
    echo "Usage: $0 -t TARGET_ENV -r REPOSITORY [-p PAT_TOKEN]"
    echo "Example: $0 -t uat -r myorg/myrepo"
    echo ""
    echo "Options:"
    echo "  -t TARGET_ENV       Target environment to clone"
    echo "  -r REPOSITORY       GitHub repository in format 'owner/repo'"
    echo "  -p PAT_TOKEN        GitHub Personal Access Token (optional if gh is already authenticated)"
    echo "  -c Clean_Environment Clean Github Environment before cloning variables, default is false"
    echo "  -h                  Display this help message"
    exit 1
}

# Parse command line arguments
while getopts "t:r:p:ch" opt; do
    case $opt in
    t) target_env="$OPTARG" ;;
    r) repository="$OPTARG" ;;
    p) pat_token="$OPTARG" ;;
    c) clean_environment=true ;;
    h) usage ;;
    ?) usage ;;
    esac
done

if [ -z "$target_env" ] || [ -z "$repository" ]; then
    echo "Error: Missing required parameters"
    usage
fi

# Set GitHub token if provided
if [ -n "$pat_token" ]; then
    export GH_TOKEN="$pat_token"
fi

# Check if environment exists
check_environment_exists() {
    echo "Checking if environment '$target_env' exists in repository '$repository'..."
    envs=$(gh api repos/"$repository"/environments --jq '.environments[].name')

    if echo "$envs" | grep -Fxq "$target_env"; then
        echo "✅ Environment '$target_env' exists."
        return 0
    else
        echo "❌ Error: Environment '$target_env' does not exist in $repository."
        return 1
    fi
}

# Function to clone variables from environment.json
clone_variables() {
    local file_path="envs/$target_env.json"

    if [ ! -f "$file_path" ]; then
        echo "❌ Error: File '$file_path' not found."
        exit 1
    fi

    if [ "$clean_environment" = true ]; then
        echo "Removing all extisting variables in '$repository' for environment '$target_env'..."
        gh variable list --repo "$repository" --env "$target_env" \
            --json name |
            jq -r '.[].name' |
            while read -r name; do
                echo "🔧 Removing variable: $name"
                gh variable delete "$name" --repo "$repository" --env "$target_env"
            done
    fi

    echo "Setting environment variables in '$repository' for environment '$target_env' from $file_path..."

    jq -r 'to_entries[] | .key' "$file_path" | while read -r key; do
        value=$(jq -r --arg k "$key" '.[$k]' "$file_path")

        if [ -z "$value" ]; then
            echo "⚠️  Warning: No value found for key $key. Skipping..."
            continue
        fi

        echo "🔧 Setting variable: $key"
        gh variable set "$key" \
            --repo "$repository" \
            --env "$target_env" \
            --body "$value"
    done

    echo "✅ All variables from $file_path have been set."
}

# Main flow
if check_environment_exists; then
    clone_variables
else
    echo "❌ Failed to find target environment. Exiting."
    exit 1
fi
