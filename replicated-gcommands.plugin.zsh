#!/bin/bash

# GUSER=
# GPREFIX=

if (( ! ${+commands[gcloud]} ));then
  >&2 echo "gcloud not installed, not loading replicated-gcommands plugin"
  return 1
fi

# Input validation functions
validate_instance_name() {
    local name="$1"
    
    # Check for valid characters (alphanumeric, hyphens only)
    if [[ ! "$name" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
        printf >&2 'Error: Invalid instance name: %s\n' "$name"
        printf >&2 'Instance names must contain only letters, numbers, and hyphens\n'
        return 1
    fi
    
    # Check length constraints
    if [[ ${#name} -gt 63 ]]; then
        printf >&2 'Error: Instance name too long: %s (max 63 characters)\n' "$name"
        return 1
    fi
    
    return 0
}

validate_required_env() {
    if [[ -z "${GUSER:-}" ]]; then
        printf >&2 'Error: GUSER environment variable not set\n'
        printf >&2 'Set GUSER to your username: export GUSER="username"\n'
        return 1
    fi
    return 0
}

genv() {
  >&2 echo "Configuration: $(cat ~/.config/gcloud/active_config)"
}

getdate() {
    local duration="${1:-1d}"
    local result
    
    case "$OSTYPE" in
        darwin*)
            if command -v gdate >/dev/null 2>&1; then
                # Use GNU date if available (homebrew)
                result=$(gdate -d "+${duration/d/ day}" '+%Y-%m-%d' 2>/dev/null)
            else
                # Use BSD date
                result=$(date -j -v "+${duration}" '+%Y-%m-%d' 2>/dev/null)
            fi
            ;;
        linux*|*gnu*)
            result=$(date -d "+${duration/d/ day}" '+%Y-%m-%d' 2>/dev/null)
            ;;
        *)
            # Fallback for other systems
            printf >&2 'Warning: Unsupported OS type: %s\n' "$OSTYPE"
            result=$(date '+%Y-%m-%d')
            ;;
    esac
    
    if [[ -z "$result" ]]; then
        printf >&2 'Error: Failed to calculate date with duration: %s\n' "$duration"
        return 1
    fi
    
    printf '%s\n' "$result"
}

glist() {
  genv
  gcloud compute instances list --filter="labels.owner:${GUSER}"
}

gcreate() {
  local usage="Usage: gcreate [-d duration|never] <IMAGE> <MACHINE_TYPE> <INSTANCE_NAMES...>"
  local expires=""
  local OPTIND=1
  
  # Validate prerequisites
  validate_required_env || return 1
  genv
  
  # Parse options with proper error handling
  while getopts ":d:h" opt; do
    case $opt in
      d)
        if [[ "$OPTARG" = "never" ]]; then
          expires="never"
        else
          expires=$(getdate "$OPTARG") || {
            printf >&2 'Error: Invalid duration: %s\n' "$OPTARG"
            return 1
          }
        fi
        ;;
      h)
        printf '%s\n' "$usage"
        return 0
        ;;
      \?)
        printf >&2 'Error: Invalid option: -%s\n' "$OPTARG"
        printf >&2 '%s\n' "$usage"
        return 1
        ;;
      :)
        printf >&2 'Error: Option -%s requires an argument\n' "$OPTARG"
        printf >&2 '%s\n' "$usage"
        return 1
        ;;
    esac
  done
  shift $((OPTIND-1))
  
  # Set default expiration if not provided
  if [[ -z "$expires" ]]; then
    expires=$(getdate) || {
      printf >&2 'Error: Failed to calculate default expiration date\n'
      return 1
    }
  fi
  
  # Validate minimum arguments
  if [[ $# -lt 2 ]]; then
    printf >&2 'Error: Insufficient arguments\n'
    printf >&2 '%s\n' "$usage"
    return 1
  fi
  # Validate and get image information
  local image
  image="$(gcloud compute images list --filter="name~${1} AND -name~arm" --limit 1 | awk 'NR == 2')" || {
    printf >&2 'Error: Failed to query images\n'
    return 1
  }
  
  if [ -z "${image}" ]; then
    printf >&2 'Error: Unknown image pattern: %s\n' "$1"
    printf >&2 '%s\n' "$usage"
    return 1
  fi
  
  # Parse image info efficiently using read
  local image_name image_project
  {
    read -r image_name image_project _ <<< "$image"
  } 2>/dev/null || {
    printf >&2 'Error: Failed to parse image information\n'
    return 1
  }
  
  # Get default service account or use 'default'
  local default_service_account
  default_service_account="$(gcloud iam service-accounts list --filter="email:*-compute@developer.gserviceaccount.com" --format="value(email)" --limit=1)" || default_service_account=""
  
  # Use 'default' if no service account found
  if [[ -z "$default_service_account" ]]; then
    default_service_account="default"
  fi
  shift  # discards arg[1] and shifts the rest up
  
  # Validate machine type
  local machine_type
  machine_type="$(gcloud compute machine-types list --filter="name=${1}" --format="value(name)" --limit=1)" || {
    printf >&2 'Error: Failed to query machine types\n'
    return 1
  }
  
  if [ -z "${machine_type}" ]; then
    printf >&2 'Error: Unknown machine type: %s\n' "$1"
    printf >&2 '%s\n' "$usage"
    return 1
  fi
  shift
  local instance_names=("$@")
  if [ -n "${GPREFIX}" ]; then
    # Use parameter expansion instead of sed for better performance
    local prefixed_instances=()
    for instance in "${instance_names[@]}"; do
      validate_instance_name "$instance" || return 1
      prefixed_instances+=("${GPREFIX}-${instance}")
    done
    instance_names=("${prefixed_instances[@]}")
  else
    # Validate instance names even without prefix
    for instance in "${instance_names[@]}"; do
      validate_instance_name "$instance" || return 1
    done
  fi
  (set -x; gcloud compute instances create "${instance_names[@]}" \
    --labels "owner=${GUSER},expires-on=${expires},managed-by=oh-my-replicated" \
    --machine-type="${machine_type}" \
    --subnet=default --network-tier=PREMIUM --maintenance-policy=MIGRATE --can-ip-forward \
    --service-account="${default_service_account}" \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
    --image="${image_name}" --image-project="${image_project}" \
    --boot-disk-size=200GB --boot-disk-type=pd-ssd \
    --restart-on-failure \
    --create-disk size=100GB,type=pd-ssd,auto-delete=yes \
    --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --reservation-affinity=any)
}

gstart() {
  genv
  local usage="Usage: gstart [INSTANCE_NAMES]"
  if [ "$#" -lt 1 ]; then echo "${usage}"; return 1; fi
  local instance_name_prefix="$1"
  gcloud compute instances start "$(gcloud compute instances list --filter="labels.owner:${GUSER}" | awk '{if(NR>1)print}' | grep TERMINATED | grep "^${instance_name_prefix}" | awk '{print $1}' | xargs echo)"
}

gstop() {
  genv
  local usage="Usage: gstop [INSTANCE_NAMES]"
  if [ "$#" -lt 1 ]; then echo "${usage}"; return 1; fi
  local instance_name_prefix="$1"
  gcloud compute instances stop "$(gcloud compute instances list --filter="labels.owner:${GUSER}" | awk '{if(NR>1)print}' | grep RUNNING | grep "^${instance_name_prefix}" | awk '{print $1}' | xargs echo)"
}

gdelete() {
  genv
  local usage="Usage: gdelete [INSTANCE_NAME_PREFIX]"
  local instance_name_prefix="$1"
  if [ -n "${GPREFIX}" ]; then
    instance_name_prefix="${GPREFIX}-${instance_name_prefix}"
  fi
  if ! gcloud compute instances list --filter="labels.owner:${GUSER}" | awk '{if(NR>1)print}' | grep RUNNING | grep -q "^${instance_name_prefix}" ; then echo "no instances match \"labels.owner:${GUSER}\""; echo "${usage}"; return 1; fi
  gcloud compute instances delete --delete-disks=all "$(gcloud compute instances list --filter="labels.owner:${GUSER}" | awk '{if(NR>1)print}' | grep RUNNING | grep "^${instance_name_prefix}" | awk '{print $1}' | xargs echo)"
}

gonline() {
  genv
  local usage="Usage: gonline [INSTANCE_NAMES]"
  if [ "$#" -lt 1 ]; then echo "${usage}"; return 1; fi
  local instance
  for instance in "$@"; do
    local instance_name="${instance}"
    if [ -n "${GPREFIX}" ]; then
      instance_name="${GPREFIX}-${instance_name}"
    fi
    (set -x; gcloud compute instances add-access-config "${instance_name}" --access-config-name="external-nat")
  done
}

gairgap() {
  genv
  local usage="Usage: gairgap [INSTANCE_NAMES]"
  if [ "$#" -lt 1 ]; then echo "${usage}"; return 1; fi
  local instance
  for instance in "$@"; do
    local instance_name="${instance}"
    if [ -n "${GPREFIX}" ]; then
      instance_name="${GPREFIX}-${instance_name}"
    fi
    local access_config_name
    access_config_name="$(gcloud compute instances describe "${instance_name}" --format="value(networkInterfaces[0].accessConfigs[0].name)")"
    (set -x; gcloud compute instances delete-access-config "${instance_name}" --access-config-name="${access_config_name}")
  done
}

gssh-forward() {
  # genv
  local usage="Usage: gssh-forward [INSTANCE_NAME]"
  if [ "$#" -ne 1 ]; then echo "${usage}"; return 1; fi
  local instance_name="$1"
  if [ -n "${GPREFIX}" ]; then
    instance_name="${GPREFIX}-${instance_name}"
  fi
  # Get instance IPs
  local natip
  natip=$(gcloud compute instances describe "${instance_name}" --format="value(networkInterfaces[0].accessConfigs[0].natIP)") || {
    printf >&2 'Error: Failed to get external IP for instance: %s\n' "$instance_name"
    return 1
  }
  
  local ip
  ip=$(gcloud compute instances describe "${instance_name}" --format="value(networkInterfaces[0].networkIP)") || {
    printf >&2 'Error: Failed to get internal IP for instance: %s\n' "$instance_name"
    return 1
  }
  
  if [[ -z "$natip" ]]; then
    printf >&2 'Error: Instance %s has no external IP\n' "$instance_name"
    return 1
  fi
  
  # Use secure SSH configuration with improved security
  ssh -o ConnectTimeout=10 \
      -o ServerAliveInterval=60 \
      -o ServerAliveCountMax=3 \
      -o StrictHostKeyChecking=accept-new \
      -L "8800:${ip}:8800" \
      -L "8888:${ip}:8888" \
      "$natip"
}

gssh() {
  genv
  local usage="Usage: gssh [INSTANCE_NAME]"
  if [ "$#" -ne 1 ]; then echo "${usage}"; return 1; fi
  local instance_name="$1"
  if [ -n "${GPREFIX}" ]; then
    instance_name="${GPREFIX}-${instance_name}"
  fi
  while true; do
    start_time="$(date -u +%s)"
    gcloud compute ssh --tunnel-through-iap "${instance_name}"
    end_time="$(date -u +%s)"
    elapsed="$(bc <<<"$end_time-$start_time")"
    if [ "${elapsed}" -gt "60" ]; then # there must be a better way to do this
      return
    fi
    sleep 2
  done
}

gdisk() {
  genv
  local usage="Usage: gdisk [DISK_NAMES]"
  if [ "$#" -lt 1 ]; then echo "${usage}"; return 1; fi
  local disk_names=("$@")
  if [ -n "${GPREFIX}" ]; then
    # Use parameter expansion instead of sed for better performance  
    local prefixed_disks=()
    for disk in "${disk_names[@]}"; do
      prefixed_disks+=("${GPREFIX}-disk-${disk}")
    done
    disk_names=("${prefixed_disks[@]}")
  fi
  # Get expiration date for disk
  local expires
  expires=$(getdate) || {
    printf >&2 'Error: Failed to calculate expiration date\n'
    return 1
  }
  
  (set -x; gcloud compute disks create "${disk_names[@]}" \
    --labels "owner=${GUSER},expires-on=${expires},managed-by=oh-my-replicated" \
    --type=pd-balanced --size=100GB)
}

gattach() {
  genv
  local usage="Usage: gattach [INSTANCE_NAME] [DISK_NAME]"
  if [ "$#" -ne 2 ]; then echo "${usage}"; return 1; fi
  local instance_name="$1"
  local disk_name="disk-$2"
  local device_name="$1-disk-$2"
  if [ -n "${GPREFIX}" ]; then
    instance_name="${GPREFIX}-${instance_name}"
    disk_name="${GPREFIX}-${disk_name}"
    device_name="${GPREFIX}-${device_name}"
  fi
  (set -x; gcloud compute instances attach-disk "${instance_name}" --disk="${disk_name}" --device-name="${device_name}")
}

gtag() {
  genv
  local usage="Usage: gattach [INSTANCE_NAME] [comma-delimited list of TAGS]"
  if [ "$#" -ne 2 ]; then echo "${usage}"; return 1; fi
  local instance_name="$1"
  if [ -n "${GPREFIX}" ]; then
    instance_name="${GPREFIX}-${instance_name}"
  fi
  local tags="$2"
  (set -x; gcloud compute instances add-tags "${instance_name}" --tags="${tags}")
}
