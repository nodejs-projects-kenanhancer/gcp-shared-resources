#!/bin/bash

# ============================================================================
# AWS Provider Module for Terraform Initialization
#
# Purpose: Handle AWS-specific operations for Terraform backend
# Author: Kenan Hancer
# Version: 2.0.0 (Interface Pattern)
# ============================================================================

# ============================================================================
# CONFIGURATION
# ============================================================================

AWS_DEFAULT_REGION="eu-west-2"
AWS_DEFAULT_BUCKET_PREFIX="terraform-state-bucket"
AWS_LIFECYCLE_NONCURRENT_DAYS=90
AWS_LIFECYCLE_NONCURRENT_VERSIONS=3
AWS_DEFAULT_DYNAMODB_TABLE="terraform-state-lock"

# ============================================================================
# AWS-SPECIFIC VARIABLES
# ============================================================================

# These will be set by parse_arguments
AWS_BUCKET_NAME=""
AWS_PROFILE=""
AWS_REGION=""
AWS_KMS_KEY_ID=""
AWS_DYNAMODB_TABLE=""
AWS_ACCOUNT_ID=""

# ============================================================================
# PROVIDER INTERFACE IMPLEMENTATION
# ============================================================================

# Print usage information for this provider
print_usage() {
    cat <<EOF
AWS Provider Options:
    -f, --profile NAME           AWS profile name (or use AWS_PROFILE env var) (REQUIRED)
    -b, --bucket-name NAME       Name of the S3 bucket for Terraform state storage
                                 (default: $AWS_DEFAULT_BUCKET_PREFIX-<account-id>)
    -r, --region REGION          AWS region (default: $AWS_DEFAULT_REGION)
    -k, --kms-key-id KEY        KMS key ID for S3 bucket encryption (creates new if not provided)
    -t, --dynamodb-table NAME    DynamoDB table name for state locking
                                 (default: $AWS_DEFAULT_DYNAMODB_TABLE)

AWS Examples:
    # Basic usage with AWS profile
    $SCRIPT_NAME -p aws -d terraform -f my-aws-profile

    # With custom bucket and region
    $SCRIPT_NAME -p aws -d terraform -f my-profile -b my-bucket -r us-east-1

    # With KMS key and custom DynamoDB table
    $SCRIPT_NAME -p aws -d terraform -f my-profile -k alias/terraform-key -t my-lock-table

Environment Variables:
    AWS_PROFILE                  AWS profile to use (alternative to -f option)
    AWS_REGION                   AWS region (alternative to -r option)

EOF
}

# Parse provider-specific arguments
parse_arguments() {
    AWS_REGION="${AWS_REGION:-$AWS_DEFAULT_REGION}"
    AWS_DYNAMODB_TABLE="$AWS_DEFAULT_DYNAMODB_TABLE"

    while [ $# -gt 0 ]; do
        case $1 in
        -b | --bucket-name)
            AWS_BUCKET_NAME="$2"
            shift 2
            ;;
        -f | --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        -r | --region)
            AWS_REGION="$2"
            shift 2
            ;;
        -k | --kms-key-id)
            AWS_KMS_KEY_ID="$2"
            shift 2
            ;;
        -t | --dynamodb-table)
            AWS_DYNAMODB_TABLE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown AWS parameter: $1"
            print_usage
            return 1
            ;;
        esac
    done

    # Use environment variable if profile not provided
    AWS_PROFILE="${AWS_PROFILE:-$AWS_PROFILE}"

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

    if [ -z "$AWS_PROFILE" ]; then
        missing_args+=("profile")
    fi

    # Report errors if any
    if [ ${#missing_args[@]} -gt 0 ]; then
        local missing_list=$(
            IFS=', '
            echo "${missing_args[*]}"
        )
        log_error "Missing required AWS arguments: $missing_list"
        echo # blank line for readability
        print_usage
        return 1
    fi

    return 0
}

# Check provider-specific dependencies
check_dependencies() {
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI (aws) is not installed"
        log_info "Please install it using one of these methods:"
        echo "  • macOS: Download installer from https://awscli.amazonaws.com/AWSCLIV2.pkg" >&2
        echo "  • Linux: curl \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"awscliv2.zip\"" >&2
        echo "           unzip awscliv2.zip && sudo ./aws/install" >&2
        echo "  • Windows: Download from https://awscli.amazonaws.com/AWSCLIV2.msi" >&2
        echo "  • Documentation: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" >&2
        return 1
    fi
    return 0
}

# Validate authentication
validate_auth() {
    # Check if we can get caller identity
    if ! aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log_error "Failed to authenticate with AWS using profile '$AWS_PROFILE'"
        log_info "Please check your AWS credentials and profile configuration"
        return 1
    fi

    # Get account ID for later use
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)

    return 0
}

# Ensure backend storage exists
ensure_backend_storage() {
    # Generate bucket name if needed
    AWS_BUCKET_NAME=$(generate_bucket_name "$AWS_BUCKET_NAME" "$AWS_ACCOUNT_ID")

    # Create or get KMS key
    if [ -z "$AWS_KMS_KEY_ID" ]; then
        AWS_KMS_KEY_ID=$(create_or_get_kms_key "")
    fi

    # Ensure bucket exists
    if bucket_exists "$AWS_BUCKET_NAME"; then
        log_info "AWS Bucket s3://${AWS_BUCKET_NAME} already exists"
    else
        if ! create_bucket "$AWS_BUCKET_NAME" "$AWS_KMS_KEY_ID"; then
            return 1
        fi
    fi

    # Ensure DynamoDB table exists
    if table_exists "$AWS_DYNAMODB_TABLE"; then
        log_info "DynamoDB table $AWS_DYNAMODB_TABLE already exists"
    else
        if ! create_dynamodb_table "$AWS_DYNAMODB_TABLE"; then
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
            state_key="${state_prefix}/terraform.tfstate"
        fi
    fi

    if [ -z "$state_key" ]; then
        state_key="$ARG_TERRAFORM_DIR/default/terraform.tfstate"
        log_warning "Using default state key: $state_key"
    fi

    log_info "STATE_KEY: $state_key"
    log_info "Generating AWS backend configuration..."

    cat >"$file_path" <<EOF
bucket         = "$AWS_BUCKET_NAME"
key            = "$state_key"
region         = "$AWS_REGION"
encrypt        = true
kms_key_id     = "$AWS_KMS_KEY_ID"
dynamodb_table = "$AWS_DYNAMODB_TABLE"
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
        set_env_property --file "$tfvar_file" --key aws_region --value "$AWS_REGION"
    else
        log_warning "set_env_property.sh not found, skipping tfvars update"
    fi

    return 0
}

# ============================================================================
# AWS-SPECIFIC HELPER FUNCTIONS
# ============================================================================

generate_bucket_name() {
    local bucket_name="$1"
    local account_id="$2"

    if [ -z "$bucket_name" ]; then
        bucket_name="${AWS_DEFAULT_BUCKET_PREFIX}-${account_id}"
        log_info "Generated AWS bucket name: $bucket_name"
    fi

    echo "$bucket_name"
}

bucket_exists() {
    local bucket_name="$1"

    aws s3api head-bucket --bucket "$bucket_name" --profile "$AWS_PROFILE" 2>/dev/null
}

create_lifecycle_policy() {
    local temp_file="$1"

    cat >"$temp_file" <<EOF
{
    "Rules": [
        {
            "ID": "terraform-state-lifecycle",
            "Status": "Enabled",
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": $AWS_LIFECYCLE_NONCURRENT_DAYS,
                "NewerNoncurrentVersions": $AWS_LIFECYCLE_NONCURRENT_VERSIONS
            },
            "AbortIncompleteMultipartUpload": {
                "DaysAfterInitiation": 7
            }
        }
    ]
}
EOF
}

create_bucket_policy() {
    local temp_file="$1"
    local bucket_name="$2"

    cat >"$temp_file" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EnforcedTLS",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${bucket_name}",
                "arn:aws:s3:::${bucket_name}/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
EOF
}

create_or_get_kms_key() {
    local key_alias="$1"

    # If no key alias provided, create a default one
    if [ -z "$key_alias" ]; then
        key_alias="alias/terraform-state-key"
    fi

    # Check if the key already exists
    local key_id
    key_id=$(aws kms describe-key --key-id "$key_alias" --profile "$AWS_PROFILE" --region "$AWS_REGION" --query 'KeyMetadata.KeyId' --output text 2>/dev/null || echo "")

    if [ -n "$key_id" ]; then
        log_info "Using existing KMS key: $key_alias"
        echo "$key_id"
        return 0
    fi

    # Create new key
    log_info "Creating new KMS key..."
    key_id=$(aws kms create-key \
        --description "Terraform state encryption key" \
        --key-usage ENCRYPT_DECRYPT \
        --origin AWS_KMS \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query 'KeyMetadata.KeyId' \
        --output text)

    # Create alias
    aws kms create-alias \
        --alias-name "$key_alias" \
        --target-key-id "$key_id" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"

    log_success "Created KMS key: $key_alias"
    echo "$key_id"
}

create_bucket() {
    local bucket_name="$1"
    local kms_key_id="$2"

    log_info "Creating AWS bucket s3://${bucket_name}..."

    # Create bucket
    if [ "$AWS_REGION" == "us-east-1" ]; then
        # us-east-1 doesn't accept LocationConstraint
        if ! aws s3api create-bucket \
            --bucket "$bucket_name" \
            --profile "$AWS_PROFILE"; then
            log_error "Failed to create bucket s3://${bucket_name}"
            return 1
        fi
    else
        if ! aws s3api create-bucket \
            --bucket "$bucket_name" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"; then
            log_error "Failed to create bucket s3://${bucket_name}"
            return 1
        fi
    fi

    # Enable versioning
    log_info "Enabling versioning..."
    if ! aws s3api put-bucket-versioning \
        --bucket "$bucket_name" \
        --versioning-configuration Status=Enabled \
        --profile "$AWS_PROFILE"; then
        log_warning "Failed to enable versioning on bucket s3://${bucket_name}"
    fi

    # Enable server-side encryption
    log_info "Enabling server-side encryption..."
    if ! aws s3api put-bucket-encryption \
        --bucket "$bucket_name" \
        --server-side-encryption-configuration "{
            \"Rules\": [{
                \"ApplyServerSideEncryptionByDefault\": {
                    \"SSEAlgorithm\": \"aws:kms\",
                    \"KMSMasterKeyID\": \"$kms_key_id\"
                }
            }]
        }" \
        --profile "$AWS_PROFILE"; then
        log_warning "Failed to enable encryption on bucket s3://${bucket_name}"
    fi

    # Block public access
    log_info "Blocking public access..."
    if ! aws s3api put-public-access-block \
        --bucket "$bucket_name" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
        --profile "$AWS_PROFILE"; then
        log_warning "Failed to block public access on bucket s3://${bucket_name}"
    fi

    # Set lifecycle policy
    log_info "Setting lifecycle policy..."
    local lifecycle_file="/tmp/lifecycle-$$.json"
    create_lifecycle_policy "$lifecycle_file"

    if ! aws s3api put-bucket-lifecycle-configuration \
        --bucket "$bucket_name" \
        --lifecycle-configuration file://"$lifecycle_file" \
        --profile "$AWS_PROFILE"; then
        log_warning "Failed to set lifecycle policy on bucket s3://${bucket_name}"
    fi
    rm -f "$lifecycle_file"

    # Set bucket policy
    log_info "Setting bucket policy..."
    local policy_file="/tmp/bucket-policy-$$.json"
    create_bucket_policy "$policy_file" "$bucket_name"

    if ! aws s3api put-bucket-policy \
        --bucket "$bucket_name" \
        --policy file://"$policy_file" \
        --profile "$AWS_PROFILE"; then
        log_warning "Failed to set bucket policy on s3://${bucket_name}"
    fi
    rm -f "$policy_file"

    log_success "Bucket s3://${bucket_name} created successfully"
    return 0
}

table_exists() {
    local table_name="$1"

    aws dynamodb describe-table \
        --table-name "$table_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" >/dev/null 2>&1
}

create_dynamodb_table() {
    local table_name="$1"

    log_info "Creating DynamoDB table: $table_name..."

    if ! aws dynamodb create-table \
        --table-name "$table_name" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" >/dev/null; then
        log_error "Failed to create DynamoDB table: $table_name"
        return 1
    fi

    # Wait for table to be active
    log_info "Waiting for table to become active..."
    if ! aws dynamodb wait table-exists \
        --table-name "$table_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"; then
        log_warning "Table creation might be taking longer than expected"
    fi

    log_success "DynamoDB table $table_name created successfully"
    return 0
}
