#!/bin/bash

get_environment_config() {
    if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
        echo "Usage: get_environment_config <repository-name> <terraform-dir> <branch-name> <developer-name> [application-name]" >&2
        return 1
    fi

    local REPOSITORY_NAME="$1"
    local TERRAFORM_DIR="$2"
    local BRANCH_NAME="$3"
    local DEVELOPER_NAME="$4"
    local APPLICATION_NAME="$5"

    # Helper function to get state prefix
    get_state_prefix() {
        local env="$1"
        local suffix="$2"
        local base_path=""

        if [[ -n "$APPLICATION_NAME" ]]; then
            base_path="${env}/${REPOSITORY_NAME}/${APPLICATION_NAME}/${TERRAFORM_DIR}"
        else
            base_path="${env}/${REPOSITORY_NAME}/${TERRAFORM_DIR}"
        fi

        # Append suffix if provided
        if [[ -n "$suffix" ]]; then
            echo "${base_path}/${suffix}"
        else
            echo "${base_path}"
        fi
    }

    # Initialize variables
    local environment_name=""
    local state_prefix=""
    local skip="false"
    local branch_type=""
    local feature_name=""

    # Determine configuration based on branch name
    case $BRANCH_NAME in
    refs/tags/*)
        environment_name="prod"
        state_prefix=$(get_state_prefix prod)
        branch_type="tag"
        ;;

    refs/heads/main)
        environment_name="preprod"
        state_prefix=$(get_state_prefix preprod)
        branch_type="main"
        ;;

    refs/heads/feature/*)
        feature_name=$(echo $BRANCH_NAME | sed 's/refs\/heads\/feature\///' | tr '/' '-')
        environment_name="${DEVELOPER_NAME}-${feature_name}"
        state_prefix=$(get_state_prefix features "${DEVELOPER_NAME}/${feature_name}")
        branch_type="feature"
        ;;

    refs/heads/release/*)
        environment_name="uat"
        state_prefix=$(get_state_prefix uat)
        branch_type="release"
        ;;

    refs/heads/hotfix/*)
        environment_name="hotfix"
        state_prefix=$(get_state_prefix hotfix)
        branch_type="hotfix"
        ;;

    refs/heads/develop | refs/heads/dev)
        environment_name="dev"
        state_prefix=$(get_state_prefix dev)
        branch_type="dev"
        ;;

    *)
        # Unknown branch pattern
        environment_name="unknown"
        state_prefix=""
        skip="true"
        branch_type="unknown"
        ;;
    esac

    # Generate JSON output using jq
    jq -n \
        --arg env_name "$environment_name" \
        --arg state_pfx "$state_prefix" \
        --arg skip_flag "$skip" \
        --arg branch_t "$branch_type" \
        --arg repo "$REPOSITORY_NAME" \
        --arg tf_dir "$TERRAFORM_DIR" \
        --arg branch "$BRANCH_NAME" \
        --arg dev "$DEVELOPER_NAME" \
        --arg app "$APPLICATION_NAME" \
        --arg feat "$feature_name" \
        '{
            environment_name: $env_name,
            state_prefix: $state_pfx,
            skip: ($skip_flag == "true"),
            branch_type: $branch_t,
            metadata: {
                repository_name: $repo,
                terraform_dir: $tf_dir,
                branch_name: $branch,
                developer_name: $dev,
                application_name: (if $app == "" then null else $app end),
                feature_name: (if $feat == "" then null else $feat end)
            }
        }'
}
