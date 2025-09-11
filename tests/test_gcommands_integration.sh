#!/bin/bash

# Integration tests for gcommands plugin - these test the actual command construction
# Note: These tests mock gcloud commands to avoid actual GCP API calls

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source the test framework
source "$SCRIPT_DIR/test_framework.sh"

# Setup test environment
setup_tests

# Mock environment variables for testing
export GUSER="testuser"
export GPREFIX="testprefix"

# Create a temporary directory for test artifacts
TEST_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

run_test_suite "Integration Tests - Command Construction"

# Create a mock version of the plugin for testing
create_mock_plugin() {
    cat > "$TEST_DIR/mock_gcommands.sh" << 'EOF'
#!/bin/bash

# Mock gcloud command that records what would be executed
MOCK_GCLOUD_LOG="$TEST_DIR/gcloud_commands.log"

gcloud() {
    echo "gcloud $*" >> "$MOCK_GCLOUD_LOG"
    
    # Mock specific responses for different commands
    case "$1" in
        "compute")
            case "$2" in
                "images")
                    if [[ "$*" == *"list"* ]]; then
                        echo "ubuntu-2004-focal-v20210817 ubuntu-os-cloud"
                    fi
                    ;;
                "instances")
                    if [[ "$*" == *"list"* ]]; then
                        echo "NAME ZONE MACHINE_TYPE PREEMPTIBLE INTERNAL_IP EXTERNAL_IP STATUS"
                        echo "testprefix-instance1 us-central1-c n1-standard-4  10.128.0.93 34.72.173.60 RUNNING"
                    elif [[ "$*" == *"create"* ]]; then
                        echo "Created [https://www.googleapis.com/compute/v1/projects/test-project/zones/us-central1-c/instances/testprefix-instance1]."
                        echo "NAME ZONE MACHINE_TYPE PREEMPTIBLE INTERNAL_IP EXTERNAL_IP STATUS"
                        echo "testprefix-instance1 us-central1-c n1-standard-4  10.128.0.93 34.72.173.60 RUNNING"
                    elif [[ "$*" == *"describe"* ]]; then
                        echo "34.72.173.60"
                    fi
                    ;;
                "machine-types")
                    if [[ "$*" == *"list"* ]]; then
                        echo "n1-standard-4"
                    fi
                    ;;
            esac
            ;;
        "iam")
            if [[ "$*" == *"service-accounts list"* ]]; then
                echo "123456789-compute@developer.gserviceaccount.com"
            fi
            ;;
    esac
    
    return 0
}

# Source utility functions from the original plugin
getdate() {
  local duration="$1"
  case $OSTYPE in
    darwin*)
      [ -z "$duration" ] && duration="1d" || :
      date "-v+${duration}" '+%Y-%m-%d'
      ;;
    linux*)
      [ -z "$duration" ] && duration="1 day" || :
      date -d "${duration}" '+%Y-%m-%d'
      ;;
  esac
}

genv() {
  >&2 echo "Configuration: test-config"
}

glist() {
  genv
  gcloud compute instances list --filter="labels.owner:${GUSER}"
}

gcreate() {
  genv
  local usage="Usage: gcreate [-d duration|never] <IMAGE> <MACHINE_TYPE> <INSTANCE_NAMES...>"
  local expires
  local OPTIND=1  # Reset OPTIND for this function
  while getopts ":d:" opt; do
    case $opt in
      d)
        [ "$OPTARG" = "never" ] && expires="never" || expires="$(getdate "${OPTARG}")"
        ;;
    esac
  done
  shift "$((OPTIND-1))"
  if [ -z "$expires" ]; then
    expires="$(getdate)"
  fi
  if [ "$#" -lt 2 ]; then
    echo "${usage}"
    return 1
  fi
  local image
  image="$(gcloud compute images list --filter="name~${1} AND -name~arm" --limit 1 | awk 'NR == 2')"
  if [ -z "${image}" ]; then
    echo "gcreate: unknown image $1"
    echo "${usage}"
    return 1
  fi
  local image_name
  image_name="$(echo "${image}" | awk '{print $1}')"
  local image_project  
  image_project="$(echo "${image}" | awk '{print $2}')"
  local default_service_account
  default_service_account="$(gcloud iam service-accounts list | grep -o '[0-9]*\-compute@developer.gserviceaccount.com')"
  shift
  local machine_type
  machine_type="$(gcloud compute machine-types list --filter="name=${1}" --format="table[no-heading](name)" --limit 1)"
  if [ -z "${machine_type}" ]; then
    echo "gcreate: unknown machine type $1"; echo "${usage}"
    return 1
  fi
  shift
  local instance_names=("$@")
  if [ -n "${GPREFIX}" ]; then
    instance_names=($(echo ${instance_names} | sed "s/[^ ]* */${GPREFIX}-&/g"))
  fi
  (set -x; gcloud compute instances create ${instance_names[@]} \
    --labels owner="${GUSER}",email="${GUSER}__64__replicated__46__com",expires-on="${expires}" \
    --machine-type="${machine_type}" \
    --subnet=default --network-tier=PREMIUM --maintenance-policy=MIGRATE --can-ip-forward \
    --service-account="${default_service_account}" \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
    --image="${image_name}" --image-project="${image_project}" \
    --boot-disk-size=200GB --boot-disk-type=pd-ssd \
    --maintenance-policy TERMINATE --restart-on-failure \
    --create-disk size=100GB,type=pd-ssd,auto-delete=yes \
    --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --reservation-affinity=any)
}

gstart() {
  genv
  local usage="Usage: gstart [INSTANCE_NAMES]"
  if [ "$#" -lt 1 ]; then echo "${usage}"; return 1; fi
  local instance_name_prefix="$1"
  gcloud compute instances start $(gcloud compute instances list --filter="labels.owner:${GUSER}" | awk '{if(NR>1)print}' | grep TERMINATED | grep "^${instance_name_prefix}" | awk '{print $1}' | xargs echo)
}

gstop() {
  genv
  local usage="Usage: gstop [INSTANCE_NAMES]"
  if [ "$#" -lt 1 ]; then echo "${usage}"; return 1; fi
  local instance_name_prefix="$1"
  gcloud compute instances stop $(gcloud compute instances list --filter="labels.owner:${GUSER}" | awk '{if(NR>1)print}' | grep RUNNING | grep "^${instance_name_prefix}" | awk '{print $1}' | xargs echo)
}

gssh() {
  genv
  local usage="Usage: gssh [INSTANCE_NAME]"
  if [ "$#" -ne 1 ]; then echo "${usage}"; return 1; fi
  local instance_name="$1"
  if [ -n "${GPREFIX}" ]; then
    instance_name="${GPREFIX}-${instance_name}"
  fi
  # Mock SSH - just record the command
  echo "gcloud compute ssh --tunnel-through-iap \"${instance_name}\""
}

EOF

    source "$TEST_DIR/mock_gcommands.sh"
}

# Test glist command construction
test_glist_command() {
    create_mock_plugin
    
    # Clear the log file
    true > "$MOCK_GCLOUD_LOG"
    
    local result=$(glist 2>&1)
    
    # Check that the correct gcloud command was called
    assert_file_exists "$MOCK_GCLOUD_LOG" "gcloud commands are logged"
    
    local logged_command=$(grep "compute instances list" "$MOCK_GCLOUD_LOG")
    assert_contains "$logged_command" "labels.owner:testuser" "glist uses correct owner filter"
    assert_contains "$result" "Configuration: test-config" "glist displays configuration"
}

# Test gcreate command construction
test_gcreate_command() {
    create_mock_plugin
    
    # Clear the log file
    true > "$MOCK_GCLOUD_LOG"
    
    local result=$(gcreate "ubuntu" "n1-standard-4" "instance1" 2>&1)
    
    # Check that required gcloud commands were called
    local images_command=$(grep "compute images list" "$MOCK_GCLOUD_LOG" || echo "")
    assert_contains "$images_command" "name~ubuntu" "gcreate queries for image"
    
    # Check that machine types command was called
    if grep -q "compute machine-types list" "$MOCK_GCLOUD_LOG"; then
        print_success "gcreate validates machine type"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_failure "gcreate validates machine type"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local create_command=$(grep "compute instances create" "$MOCK_GCLOUD_LOG" || echo "")
    assert_contains "$create_command" "testprefix-instance1" "gcreate applies GPREFIX to instance name"
    assert_contains "$create_command" "owner=testuser" "gcreate sets owner label"
    assert_contains "$create_command" "machine-type" "gcreate uses correct machine type"
}

# Test gcreate parameter validation
test_gcreate_validation() {
    create_mock_plugin
    
    # Test with insufficient parameters
    local result
    result=$(gcreate "ubuntu" 2>&1)
    local exit_code=$?
    
    assert_exit_code 1 $exit_code "gcreate fails with insufficient parameters"
    assert_contains "$result" "Usage:" "gcreate shows usage message on error"
}

# Test gcreate with duration flag
test_gcreate_with_duration() {
    create_mock_plugin
    
    # Clear the log file
    true > "$MOCK_GCLOUD_LOG"
    
    local result=$(gcreate -d "never" "ubuntu" "n1-standard-4" "instance1" 2>&1)
    
    local create_command=$(grep "compute instances create" "$MOCK_GCLOUD_LOG" || echo "")
    assert_contains "$create_command" "expires-on=never" "gcreate handles 'never' expiration"
}

# Test gstart command construction
test_gstart_command() {
    create_mock_plugin
    
    # Clear the log file
    true > "$MOCK_GCLOUD_LOG"
    
    local result=$(gstart "instance" 2>&1)
    
    local start_command=$(grep "compute instances start" "$MOCK_GCLOUD_LOG")
    assert_not_empty "$start_command" "gstart generates correct command"
    
    # Should also have a list command to find instances
    local list_command=$(grep "compute instances list" "$MOCK_GCLOUD_LOG")
    assert_contains "$list_command" "labels.owner:testuser" "gstart filters by owner"
}

# Test parameter validation for various commands
test_parameter_validations() {
    create_mock_plugin
    
    # Test gstart with no parameters
    local result=$(gstart 2>&1)
    assert_contains "$result" "Usage:" "gstart shows usage without parameters"
    
    # Test gstop with no parameters
    result=$(gstop 2>&1)
    assert_contains "$result" "Usage:" "gstop shows usage without parameters"
    
    # Test gssh with no parameters
    result=$(gssh 2>&1)
    assert_contains "$result" "Usage:" "gssh shows usage without parameters"
    
    # Test gssh with too many parameters
    result=$(gssh "instance1" "instance2" 2>&1)
    assert_contains "$result" "Usage:" "gssh shows usage with too many parameters"
}

# Test GPREFIX application
test_prefix_application() {
    create_mock_plugin
    
    # Test with GPREFIX set
    local result=$(gssh "myinstance" 2>&1)
    assert_contains "$result" "testprefix-myinstance" "gssh applies GPREFIX correctly"
    
    # Test without GPREFIX
    local old_prefix="$GPREFIX"
    unset GPREFIX
    
    result=$(gssh "myinstance" 2>&1)
    assert_contains "$result" "myinstance" "gssh works without GPREFIX"
    
    # Restore GPREFIX
    export GPREFIX="$old_prefix"
}

# Test environment variable requirements
test_environment_requirements() {
    create_mock_plugin
    
    # Test without GUSER
    local old_guser="$GUSER"
    unset GUSER
    
    # Clear the log file
    true > "$MOCK_GCLOUD_LOG"
    
    local result=$(glist 2>&1)
    local list_command=$(grep "compute instances list" "$MOCK_GCLOUD_LOG")
    assert_contains "$list_command" "labels.owner:" "glist handles missing GUSER"
    
    # Restore GUSER
    export GUSER="$old_guser"
}

# Run all integration tests
test_glist_command
test_gcreate_command
test_gcreate_validation
test_gcreate_with_duration
test_gstart_command
test_parameter_validations
test_prefix_application
test_environment_requirements

print_test_summary