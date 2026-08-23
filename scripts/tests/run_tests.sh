#!/bin/bash
# ============================================================================
# Test suite for the shared scripts toolkit
#
# Pure bash, no framework dependency - runs anywhere the scripts run.
# Usage: ./scripts/tests/run_tests.sh
# ============================================================================

set -u

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(dirname "$TESTS_DIR")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0
FAILED_NAMES=()

# ----------------------------------------------------------------------------
# Assertion helpers
# ----------------------------------------------------------------------------

assert_eq() { # <test-name> <expected> <actual>
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
        echo "  ok  $1"
    else
        FAIL=$((FAIL + 1))
        FAILED_NAMES+=("$1")
        echo "  FAIL $1"
        echo "       expected: [$2]"
        echo "       actual:   [$3]"
    fi
}

assert_contains() { # <test-name> <needle> <haystack>
    case "$3" in
    *"$2"*)
        PASS=$((PASS + 1))
        echo "  ok  $1"
        ;;
    *)
        FAIL=$((FAIL + 1))
        FAILED_NAMES+=("$1")
        echo "  FAIL $1"
        echo "       expected to contain: [$2]"
        echo "       actual: [$3]"
        ;;
    esac
}

# ----------------------------------------------------------------------------
# get_environment_config: branch -> environment/state contract
# The CI workflows parse this output with jq; these tests pin the contract.
# ----------------------------------------------------------------------------

test_get_environment_config() {
    echo "get_environment_config.sh"
    . "$SCRIPTS_DIR/get_environment_config.sh"

    local out

    out=$(get_environment_config "my-repo" "terraform" "refs/heads/main" "42")
    assert_eq "main -> preprod" "preprod" "$(echo "$out" | jq -r '.environment_name')"
    assert_eq "main -> branch_type main" "main" "$(echo "$out" | jq -r '.branch_type')"
    assert_eq "main -> state prefix" "preprod/my-repo/terraform" "$(echo "$out" | jq -r '.state_prefix')"

    out=$(get_environment_config "my-repo" "terraform" "refs/heads/dev" "42")
    assert_eq "dev -> dev" "dev" "$(echo "$out" | jq -r '.environment_name')"

    out=$(get_environment_config "my-repo" "terraform" "refs/tags/v1.2.3" "42")
    assert_eq "tag -> prod" "prod" "$(echo "$out" | jq -r '.environment_name')"
    assert_eq "tag -> branch_type tag" "tag" "$(echo "$out" | jq -r '.branch_type')"

    out=$(get_environment_config "my-repo" "terraform" "refs/heads/release/1.2.0" "42")
    assert_eq "release -> uat" "uat" "$(echo "$out" | jq -r '.environment_name')"

    out=$(get_environment_config "my-repo" "terraform" "refs/heads/hotfix/1.2.1" "42")
    assert_eq "hotfix -> hotfix" "hotfix" "$(echo "$out" | jq -r '.environment_name')"

    out=$(get_environment_config "my-repo" "terraform" "refs/heads/feature/say-hello" "42")
    assert_eq "feature -> dev-id + name" "42-say-hello" "$(echo "$out" | jq -r '.environment_name')"
    assert_eq "feature -> state prefix" "features/my-repo/terraform/42/say-hello" "$(echo "$out" | jq -r '.state_prefix')"

    out=$(get_environment_config "my-repo" "terraform" "refs/heads/random-branch" "42")
    assert_eq "unknown -> skip=true" "true" "$(echo "$out" | jq -r '.skip')"

    out=$(get_environment_config "my-repo" "terraform" "refs/heads/main" "42" "my-app")
    assert_eq "app-name in state prefix" "preprod/my-repo/my-app/terraform" "$(echo "$out" | jq -r '.state_prefix')"

    get_environment_config "only-two-args" "x" >/dev/null 2>&1
    assert_eq "too few args -> exit 1" "1" "$?"
}

# ----------------------------------------------------------------------------
# init_terraform.sh: entry-point behaviour
# ----------------------------------------------------------------------------

test_init_terraform_entrypoint() {
    echo "init_terraform.sh"

    # Sourcing must only define the function, never execute it (CI contract)
    local out
    out=$(bash -c "source '$SCRIPTS_DIR/init_terraform.sh' >/dev/null 2>&1; type -t init_terraform")
    assert_eq "source defines function without executing" "function" "$out"

    bash "$SCRIPTS_DIR/init_terraform.sh" >/dev/null 2>&1
    assert_eq "direct run without args -> exit 1" "1" "$?"

    out=$(bash "$SCRIPTS_DIR/init_terraform.sh" -p not-a-provider -d terraform 2>&1)
    assert_eq "unsupported provider -> exit 1" "1" "$?"
    assert_contains "unsupported provider message" "Unsupported provider" "$out"

    bash "$SCRIPTS_DIR/init_terraform.sh" -p gcp >/dev/null 2>&1
    assert_eq "missing terraform dir -> exit 1" "1" "$?"
}

# ----------------------------------------------------------------------------
# gcp_provider.sh helpers (sourced with stubbed logging)
# ----------------------------------------------------------------------------

load_gcp_provider() {
    log_error() { :; }
    log_success() { :; }
    log_info() { :; }
    log_warning() { :; }
    SCRIPT_NAME="test"
    . "$SCRIPTS_DIR/providers/gcp_provider.sh"
}

test_generate_bucket_name() {
    echo "gcp_provider.sh: generate_bucket_name"
    (
        FAIL=0
        load_gcp_provider
        assert_eq "empty name -> prefix-project" \
            "terraform-state-bucket-proj-1" "$(generate_bucket_name "" "proj-1")"
        assert_eq "custom name -> project appended" \
            "my-bucket-proj-1" "$(generate_bucket_name "my-bucket" "proj-1")"
        assert_eq "name with project suffix -> unchanged" \
            "my-bucket-proj-1" "$(generate_bucket_name "my-bucket-proj-1" "proj-1")"
        exit $FAIL
    )
    local sub_fail=$?
    FAIL=$((FAIL + sub_fail))
    PASS=$((PASS + 3 - sub_fail))
}

# ----------------------------------------------------------------------------
# gcp_provider.sh: ensure_encryption_key (gcloud stubbed via PATH)
# ----------------------------------------------------------------------------

make_gcloud_stub() {
    mkdir -p "$TMP_DIR/bin"
    cat >"$TMP_DIR/bin/gcloud" <<'EOF'
#!/bin/bash
case "$*" in
*"secrets versions access"*)
    if [ "${STUB_SECRET_EXISTS:-0}" = "1" ]; then
        printf 'key-from-secret-manager'
        exit 0
    fi
    exit 1
    ;;
*"storage ls"*)
    if [ "${STUB_BUCKET_HAS_OBJECTS:-0}" = "1" ]; then
        echo "gs://bucket/some/state/default.tfstate"
        exit 0
    fi
    exit 1
    ;;
*"services enable"*) exit 0 ;;
*"secrets create"*)
    if [ "${STUB_CREATE_FAILS:-0}" = "1" ]; then
        exit 1
    fi
    cat >/dev/null # consume --data-file=- input
    exit 0
    ;;
*) exit 0 ;;
esac
EOF
    chmod +x "$TMP_DIR/bin/gcloud"
}

run_ensure_key() { # env assignments passed as VAR=value args
    (
        export PATH="$TMP_DIR/bin:$PATH"
        for kv in "$@"; do export "${kv?}"; done
        load_gcp_provider
        GCP_PROJECT_ID="proj-1"
        GCP_BUCKET_NAME="terraform-state-bucket-proj-1"
        GCP_ENCRYPTION_KEY="${PRESET_KEY:-}"
        ensure_encryption_key || exit 9
        printf '%s' "$GCP_ENCRYPTION_KEY"
    )
}

test_ensure_encryption_key() {
    echo "gcp_provider.sh: ensure_encryption_key"
    make_gcloud_stub
    local out

    out=$(run_ensure_key "PRESET_KEY=explicit-key")
    assert_eq "-k flag wins" "explicit-key" "$out"

    out=$(run_ensure_key "TF_STATE_ENCRYPTION_KEY=key-from-env")
    assert_eq "env var used when no flag" "key-from-env" "$out"

    out=$(run_ensure_key "STUB_SECRET_EXISTS=1")
    assert_eq "existing secret is read" "key-from-secret-manager" "$out"

    out=$(run_ensure_key)
    assert_eq "first use generates 32-byte base64 key" "44" "${#out}"

    run_ensure_key "STUB_BUCKET_HAS_OBJECTS=1" >/dev/null 2>&1
    assert_eq "orphaned state blocks key generation" "9" "$?"

    out=$(run_ensure_key "STUB_CREATE_FAILS=1" "STUB_SECRET_EXISTS=0" 2>/dev/null; echo "rc=$?")
    assert_contains "create+read both failing -> error" "rc=9" "$out"
}

# ----------------------------------------------------------------------------
# set_env_property.sh: tfvars updates
# ----------------------------------------------------------------------------

test_set_env_property() {
    echo "set_env_property.sh"
    . "$SCRIPTS_DIR/set_env_property.sh"

    local tfvars="$TMP_DIR/test.tfvars"
    cat >"$tfvars" <<'EOF'
basic_config = {
  environment    = "preprod"
  gcp_project_id = "old-project"
}
EOF
    set_env_property --file "$tfvars" --key gcp_project_id --value new-project >/dev/null
    grep -q 'gcp_project_id = "new-project"' "$tfvars"
    assert_eq "tfvars nested key updated" "0" "$?"

    local envfile="$TMP_DIR/test.env"
    printf 'SERVER_PORT=1000\n' >"$envfile"
    set_env_property --file "$envfile" --key SERVER_PORT --value 8080 >/dev/null
    assert_eq ".env key updated" "SERVER_PORT=8080" "$(cat "$envfile")"
}

# ----------------------------------------------------------------------------
# convert_json_to_hcl.py
# ----------------------------------------------------------------------------

test_convert_json_to_hcl() {
    echo "convert_json_to_hcl.py"
    if ! command -v python3 >/dev/null 2>&1; then
        echo "  skip (python3 not available)"
        return 0
    fi

    local out
    out=$(python3 "$SCRIPTS_DIR/convert_json_to_hcl.py" -j '{"basic_config":{"environment":"dev","region":"europe-west2"},"list_value":["a","b"]}')
    assert_contains "nested object rendered as block" 'basic_config = {' "$out"
    assert_contains "string value quoted" 'environment = "dev"' "$out"
    assert_contains "list rendered as json array" 'list_value = ["a", "b"]' "$out"
}

# ----------------------------------------------------------------------------
# Runner
# ----------------------------------------------------------------------------

echo "Running script tests from: $SCRIPTS_DIR"
echo

test_get_environment_config
test_init_terraform_entrypoint
test_generate_bucket_name
test_ensure_encryption_key
test_set_env_property
test_convert_json_to_hcl

echo
echo "Passed: $PASS  Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed tests:\n'
    printf '  - %s\n' "${FAILED_NAMES[@]}"
    exit 1
fi
echo "All tests passed."
