# Multi-Cloud Shared Resources — Design & Migration Plan

> **Status:** Approved design, implementation NOT started
> **Date:** 2026-08-26
> **Author:** Kenan Hancer + Claude (Claude Code session)
> **Purpose:** Complete handoff document. A future session must be able to resume
> implementation from this file alone, without re-deriving any analysis.

---

## 1. Executive Summary

The goal is to deploy shared platform resources to **AWS, GCP and Azure** from a
**single new repository** (working name: `shared-resources`) containing one
Terraform tree per cloud, reusing the existing gitflow/scripts/CI machinery,
which is already ~80% cloud-agnostic. AWS is the first cloud to add; Azure
follows later. The existing `gcp-shared-resources` repo's terraform content
migrates into the new repo as `terraform/gcp/` and the old repo gets archived.

Timing is ideal: on 2026-08-23 the GCP project was intentionally reset to a
clean slate (no state bucket, no terraform-managed resources), so this
restructuring requires **zero state migration**.

---

## 2. Repository Ecosystem (as of 2026-08-26)

All repos are under the public GitHub org `nodejs-projects-kenanhancer`.

| Repo | Role | Local path | Last relevant commit |
|---|---|---|---|
| `gcp-shared-resources` | GCP platform terraform (buckets, Pub/Sub, secrets, IAM, Bigtable) + canonical scripts | `~/Documents/projects/gcp-shared-resources` | `578c19b` |
| `gitflow-shared-workflows` (SW) | Central reusable workflows (6) + WIF bootstrap terraform (`github-actions-resources-terraform/`) + scripts copy | `~/Documents/projects/nodejs-projects-kenanhancer/gitflow-shared-workflows` | `769cf05` |
| `gcp-cloudrun-function-pubsub-triggered` | App repo (generated from cookiecutter) | no local clone (was in scratchpad) | `0aa57c3` |
| `gcp-cloudrun-service-kafka-consumer` | App repo (generated from cookiecutter) | no local clone | `a7c1055` |
| `gcp-typescript-cloudrun-function-cookiecutter-template` | Scaffolding template ("harness") for app repos | no local clone | `6d5ce55` |
| `aws-cdk-shared-resources` | AWS **CDK** port of the GCP terraform (reference implementation) | `~/Documents/projects/nodejs-projects-kenanhancer/aws-cdk-shared-resources` | `696e53c` |

### Shared conventions (all designed by Kenan, all still in force)

- **Gitflow branch → environment mapping:** tag `v*.*.*` → `prod`, `main` →
  `preprod`, `dev` → `dev`, `release/*` → `uat`, `hotfix/*` → `hotfix`,
  `feature/x` → `{github_actor_id}-x` (ephemeral per-developer env).
- **State prefixes:** `{env}/{repo}[/{app}]/{terraform_dir}` (from
  `scripts/get_environment_config.sh`, emits JSON, parsed with `jq`).
- **Config injection in CI:** GitHub env vars/secrets prefixed `TFVAR_` are
  merged over any committed tfvars via hcl2json + jq, `__PLACEHOLDER__` tokens
  substituted from `GITVAR_*`/secrets, then `convert_json_to_hcl.py` writes the
  final `terraform.tfvars`. `GITVAR_*` = pipeline config (project id, region,
  state bucket...).
- **Thin caller workflow pattern:** each repo has a small
  `gitflow-terraform-deploy.yml` whose `determine_environment` job maps the git
  ref, then a job-level `uses:` calls the matching reusable workflow in SW with
  `secrets: inherit`.
- **Scripts toolkit is canonical and synced byte-identical** across
  gcp-shared-resources, SW, both app repos and the cookiecutter template
  (15 files + `providers/` + `tests/`). Tests (32, pure bash) run in pre-commit
  (`core.hooksPath .husky`) and in CI (`scripts-tests.yml`, path-filtered to
  `scripts/**`).

---

## 3. Work Completed on 2026-08-23 (already pushed, do not redo)

1. **Contract bugs fixed** (`gcp-shared-resources` `f109b27`):
   - Workflow parsed `get_environment_config` output as `key=value` while the
     refactored script emits JSON → switched to `jq -r '.environment_name'` /
     `.branch_type`.
   - `init_terraform.sh` lacked a source guard (ran `main "$@"` when sourced) →
     guard added.
   - `get_environment_config.sh` hardened for `set -u` (optional args
     `${5:-}`, `${2:-}`).
2. **Secret Manager key bootstrap** (same commit): gcp provider resolves the
   state encryption key as `-k` flag → `TF_STATE_ENCRYPTION_KEY` env var →
   Secret Manager **get-or-create** (secret `<state-bucket>-encryption-key`,
   generated on first use, refuses to generate if orphaned state exists).
   `-k` is now optional. Bucket IAM self-grant made non-fatal.
3. **`check_and_import_resources.sh` restored** from SW git history
   (`git show 5735f15:...`) — imports soft-deleted WIF pool/provider/SA into
   terraform state.
4. **Scripts test suite added** + pre-commit hook + `scripts-tests.yml` CI
   (`578c19b`).
5. **All 5 repos synced** to the identical canonical scripts set; all 6 SW
   reusable workflows switched to the v5 `init_terraform` interface
   (`-p gcp -i <project>`) with `TF_STATE_ENCRYPTION_KEY` passed as env;
   `reusable-determine-environment.yml` parse fixed too (SW `769cf05`,
   pubsub `0aa57c3`, kafka `a7c1055`, template `6d5ce55`).
6. **Committed encryption key removed from all 5 public READMEs** (it existed
   in gcp, SW, pubsub, kafka, template). Keyless local-deploy instructions
   documented everywhere.
7. **Key "rotation" resolved:** recon showed the state bucket no longer exists,
   Secret Manager was empty and NO repo had a `GITVAR_ENCRYPTION_KEY` GitHub
   secret → nothing was encrypted with the exposed key. A fresh key was
   generated directly into Secret Manager
   (`terraform-state-bucket-medallion-dev-463909-encryption-key`, value never
   displayed) and `github-actions-sa` was granted `secretAccessor`. The leaked
   key in git history is permanently dead.
8. **Clean slate** (approved by Kenan; he had deliberately deleted billable
   test resources earlier): deleted `sa-preprod79ef82c7` SA + its 9 project IAM
   bindings, 4 preprod Pub/Sub topics, `order-event-schema-preprod`, custom
   role `cloud_function_runtime_role_preprod`. **KEPT:** `github-actions-sa`,
   `github-id-pool` WIF pool + `github-id-pool-provider`, the new encryption
   key secret, Kenan's owner/viewer bindings.
9. **SW WIF trust list** (`github_config.repositories` in
   `github-actions-resources-terraform/terraform.tfvars`) now includes the two
   app repos — **committed but NOT terraform-applied yet**.
10. **CDK migration** (earlier on 2026-08-23): `cdk/` folder moved out of
    gcp-shared-resources into `aws-cdk-shared-resources` (`696e53c`) with
    deploy blockers fixed (see §7).

---

## 4. Current Live State

### GCP project `medallion-dev-463909` (project number `368539885233`)

| Item | State |
|---|---|
| Storage buckets | **NONE** (state bucket included — deleted) |
| Terraform state | **NONE anywhere** — next apply starts from scratch |
| Pub/Sub, Bigtable, Cloud Run, Functions, SQL, Compute | NONE |
| `github-actions-sa@medallion-dev-463909.iam.gserviceaccount.com` | EXISTS (CI identity, keep forever) |
| WIF: `github-id-pool` / `github-id-pool-provider` | EXISTS (attribute condition: `assertion.repository.startsWith('nodejs-projects-kenanhancer/')`; SA impersonation is per-repo via `github_config.repositories`) |
| Secret Manager | exactly 1 secret: `terraform-state-bucket-medallion-dev-463909-encryption-key` (v1); `github-actions-sa` has `secretAccessor` |
| Custom roles | NONE — but see soft-delete caveat in §10 |
| Kenan's bindings | `roles/owner`, `roles/viewer` |

### Known gaps (pre-existing, still open)

- **GitHub environments:** 0 configured on gcp-shared-resources (so `prod`
  approval gates and env-scoped vars/secrets don't exist yet).
- **`envs/*.json` missing:** the caller workflow's
  "Sync File Env Variables" step expects `envs/<env>.json` and a `PAT_TOKEN`
  secret; will fail on preprod/prod/dev pushes until created.
- **`GITVAR_*` variables/secrets not set** in any repo (no
  `GITVAR_GCP_PROJECT_ID`, `GITVAR_TF_STATE_BUCKET`, etc.). CI cannot deploy
  until these exist per environment.
- SW WIF tfvars change (item 9 above) not applied.

---

## 5. The Goal (Kenan's own words, translated)

> "My real aim was to be able to deploy to AWS, GCP and Azure. I want a NEW
> repository that hosts the AWS, GCP and Azure terraform configurations
> together." AWS has priority (also for interview preparation).

Explicitly decided along the way:

- **Terraform is the multi-cloud IaC standard** for this platform (one
  language/tool/state-model/pipeline — NOT "one config deploys anywhere";
  each cloud gets its own resource tree).
- The CDK repo stays as a **reference implementation** (interview story:
  "same platform in CDK and Terraform").

---

## 6. Target Architecture (approved)

### 6.1 New repo layout

```
shared-resources/                          ← NEW repo (name candidates: shared-resources | multicloud-shared-resources)
├── scripts/                               ← canonical set AS-IS (already multi-cloud)
│   ├── init_terraform.sh                  ←   -p gcp | aws | azure
│   ├── providers/
│   │   ├── gcp_provider.sh                ←   GCS backend + Secret Manager key (done, proven)
│   │   ├── aws_provider.sh                ←   S3 + DynamoDB lock + KMS (written, never used yet)
│   │   └── azure_provider.sh              ←   Storage Account backend (written, never used yet)
│   └── tests/run_tests.sh
├── terraform/
│   ├── gcp/                               ← MOVED from gcp-shared-resources/terraform (unchanged)
│   ├── aws/                               ← NEW (blueprint = CDK port, see §7)
│   └── azure/                             ← later
├── .github/workflows/
│   ├── gitflow-terraform-deploy-gcp.yml   ← paths: ["terraform/gcp/**", <self>]
│   ├── gitflow-terraform-deploy-aws.yml   ← paths: ["terraform/aws/**", <self>]
│   ├── gitflow-terraform-deploy-azure.yml ← later
│   └── scripts-tests.yml                  ← paths: ["scripts/**", <self>]
├── .husky/pre-commit                      ← runs scripts tests (core.hooksPath)
├── GITFLOW.md, images/, README.md
```

### 6.2 Core principles

1. **Per-cloud state sovereignty:** each cloud's terraform state lives in that
   cloud's own backend (GCS / S3+DynamoDB / Azure Storage). No "home cloud"
   dependency. `init_terraform.sh -p aws -d terraform/aws` already does this.
2. **State prefix isolation is free:** prefix = `{env}/{repo}/{terraform_dir}`
   and `terraform_dir` (`terraform/gcp` vs `terraform/aws`) is part of the
   prefix → `preprod/shared-resources/terraform/aws` etc. No script changes
   needed.
3. **Blast-radius isolation via `paths:` filters:** three thin caller
   workflows; changing `terraform/aws/**` triggers only the AWS pipeline.
   Same pattern already proven by `scripts-tests.yml`.
4. **SW stays the center:** one reusable workflow per cloud
   (`reusable-aws-shared-resources-terraform-deploy.yml` is ~90% a copy of the
   GCP one; only the auth block differs), plus per-cloud CI-identity bootstrap
   terraform folders.
5. **GitHub environments stay shared across clouds** (one `prod` approval gate
   for all clouds — a feature, not a bug). Cloud-specific pipeline config uses
   distinct `GITVAR_` names (`GITVAR_GCP_PROJECT_ID` vs `GITVAR_AWS_ACCOUNT_ID`,
   `GITVAR_AWS_REGION`, `GITVAR_AWS_TF_STATE_BUCKET`...).

### 6.3 The ONE new mechanism needed: TFVAR cloud-prefix

Problem: `TFVAR_*` vars are environment-scoped and cloud-blind; in a single
repo they would leak into every cloud's tfvars.

Solution (small, backward compatible): reusable workflows accept a
`tfvar_prefix` input. The AWS workflow first collects `TFVAR_AWS_*`
(stripping the full prefix), then falls back to plain `TFVAR_*` for
cloud-agnostic values; GCP uses `TFVAR_GCP_*` similarly. Implemented in the
"Generate updates.json" jq step of each reusable workflow.

### 6.4 Auth per cloud (CI)

| Cloud | Mechanism | Bootstrap location |
|---|---|---|
| GCP | WIF: `google-github-actions/auth@v2` + `github-actions-sa` | SW `github-actions-resources-terraform/` (EXISTS) |
| AWS | GitHub OIDC: `aws-actions/configure-aws-credentials@v4` + `role-to-assume` (trust policy on `token.actions.githubusercontent.com`, repo-scoped condition) | SW `aws-github-actions-resources-terraform/` (NEW, Phase 1) |
| Azure | Entra ID federated credentials + `azure/login` | later |

### 6.5 Encryption/state protection per cloud

| Cloud | Strategy |
|---|---|
| GCP | GCS CSEK via Secret Manager get-or-create (DONE — `ensure_encryption_key` in `gcp_provider.sh`) |
| AWS | **No extra key management needed**: S3 backend native SSE-KMS + DynamoDB lock; `aws_provider.sh` already creates/uses the KMS key |
| Azure | Storage account encryption (native); revisit at Azure phase |

### 6.6 Fate of existing repos

- `gcp-shared-resources` → content moves to `shared-resources/terraform/gcp/`;
  repo **archived** after migration (read-only, history preserved).
- `aws-cdk-shared-resources` → untouched, reference implementation.
- SW → grows (new bootstrap folder + new reusable workflows).
- App repos + cookiecutter template → unaffected.

---

## 7. AWS Terraform Blueprint (from the CDK port)

The CDK port (`aws-cdk-shared-resources`, commit `696e53c`) already contains
the service mapping AND the lessons learned. Use it as the design source for
`terraform/aws/` modules:

| GCP module | AWS module (new) | AWS services | Lessons from CDK fixes |
|---|---|---|---|
| `storage` | `s3` | S3 buckets (bronze/silver/gold + app-config + artifacts) | keep KMS + BlockPublicAccess; bucket names are GLOBAL — include account id or random suffix in names |
| `secret` | `secrets` | Secrets Manager | set values via native secret-version (CDK bug was `CfnSecretTargetAttachment` misuse); NO auto-rotation on API keys/tokens |
| `pubsub` | `messaging` | SNS topic + SQS queue + subscription; DLQ via redrive (`maxReceiveCount` ≈ Pub/Sub `max_delivery_attempts`, `visibilityTimeout` ≈ `ack_deadline`) | schema support needs EventBridge/Glue registry — decide whether to port `schema_config` or drop it for AWS |
| `bigtable` | `dynamodb` | DynamoDB tables (+autoscaling when PROVISIONED) | support MULTIPLE tables per config (CDK only used `tables[0]`) |
| `iam` | `iam` | shared execution role (Lambda/SFN/Events principals) | resource-scoped grants ONLY — no `*FullAccess` managed policies; dedupe principals (CDK had duplicate-user bug) |

Keep the tfvars schema shape identical to GCP's (`basic_config`,
`storages_config`, `secrets_config`, `topic_config`-equivalent,
`bigtable_config`-equivalent) so the TFVAR_ injection pipeline works unchanged.

---

## 8. Phased Implementation Plan

### Phase 0 — Create `shared-resources`, migrate GCP (repo works day 1)
1. Create GitHub repo (public, org `nodejs-projects-kenanhancer`).
2. Copy from `gcp-shared-resources`: `scripts/` (canonical), `GITFLOW.md`,
   `images/`, `.husky/`, `.github/workflows/scripts-tests.yml`.
3. Move `terraform/` → `terraform/gcp/`.
4. Author `gitflow-terraform-deploy-gcp.yml`: copy of current caller with
   `paths: ["terraform/gcp/**", <self>]` and
   `terraform_dir: "terraform/gcp"` passed to the SW reusable workflow.
5. New root README (multi-cloud story + per-cloud local deploy instructions;
   GCP block: `./scripts/init_terraform.sh -p gcp -i medallion-dev-463909 -r europe-west2 -d terraform/gcp`).
6. `git config core.hooksPath .husky`; run `./scripts/tests/run_tests.sh`.
7. Push; verify scripts-tests CI green.
8. Archive `gcp-shared-resources` on GitHub (Settings → Archive) — only AFTER
   verifying the new repo's GCP pipeline (or defer archiving to Phase 4).

**Acceptance:** scripts tests green in new repo; a feature-branch push touching
`terraform/gcp/**` triggers ONLY the GCP workflow (it will fail at
missing-GITVAR stage — that's expected until CI vars are configured, see §4
gaps; local `init_terraform -p gcp -d terraform/gcp` + `plan` must work
end-to-end and create the state bucket + read the key from Secret Manager).

### Phase 1 — AWS CI identity bootstrap (in SW)
1. New folder `aws-github-actions-resources-terraform/` in SW mirroring the GCP
   one: `aws_iam_openid_connect_provider`
   (`token.actions.githubusercontent.com`), `aws_iam_role`
   `github-actions-deploy-role` with trust condition
   `repo:nodejs-projects-kenanhancer/shared-resources:*` (list-driven like
   `github_config.repositories`), permission policies for what terraform
   manages (start broad-ish: PowerUser + IAM scoped, tighten later).
2. Backend: `init_terraform.sh -p aws -d aws-github-actions-resources-terraform`
   → exercises `aws_provider.sh` for the first time (expect and fix drift —
   it has never run).
3. Apply locally with Kenan's AWS credentials (`aws configure` / SSO).
4. Document in SW README (local bootstrap section, AWS variant).

**Acceptance:** role ARN output; a scratch GitHub Actions run in
`shared-resources` can `aws sts get-caller-identity` via
`configure-aws-credentials` with that role.

### Phase 2 — `terraform/aws/` modules
Implement per §7 blueprint + root `main.tf`/`variables.tf`/`providers.tf`
(+ `backend "s3" {}` empty block — config injected by `aws_provider.sh`'s
`backend-config.hcl`). Local workflow:
`./scripts/init_terraform.sh -p aws -f <profile> -d terraform/aws` → plan →
apply → verify → destroy (billing hygiene).

**Acceptance:** clean apply+destroy cycle from local; tfvars schema mirrors
GCP shape.

### Phase 3 — AWS reusable workflow + TFVAR prefix mechanism
1. SW: `reusable-aws-shared-resources-terraform-deploy.yml` — copy GCP one;
   replace auth block (`configure-aws-credentials@v4`, `role-to-assume` from
   `vars.GITVAR_AWS_DEPLOY_ROLE_ARN` or constructed default, region from
   `vars.GITVAR_AWS_REGION`); drop gcloud/GCS-specific steps
   (`sync_schema_to_cloud.sh` is gsutil-based — skip or port); init call:
   `init_terraform -p aws -f default -b "${{ vars.GITVAR_AWS_TF_STATE_BUCKET }}" -d "$TERRAFORM_DIR"`
   (check `aws_provider.sh` flag names first: `-f` profile may need an
   env-credentials mode for CI — likely needs a small provider patch to skip
   profile validation when `AWS_ACCESS_KEY_ID`/OIDC env creds are present).
2. Implement `tfvar_prefix` input in BOTH aws and gcp reusable workflows
   (backward compatible fallback to plain `TFVAR_`).
3. `gitflow-terraform-deploy-aws.yml` caller in `shared-resources`.
4. Configure GitHub environments + `GITVAR_AWS_*` vars (manual, Kenan).

**Acceptance:** feature branch touching `terraform/aws/**` → PR shows plan →
merge to dev applies to an ephemeral/dev AWS environment → cleanup via
workflow_dispatch destroy.

### Phase 4 — Hardening
- Version SW reusable workflows with tags (`@v1`) instead of `@main`
  (long-standing recommendation; prevents the cross-repo drift class of bugs).
- Add AWS provider tests to `scripts/tests/run_tests.sh` (mock `aws` CLI like
  the gcloud stub pattern).
- Archive `gcp-shared-resources` if not done in Phase 0.
- Create `envs/*.json` + GitHub environments + approval reviewers.

### Phase 5 — Azure (same recipe, later)
`azure-github-actions-resources-terraform/` (Entra federated creds),
`terraform/azure/`, `reusable-azure-...yml`, `azure_provider.sh` first-use
shakedown.

---

## 9. Open Decisions (ask Kenan at session start)

1. **Repo name:** `shared-resources` (Claude's recommendation — the prefix-less
   name communicates multi-cloud) vs `multicloud-shared-resources`.
2. Archive `gcp-shared-resources` in Phase 0 or Phase 4?
3. AWS account: which account id / region defaults? (No AWS account details
   are known yet in this ecosystem — Phase 1 needs Kenan logged in via
   `aws configure` or SSO.)
4. Port Pub/Sub `schema_config` to AWS (EventBridge Schema Registry) or drop
   schemas on the AWS side initially? (Recommendation: drop initially.)

---

## 10. Risks & Gotchas (read before implementing)

- **Custom role soft-delete window:** `cloud_function_runtime_role_preprod`
  was deleted 2026-08-23. GCP blocks reusing a deleted custom role ID for
  ~7–37 days. If `terraform/gcp` is applied before ~end of Sept 2026 and role
  creation fails with "already exists (deleted)":
  `gcloud iam roles undelete cloud_function_runtime_role_preprod --project=medallion-dev-463909`
  then `terraform import`.
- **SW WIF trust tfvars not applied:** app repos' CI can't impersonate
  `github-actions-sa` until `github-actions-resources-terraform` is applied.
  Also: when the new `shared-resources` repo is created it must be ADDED to
  `github_config.repositories` (and the old repo name removed after archiving).
- **`aws_provider.sh` / `azure_provider.sh` have never been executed** — they
  were written alongside the gcp one but are untested. Budget shakedown time
  in Phase 1/2 (flag parsing, `-f` profile requirement in CI, KMS/DynamoDB
  creation paths).
- **GCS/S3 bucket name globality:** `bronze-layer-preprod` style names collide
  globally. For AWS include the account id in bucket names from day 1;
  consider the same for a future fresh GCP apply.
- **Reusable workflows pinned `@main`:** any SW change is instantly live for
  all consumers. Tagging (`@v1`) is the standing recommendation (Phase 4).
- **GitHub environment protection is repo-level:** one `prod` gate covers all
  clouds in the single repo (accepted as a feature).
- **App repos and template still deploy GCP only** — this plan does NOT touch
  them; multi-cloud applies to the platform repo only.
- The caller workflow's env-sync step (`envs/*.json` + `PAT_TOKEN`) is still
  unsatisfied everywhere (§4 gaps) — CI runs go red at that step for
  preprod/prod/dev until configured or the step is made conditional.

---

## 11. How to Resume in a New Session

Tell Claude:

> "Read MULTICLOUD_PLAN.md in gcp-shared-resources and continue from Phase 0.
> Repo name decision: <shared-resources | multicloud-shared-resources>."

Claude's memory (project memory file `gcp-shared-resources-ecosystem`) also
summarizes this ecosystem; this document is the authoritative, more detailed
source.

---

## Appendix A — Key Identifiers

| Item | Value |
|---|---|
| GCP project | `medallion-dev-463909` (number `368539885233`) |
| GCP region default | `europe-west2` |
| CI service account | `github-actions-sa@medallion-dev-463909.iam.gserviceaccount.com` |
| WIF pool / provider | `github-id-pool` / `github-id-pool-provider` (location: global) |
| State bucket name (when recreated) | `terraform-state-bucket-medallion-dev-463909` |
| Encryption key secret | `terraform-state-bucket-medallion-dev-463909-encryption-key` (Secret Manager, v1; `github-actions-sa` has accessor) |
| Old leaked key | dead — nothing it decrypts exists; still visible in git histories (harmless) |
| Session commits (2026-08-23) | gcp: `f109b27`, `578c19b` · SW: `769cf05` · pubsub: `0aa57c3` · kafka: `a7c1055` · template: `6d5ce55` · cdk: `696e53c` |

## Appendix B — Canonical scripts set (synced across all repos)

`build_and_prepare.sh`, `check_and_import_resources.sh`, `cleanup.py`,
`clone_github_environment_variables_secrets.sh`, `convert_json_to_hcl.py`,
`get_environment_config.sh`, `init_terraform.sh`, `install_hcl2json.sh`,
`providers/{gcp,aws,azure}_provider.sh`, `set_env_property.sh`, `setup.py`,
`sync_env_vars_to_github.sh`, `sync_schema_to_cloud.sh`, `tests/run_tests.sh`.

Sync rule: change scripts ONLY as a package (script + its workflow consumers +
tests together), then propagate to all repos. Tests must pass everywhere
(pre-commit + scripts-tests CI enforce this).
