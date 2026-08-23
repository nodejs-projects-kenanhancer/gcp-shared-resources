# gcp-shared-resources

- `init_terraform` command will create or get terraform state file in GCP storage named `terraform-state-bucket-<gcp_project_id>`.
  
  `.terraform`, `.terraform.lock.hcl` and `backend-config.hcl`  will be generated. If you want to just get latest terraform state file from gcp, then remove them and run the following `init_terraform` command again, then add your terraform changes in local and run the following `terraform -chdir=terraform plan`, `chdir` parameter is directory of terraform.

## GCloud Local Profile Configurations

```bash
# Authenticate with Google Cloud using your Google account
# This opens a browser window for you to sign in
gcloud auth login # Login with your gcp account

gcloud auth application-default login --account=$(gcloud config get-value account)

# List all GCP projects you have access to
# Shows PROJECT_ID, NAME, and PROJECT_NUMBER for each project
gcloud projects list

# Create a new configuration profile with a specific name
# Configurations let you switch between different projects/accounts easily
# Replace <GCP-PROJECT-ID> with your actual project ID (e.g., my-dev-project)
gcloud config configurations create <GCP-PROJECT-ID>

# Switch to and activate a specific configuration
# Makes this configuration the current active one
# Replace <GCP-PROJECT-ID> with your configuration name
gcloud config configurations activate <GCP-PROJECT-ID>

# Set the Google account for the current configuration
# Replace <EMAIL> with your Google account email (e.g., user@gmail.com)
gcloud config set account <EMAIL>

# Set the default project for the current configuration
# All gcloud commands will use this project unless specified otherwise
# Replace <GCP-PROJECT-ID> with your actual GCP project ID
gcloud config set project <GCP-PROJECT-ID>

# Display all settings for the current active configuration
# Shows account, project, region, zone, and other configured properties
gcloud config list

# List all available configurations
# Shows which configuration is currently active (marked with IS_ACTIVE)
# Displays NAME, IS_ACTIVE, ACCOUNT, PROJECT, COMPUTE_DEFAULT_ZONE, COMPUTE_DEFAULT_REGION
gcloud config configurations list
```

## Typical Workflow Example

```bash
# 1. Set gcloud CLI authentication
gcloud auth login

# 2. See what projects you have access to
gcloud projects list

# 3. Create a configuration for your dev environment
gcloud config configurations create my-dev-project

# 4. Set up the configuration
gcloud config set account john@example.com
gcloud config set project my-dev-project-123456
gcloud config set compute/region us-central1
gcloud config set compute/zone us-central1-a

# 5. Set Application Default Credentials (ADC) to match current config
# This is REQUIRED for tools like:
# - Terraform (terraform init/plan/apply)
# - Python scripts using google-cloud libraries
# - Node.js apps using @google-cloud packages
# - Docker with GCR authentication
# - Any application using GCP SDKs
# Without this, these tools will fail with authentication errors!
gcloud auth application-default login --account=$(gcloud config get-value account)

# 6. Verify your configuration
gcloud config list

# 7. Create another configuration for production
gcloud config configurations create my-prod-project
gcloud config set account john@example.com
gcloud config set project my-prod-project-789012

# 8. Switch between configurations as needed
gcloud config configurations activate my-dev-project  # Switch to dev
gcloud auth application-default login --account=$(gcloud config get-value account)  # Sync ADC

gcloud config configurations activate my-prod-project # Switch to prod
gcloud auth application-default login --account=$(gcloud config get-value account)  # Sync ADC

# 9. See all your configurations
gcloud config configurations list
```

## Terraform Deployment from local

This terraform provisions the shared GCP resources (storage buckets, Pub/Sub topics, secrets, Bigtable, and the shared runtime service account) that the application repositories consume.

The state encryption key is NOT stored in the repository. `init_terraform.sh` resolves it from Secret Manager automatically and generates it on the very first run in a fresh project. See [Encryption key management](#encryption-key-management) below.

```bash
cd ./gcp-shared-resources
gcp_project_id=medallion-dev-463909
region=europe-west2
terraform_dir=terraform

./scripts/init_terraform.sh \
  -p gcp \
  -i $gcp_project_id \
  -r $region \
  -d $terraform_dir

terraform -chdir=$terraform_dir plan
terraform -chdir=$terraform_dir apply
```

> The GitHub Actions identity (Workload Identity Federation pool/provider and `github-actions-sa`) is provisioned separately by the [gitflow-shared-workflows](https://github.com/nodejs-projects-kenanhancer/gitflow-shared-workflows) repository (`github-actions-resources-terraform/`), which also uses `scripts/check_and_import_resources.sh` to import soft-deleted pools back into state.

### Encryption key management

The GCS backend encrypts terraform state with a customer-supplied encryption key. The key never lives in git; `init_terraform.sh` resolves it in this order:

1. `-k` flag: explicit override.
2. `TF_STATE_ENCRYPTION_KEY` environment variable (used by CI, populated from a GitHub secret).
3. Secret Manager secret named `<state-bucket>-encryption-key`: read if present, **generated and stored automatically on first use** in a fresh project.

Because the secret is scoped to the state bucket, every repository sharing that bucket converges on the same key with zero coordination. To onboard another developer, grant access instead of sharing the key value:

```bash
gcloud secrets add-iam-policy-binding terraform-state-bucket-<project-id>-encryption-key \
  --project=<project-id> \
  --member="user:dev@example.com" \
  --role="roles/secretmanager.secretAccessor"
```

## GCP CLI Commands Quick Reference

### Project Management

```bash
gcloud config list                                        # View current configuration
gcloud config set project <GCP-PROJECT-ID>                    # Switch active project
gcloud config configurations create <CONFIGURATION_NAME>
```

```bash
gcloud projects list # List all projects

PROJECT_ID            NAME           PROJECT_NUMBER
glossy-hangar-6g582                  851161057186
medallion-dev-463909  Medallion Dev  368539885233
```

### IAM & Service Accounts

```bash
# List and Describe
gcloud iam service-accounts list                                    # List service accounts
gcloud iam service-accounts describe <SERVICE-ACCOUNT-EMAIL>        # Get details of a service account
gcloud iam service-accounts get-iam-policy <SERVICE-ACCOUNT-EMAIL>  # Get IAM policy for service account
gcloud iam roles list --project=<GCP-PROJECT-ID>                        # List IAM roles
gcloud projects get-iam-policy                                      # View project IAM policy

# Enable/Disable
gcloud iam service-accounts enable <SERVICE-ACCOUNT-EMAIL>         # Enable service account
gcloud iam service-accounts disable <SERVICE-ACCOUNT-EMAIL>        # Disable service account

# Update
gcloud iam service-accounts update <SERVICE-ACCOUNT-EMAIL> \       # Update display name
    --display-name="New Display Name"

# Create and Delete
gcloud iam service-accounts create <ACCOUNT-ID>                    # Create new service account
gcloud iam service-accounts delete <SERVICE-ACCOUNT-EMAIL>         # Delete service account

# Keys Management
gcloud iam service-accounts keys list \                            # List keys for service account
    --iam-account=<SERVICE-ACCOUNT-EMAIL>
gcloud iam service-accounts keys create key.json \                 # Create new key
    --iam-account=<SERVICE-ACCOUNT-EMAIL>
cat key.json | base64                                              # Display key content (for GitHub secret)

gcloud iam service-accounts keys create - \                        # To print out  directly to terminal
    --iam-account=<SERVICE-ACCOUNT-EMAIL> \
    --format='get(privateKeyData)'
gcloud iam service-accounts keys delete <KEY-ID> \                 # Delete key
    --iam-account=<SERVICE-ACCOUNT-EMAIL>

# IAM Policy
gcloud projects add-iam-policy-binding <GCP-PROJECT-ID> \              # Grant role to service account
    --member="serviceAccount:<SERVICE-ACCOUNT-EMAIL>" \
    --role="<ROLE-ID>"
```

### Storage Operations

```bash
gsutil ls                                  # List buckets
gsutil ls gs://<BUCKET-NAME>               # List bucket contents
gsutil cp <FILE> gs://<BUCKET-NAME>        # Upload file
```

### Compute Engine

```bash
gcloud compute instances list [NAMES]      # List VM instances
gcloud compute zones list                  # List available zones
gcloud compute images list                 # List available images
```

### Kubernetes (GKE)

```bash
gcloud container clusters list                              # List GKE clusters
gcloud container clusters get-credentials <CLUSTER-NAME>    # Configure kubectl
```

### Common Options

- `--project=<GCP-PROJECT-ID>`: Specify project
- `--format=[json|yaml]`: Change output format
- `--filter="<EXPRESSION>"`: Filter results

### Configuration Info

```bash
gcloud info                               # Display SDK configuration details
```

### Tips

- Use `gcloud help <COMMAND>` for detailed documentation
- Add `--quiet` or `-q` to skip confirmation prompts
- Use `--format=json | jq` for JSON parsing

### Environment Setup

```bash
gcloud init                               # Initialize configuration
gcloud auth login                         # Authenticate account
```

### Workload Identity Pool(WIP)

```bash
gcloud iam workload-identity-pools list \
  --location=global \
  --project=<GCP-PROJECT-ID>
```

```bash
gcloud iam workload-identity-pools list \
  --project=<GCP-PROJECT-ID> \
  --location=global \
  --show-deleted
```

- Undelete pool:

    ```bash
    gcloud iam workload-identity-pools undelete \
    projects/<GCP-PROJECT-NUMBER>/locations/global/workloadIdentityPools/github-id-pool
    ```

- Import it into Terraform:

    ```bash
    terraform import \
        google_iam_workload_identity_pool.github_pool \
        projects/<GCP-PROJECT-NUMBER>/locations/global/workloadIdentityPools/github-id-pool

    ```

### Workload Identity Pool(WIP) Provider

```bash
gcloud iam workload-identity-pools providers list \
  --workload-identity-pool=projects/<GCP-PROJECT-NUMBER>/locations/global/workloadIdentityPools/github-id-pool \
  --location=global \
  --project=<GCP-PROJECT-ID>
```

```bash
gcloud iam workload-identity-pools providers list \
  --project=<GCP-PROJECT-ID> \
  --location=global \
  --workload-identity-pool=github-id-pool \
  --show-deleted
```

```bash
gcloud iam workload-identity-pools providers undelete \
  projects/<GCP-PROJECT-NUMBER>/locations/global/workloadIdentityPools/github-id-pool/providers/github-id-pool-provider
```

## Git hooks

The pre-commit hook runs the scripts test suite (`scripts/tests/run_tests.sh`).
Enable it once per clone:

```bash
git config core.hooksPath .husky
```
