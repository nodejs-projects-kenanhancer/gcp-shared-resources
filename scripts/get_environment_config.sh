#!/bin/bash
get_environment_config() {
    if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
        echo "Usage: get_environment_config <repository-name> <terraform-dir> <branch-name> <developer-name> [application-name]" >&2
        return 1
    fi

    local REPOSITORY_NAME=$1
    local TERRAFORM_DIR=$2
    local BRANCH_NAME=$3
    local DEVELOPER_NAME=$4
    local APPLICATION_NAME=$5

    get_state_prefix() {
        local env=$1
        local suffix=$2

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

    case $BRANCH_NAME in
    refs/tags/*)
        echo "environment_name=prod"
        echo "state_prefix=$(get_state_prefix prod)"
        echo "skip=false"
        echo "branch_name=tag"
        ;;
    refs/heads/main)
        echo "environment_name=preprod"
        echo "state_prefix=$(get_state_prefix preprod)"
        echo "skip=false"
        echo "branch_name=main"
        ;;
    refs/heads/feature/*)
        local FEATURE_NAME=$(echo $BRANCH_NAME | sed 's/refs\/heads\/feature\///' | tr '/' '-')
        echo "environment_name=${DEVELOPER_NAME}-${FEATURE_NAME}"
        echo "state_prefix=$(get_state_prefix features "${DEVELOPER_NAME}/${FEATURE_NAME}")"
        echo "skip=false"
        echo "branch_name=feature"
        ;;
    refs/heads/release/*)
        echo "environment_name=uat"
        echo "state_prefix=$(get_state_prefix uat)"
        echo "skip=false"
        echo "branch_name=release"
        ;;
    refs/heads/hotfix/*)
        echo "environment_name=hotfix"
        echo "state_prefix=$(get_state_prefix hotfix)"
        echo "skip=false"
        echo "branch_name=hotfix"
        ;;
    refs/heads/develop | refs/heads/dev)
        echo "environment_name=dev"
        echo "state_prefix=$(get_state_prefix dev)"
        echo "skip=false"
        echo "branch_name=dev"
        ;;
    esac
}
