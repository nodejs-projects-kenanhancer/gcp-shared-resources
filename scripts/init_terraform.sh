#!/bin/bash

# ============================================================================
# Terraform Initialization Script - Main Controller
#
# Purpose: Initialize Terraform with cloud provider backends
# Author: Kenan Hancer
# Version: 5.0.0 (Interface Pattern)
# ============================================================================

# Use defensive programming - compatible with older bash versions
set -e # Exit on error

# ============================================================================
# CONFIGURATION
# ============================================================================

# Script metadata
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
PROVIDERS_DIR="$SCRIPT_DIR/providers"

# Supported providers
SUPPORTED_PROVIDERS=("gcp" "aws" "azure")

# Global variables for argument parsing
REMAINING_ARGS=()

join_array() {
    local delimiter="${1}"
    shift # Remove delimiter from arguments
    local IFS="$delimiter"
    echo "$*"
}

# ============================================================================
# COLOR INITIALIZATION
# ============================================================================

# Initialize color variables based on terminal support
init_colors() {
    # Check if terminal supports colors
    if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
        COLOR_RED=$(tput setaf 1)
        COLOR_GREEN=$(tput setaf 2)
        COLOR_YELLOW=$(tput setaf 3)
        COLOR_BLUE=$(tput setaf 4)
        COLOR_RESET=$(tput sgr0)
    else
        COLOR_RED=""
        COLOR_GREEN=""
        COLOR_YELLOW=""
        COLOR_BLUE=""
        COLOR_RESET=""
    fi
}

# Initialize colors when script loads
init_colors

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_error() {
    echo "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

log_success() {
    echo "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $*" >&2
}

log_info() {
    echo "${COLOR_BLUE}[INFO]${COLOR_RESET} $*" >&2
}

log_warning() {
    echo "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $*" >&2
}

# ============================================================================
# USAGE AND HELP
# ============================================================================

print_main_usage() {
    cat <<EOF
Description:
    Initializes Terraform configuration with cloud provider remote state backend

Usage:
    $SCRIPT_NAME [OPTIONS]

Required Options:
    -p, --provider PROVIDER      Cloud provider (gcp, aws, azure)
    -d, --terraform-dir DIR      Directory containing Terraform configuration files

Provider-specific options vary. Use -h with provider to see details:
    $SCRIPT_NAME -p gcp -h
    $SCRIPT_NAME -p aws -h
    $SCRIPT_NAME -p azure -h

Common Options:
    -a, --app-name NAME          Application name for state prefix
    -h, --help                   Show this help message

Examples:
    # GCP initialization
    $SCRIPT_NAME -p gcp -d terraform -k my-key -i my-project

    # AWS initialization
    $SCRIPT_NAME -p aws -d terraform -f my-profile

    # Azure initialization
    $SCRIPT_NAME -p azure -d terraform -s my-subscription-id

Environment Variables:
    GITHUB_ACTOR                 GitHub username (used for developer identification)
    GITHUB_ACTOR_ID             GitHub user ID (used for state prefix generation)

EOF
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

# Function to check for required commands
# Usage: check_dependencies "command1" "command2" ...
check_common_dependencies() {
    local missing_deps=()
    local required_commands=("$@")

    # If no arguments provided, show usage
    if [ ${#required_commands[@]} -eq 0 ]; then
        echo "Error: No commands specified to check"
        echo "Usage: check_common_dependencies \"command1\" \"command2\" ..."
        return 1
    fi

    # Check each required command
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    # Report missing dependencies
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "Error: Required commands not found: ${missing_deps[*]}"
        echo "Please install the missing dependencies and try again."
        return 1
    fi

    return 0
}

validate_provider() {
    local provider="$1" # Fixed: removed asterisks

    # Check if provider is empty
    if [ -z "$provider" ]; then
        log_error "Provider not specified"
        print_main_usage
        return 1
    fi

    local valid=0

    for p in "${SUPPORTED_PROVIDERS[@]}"; do
        if [ "$p" = "$provider" ]; then
            valid=1
            break
        fi
    done

    if [ $valid -eq 0 ]; then
        log_error "Unsupported provider: $provider"
        log_info "Supported providers: $(join_array ',' "${SUPPORTED_PROVIDERS[@]}")"
        return 1
    fi

    return 0
}

# ============================================================================
# GIT FUNCTIONS
# ============================================================================

get_git_reference() {
    local ref_name=""
    local ref_type=""

    if ref_name=$(git symbolic-ref HEAD 2>/dev/null); then
        ref_type="branch"
    elif tag_name=$(git describe --tags --exact-match 2>/dev/null); then
        ref_name="refs/tags/${tag_name}"
        ref_type="tag"
    else
        commit_sha=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        ref_name="refs/commits/${commit_sha}"
        ref_type="commit"
    fi

    echo "ref_name=$ref_name"
    echo "ref_type=$ref_type"
}

get_repository_info() {
    local repo_url
    local repo_name

    repo_url=$(git config --get remote.origin.url 2>/dev/null || echo "unknown")
    repo_name=$(basename "$repo_url" .git)

    echo "$repo_name"
}

# ============================================================================
# PROJECT STRUCTURE FUNCTIONS
# ============================================================================

find_project_root() {
    local current_dir="$1"
    local terraform_dir="$2"

    while [ "$current_dir" != "/" ]; do
        if [ -d "$current_dir/$terraform_dir" ] && [ -d "$current_dir/scripts" ]; then
            echo "$current_dir"
            return 0
        fi
        current_dir=$(dirname "$current_dir")
    done

    return 1
}

# ============================================================================
# TERRAFORM FUNCTIONS
# ============================================================================

run_terraform_init() {
    local terraform_dir="$1"
    local backend_config="$2"

    log_info "Initializing Terraform..."

    if ! terraform -chdir="$terraform_dir" init -reconfigure -backend-config="$backend_config"; then
        log_error "Terraform initialization failed"
        return 1
    fi

    log_success "Terraform initialization completed successfully"
    return 0
}

# ============================================================================
# PROVIDER INTERFACE
# ============================================================================

# Define the provider interface - these functions must be implemented by each provider
# - print_usage()
# - parse_arguments()
# - validate_required_args()
# - check_dependencies()
# - validate_auth()
# - ensure_backend_storage()
# - generate_backend_config()
# - update_tfvars()

load_provider() {
    local provider="$1"
    local provider_script="$PROVIDERS_DIR/${provider}_provider.sh"

    if [ ! -f "$provider_script" ]; then
        log_error "Provider script not found: $provider_script"
        return 1
    fi

    # Set the current provider for logging/debugging
    export CURRENT_PROVIDER="$provider"

    # Source the provider script (this will define the interface functions)
    . "$provider_script"

    # Verify required functions exist
    local required_functions=(
        "print_usage"
        "parse_arguments"
        "validate_required_args"
        "check_dependencies"
        "validate_auth"
        "ensure_backend_storage"
        "generate_backend_config"
        "update_tfvars"
    )

    for func in "${required_functions[@]}"; do
        if ! type -t "$func" >/dev/null; then
            log_error "Provider $provider missing required function: $func"
            return 1
        fi
    done

    return 0
}

# EXAMPLES:
#   # Basic usage
#   config=$(get_environment_config "my-repo" "terraform" "refs/heads/main" "kenan")
#
#   # With application name
#   config=$(get_environment_config "shared-infra" "terraform" "refs/heads/feature/add-s3" "kenan" "storage-app")
#
#   # Parse the JSON output
#   env_name=$(echo "$config" | jq -r '.environment_name')
#   state_prefix=$(echo "$config" | jq -r '.state_prefix')
#   should_skip=$(echo "$config" | jq -r '.skip')
get_environment_config_output() {
    local scripts_dir="$1"
    local repo_name="$2"
    local terraform_dir="$3"
    local branch_name="$4"
    local developer_github_id="$5"
    local app_name="$6"

    if [ -f "$scripts_dir/get_environment_config.sh" ]; then
        . "$scripts_dir/get_environment_config.sh"

        local env_config
        env_config=$(get_environment_config "$repo_name" "$terraform_dir" "$branch_name" "$developer_github_id" "$app_name")

        echo "$env_config"
    fi
}

# ============================================================================
# PROJECT METADATA FUNCTIONS
# ============================================================================

# Functional approach to gather project metadata and return JSON data
# Returns: JSON object on stdout, logs on stderr
# Usage example:
#   context=$(get_project_context "$scripts_dir" "$terraform_dir" "$app_name")
#   repo_name=$(echo "$context" | jq -r '.repo_name')
#   should_skip=$(echo "$context" | jq -r '.should_skip')
get_project_context() {
    local scripts_dir="$1"
    local terraform_dir="$2"
    local app_name="$3"

    # Get repository info
    local repo_name
    repo_name=$(get_repository_info)

    # Get Git reference info
    local git_ref_info
    git_ref_info=$(get_git_reference)
    local branch_name
    branch_name=$(echo "$git_ref_info" | grep "ref_name" | cut -d'=' -f2)
    local ref_type
    ref_type=$(echo "$git_ref_info" | grep "ref_type" | cut -d'=' -f2)

    # Get developer info
    local developer_name="${GITHUB_ACTOR:-$(git config user.name 2>/dev/null | tr -d ' ' || echo "unknown")}"
    local developer_id="${GITHUB_ACTOR_ID:-}"

    # Try to get GitHub ID if not set
    if [ -z "$developer_id" ] && command -v gh >/dev/null 2>&1; then
        developer_id=$(gh api user 2>/dev/null | grep '"id"' | head -1 | sed 's/.*: *\([0-9]*\).*/\1/' || echo "")
    fi

    # Get environment config
    local env_config
    env_config=$(get_environment_config_output "$scripts_dir" "$repo_name" "$terraform_dir" "$branch_name" "$developer_id" "$app_name")

    log_info "Environment configuration:"
    echo "$env_config" | jq '.' >&2

    local skip=$(echo "$env_config" | jq -r '.skip')

    # Output as JSON using jq for proper escaping and formatting
    jq -n \
        --arg repo_name "$repo_name" \
        --arg branch_name "$branch_name" \
        --arg ref_type "$ref_type" \
        --arg developer_name "$developer_name" \
        --arg developer_id "$developer_id" \
        --arg should_skip "$skip" \
        --argjson env_config "$env_config" \
        '{
            repo_name: $repo_name,
            branch_name: $branch_name,
            ref_type: $ref_type,
            developer_name: $developer_name,
            developer_id: $developer_id,
            should_skip: $should_skip,
            env_config: $env_config
        }'
}

# ============================================================================
# MAIN FUNCTIONS
# ============================================================================

parse_common_arguments() {
    # Initialize global variables
    ARG_PROVIDER=""
    ARG_TERRAFORM_DIR=""
    ARG_APP_NAME=""
    ARG_HELP=0
    REMAINING_ARGS=()

    # Parse only common arguments first
    while [ $# -gt 0 ]; do
        case $1 in
        -p | --provider)
            ARG_PROVIDER="$2"
            shift 2
            ;;
        -d | --terraform-dir)
            ARG_TERRAFORM_DIR="$2"
            shift 2
            ;;
        -a | --app-name)
            ARG_APP_NAME="$2"
            shift 2
            ;;
        -h | --help)
            ARG_HELP=1
            shift
            ;;
        *)
            # Keep unknown arguments for provider-specific parsing
            REMAINING_ARGS+=("$1")
            shift
            ;;
        esac
    done
}

process_arguments() {
    # Handle help without provider
    if [ "$ARG_HELP" = "1" ] && [ -z "$ARG_PROVIDER" ]; then
        print_main_usage
        exit 0
    fi

    # Validate provider
    validate_provider "$ARG_PROVIDER" || return 1

    # Load provider module early to enable provider-specific help
    load_provider "$ARG_PROVIDER" || return 1

    # Show provider-specific help if requested
    if [ "$ARG_HELP" = "1" ]; then
        print_usage
        exit 0
    fi

    # Validate terraform directory is provided (common requirement)
    if [ -z "$ARG_TERRAFORM_DIR" ]; then
        log_error "Terraform directory not specified"
        print_usage # Show provider-specific usage since provider is loaded
        return 1
    fi

    # Validate app-name format if provided (optional validation)
    if [ -n "$ARG_APP_NAME" ]; then
        # Example: Ensure app name contains only alphanumeric, hyphens, underscores
        if ! echo "$ARG_APP_NAME" | grep -qE '^[a-zA-Z0-9_-]+$'; then
            log_error "Invalid app name format. Use only alphanumeric characters, hyphens, and underscores"
            return 1
        fi
    fi

    # Validate we're in a git repository (since the script heavily relies on git)
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "Not in a git repository. This script must be run from within a git repository"
        return 1
    fi

    # Validate remaining args don't contain common mistakes
    # Define known provider flags for better maintainability
    local KNOWN_SHORT_FLAGS="k|i|f|s|r|g|b|e|v|n|location"
    local KNOWN_LONG_FLAGS="key-file|project-id|profile|subscription-id|resource-group|storage-account-name|bucket|env|var-file|dry-run"

    # Validate remaining args don't contain common mistakes
    for arg in "${REMAINING_ARGS[@]}"; do
        case "$arg" in
        -*)
            # Check for common typos or unknown flags
            if [[ ! "$arg" =~ ^-($KNOWN_SHORT_FLAGS)$ ]] &&
                [[ ! "$arg" =~ ^--($KNOWN_LONG_FLAGS)$ ]]; then
                log_warning "Unknown option: $arg (this will be passed to provider)"
            fi
            ;;
        esac
    done

    return 0
}

init_terraform() {
    # Parse common arguments
    parse_common_arguments "$@"

    # Validate all arguments (handles help, provider validation, loading, etc.)
    process_arguments || return 1

    # Check common dependencies
    check_common_dependencies "terraform" "git" "jq" || return 1

    # Check provider-specific dependencies (provider-specific)
    check_dependencies || return 1

    # Parse provider-specific arguments (provider-specific)
    parse_arguments "${REMAINING_ARGS[@]}" || return 1

    # Validate required arguments (provider-specific)
    validate_required_args "$ARG_TERRAFORM_DIR" || return 1

    # Validate provider authentication (provider-specific)
    validate_auth || return 1

    # Find project root
    local root_dir
    if ! root_dir=$(find_project_root "$SCRIPT_DIR" "$ARG_TERRAFORM_DIR"); then
        log_error "Could not find project root (looking for $ARG_TERRAFORM_DIR and scripts directories)"
        return 1
    fi

    # Set up paths
    local target_dir="$root_dir/$ARG_TERRAFORM_DIR"
    local backend_config="$target_dir/backend-config.hcl"
    local scripts_dir="$root_dir/scripts"
    local tfvar_file="$target_dir/terraform.tfvars"

    # Get project context as JSON
    local project_context
    project_context=$(get_project_context "$scripts_dir" "$ARG_TERRAFORM_DIR" "$ARG_APP_NAME")

    local should_skip=$(echo "$project_context" | jq -r '.should_skip')

    # Check if we should skip initialization
    if [ "$should_skip" = "true" ]; then
        return 0
    fi

    # Extract env_config as JSON object directly
    local env_config=$(echo "$project_context" | jq '.env_config')

    # Ensure backend storage exists (provider-specific)
    ensure_backend_storage || return 1

    # Generate backend config (provider-specific)
    generate_backend_config "$backend_config" "$env_config" || return 1

    # Update terraform.tfvars (provider-specific)
    update_tfvars "$tfvar_file" "$scripts_dir" || return 1

    # Initialize Terraform
    run_terraform_init "$target_dir" "$backend_config"
}

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

main() {
    init_terraform "$@"
}

# Execute main function if script is run directly
main "$@"
