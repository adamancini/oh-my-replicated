#!/bin/bash

# AWSUSER=
# AWSPREFIX=

if (( ! ${+commands[aws]} ));then
  >&2 echo "aws cli not installed, not loading replicated-awscommands plugin"
  return 1
fi

# Configuration constants (exported for potential external use)
export AWS_DEFAULT_PORTS=(22 80 443 8800 8888 30000)
export AWS_DEFAULT_VOLUME_SIZE="100"
export AWS_DEFAULT_VOLUME_TYPE="gp3"
export AWS_DEFAULT_INSTANCE_TYPE="t3.medium"
export AWS_DEFAULT_BOOT_DISK_SIZE="100"

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

validate_ami_id() {
    local ami_id="$1"
    
    if [[ ! "$ami_id" =~ ^ami-[0-9a-f]{8,17}$ ]]; then
        printf >&2 'Error: Invalid AMI ID format: %s\n' "$ami_id"
        printf >&2 'AMI IDs must be in format: ami-xxxxxxxxx\n'
        return 1
    fi
    
    return 0
}

validate_required_env() {
    if [[ -z "${AWSUSER:-}" ]]; then
        printf >&2 'Error: AWSUSER environment variable not set\n'
        printf >&2 'Set AWSUSER to your username: export AWSUSER="username"\n'
        return 1
    fi
    return 0
}

awsenv() {
    local profile region
    profile=$(aws configure list-profiles 2>/dev/null | head -1 || echo "default")
    region=$(aws configure get region 2>/dev/null || echo "us-east-1")
    
    printf >&2 'AWS Profile: %s\n' "$profile"
    printf >&2 'AWS Region: %s\n' "$region"
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

awslist() {
  validate_required_env || return 1
  awsenv
  
  if ! aws ec2 describe-instances \
    --filters "Name=tag:Owner,Values=${AWSUSER}" "Name=instance-state-name,Values=running,stopped,pending,stopping,starting" \
    --query "Reservations[*].Instances[*].[InstanceId,Tags[?Key==\`Name\`]|[0].Value,State.Name,InstanceType,PublicIpAddress,PrivateIpAddress]" \
    --output table; then
    printf >&2 'Error: Failed to list instances\n'
    return 1
  fi
}

awscreate() {
  local usage="Usage: awscreate [-d duration|never] <AMI_ID> <INSTANCE_TYPE> <INSTANCE_NAMES...>"
  local expires=""
  local OPTIND=1
  
  # Validate prerequisites
  validate_required_env || return 1
  awsenv
  
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
  if [[ $# -lt 3 ]]; then
    printf >&2 'Error: Insufficient arguments\n'
    printf >&2 '%s\n' "$usage"
    return 1
  fi
  
  local ami_id="$1"
  local instance_type="$2"
  shift 2
  local instance_names=("$@")
  
  # Validate AMI ID format and existence
  validate_ami_id "$ami_id" || return 1
  
  if ! aws ec2 describe-images --image-ids "${ami_id}" --query 'Images[0].ImageId' --output text >/dev/null 2>&1; then
    printf >&2 'Error: AMI %s not found or not accessible\n' "$ami_id"
    printf >&2 '%s\n' "$usage"
    return 1
  fi
  
  # Validate and process instance names
  if [ -n "${AWSPREFIX}" ]; then
    local prefixed_instances=()
    for instance in "${instance_names[@]}"; do
      validate_instance_name "$instance" || return 1
      prefixed_instances+=("${AWSPREFIX}-${instance}")
    done
    instance_names=("${prefixed_instances[@]}")
  else
    # Validate instance names even without prefix
    for instance in "${instance_names[@]}"; do
      validate_instance_name "$instance" || return 1
    done
  fi
  
  # Get default VPC and subnet with error handling
  local vpc_id
  vpc_id=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text) || {
    printf >&2 'Error: Failed to get default VPC\n'
    return 1
  }
  
  if [[ "$vpc_id" == "None" || -z "$vpc_id" ]]; then
    printf >&2 'Error: No default VPC found\n'
    return 1
  fi
  
  local subnet_id
  subnet_id=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${vpc_id}" --query 'Subnets[0].SubnetId' --output text) || {
    printf >&2 'Error: Failed to get subnet for VPC: %s\n' "$vpc_id"
    return 1
  }
  
  # Create or get security group
  local sg_name="${AWSUSER}-default-sg"
  local security_group_id
  security_group_id=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${sg_name}" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
  
  if [ "$security_group_id" = "None" ] || [ -z "$security_group_id" ]; then
    echo "Creating security group ${sg_name}"
    security_group_id=$(aws ec2 create-security-group --group-name "${sg_name}" --description "Default security group for ${AWSUSER}" --vpc-id "${vpc_id}" --query 'GroupId' --output text)
    # Add SSH access
    aws ec2 authorize-security-group-ingress --group-id "${security_group_id}" --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null
    # Add HTTP access
    aws ec2 authorize-security-group-ingress --group-id "${security_group_id}" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
    # Add HTTPS access
    aws ec2 authorize-security-group-ingress --group-id "${security_group_id}" --protocol tcp --port 443 --cidr 0.0.0.0/0 >/dev/null
    # Add port 8800 (Replicated admin)
    aws ec2 authorize-security-group-ingress --group-id "${security_group_id}" --protocol tcp --port 8800 --cidr 0.0.0.0/0 >/dev/null
    # Add port 8888 (common dev port)
    aws ec2 authorize-security-group-ingress --group-id "${security_group_id}" --protocol tcp --port 8888 --cidr 0.0.0.0/0 >/dev/null
    # Add port 30000 (embedded-cluster admin console)
    aws ec2 authorize-security-group-ingress --group-id "${security_group_id}" --protocol tcp --port 30000 --cidr 0.0.0.0/0 >/dev/null
  fi
  
  for instance_name in "${instance_names[@]}"; do
    local full_name="${instance_name}"
    if [ -n "${AWSPREFIX}" ]; then
      full_name="${AWSPREFIX}-${instance_name}"
    fi
    
    echo "Creating instance: ${full_name}"
    (set -x; aws ec2 run-instances \
      --image-id "${ami_id}" \
      --instance-type "${instance_type}" \
      --subnet-id "${subnet_id}" \
      --security-group-ids "${security_group_id}" \
      --associate-public-ip-address \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${full_name}},{Key=owner,Value=${AWSUSER}},{Key=expires-on,Value=${expires}},{Key=managed-by,Value=oh-my-replicated}]" "ResourceType=volume,Tags=[{Key=Name,Value=${full_name}-root},{Key=owner,Value=${AWSUSER}},{Key=expires-on,Value=${expires}},{Key=managed-by,Value=oh-my-replicated}]" \
      --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":100,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
      --query 'Instances[0].[InstanceId,State.Name,PublicIpAddress]' \
      --output table)
  done
}

awsstart() {
  validate_required_env || return 1
  awsenv
  local usage="Usage: awsstart [INSTANCE_NAME_PREFIX]"
  if [ "$#" -lt 1 ]; then 
    printf >&2 '%s\n' "${usage}"
    return 1
  fi
  
  local instance_name_prefix="$1"
  if [ -n "${AWSPREFIX}" ]; then
    instance_name_prefix="${AWSPREFIX}-${instance_name_prefix}"
  fi
  
  local instance_ids
  instance_ids=$(aws ec2 describe-instances \
    --filters "Name=tag:Owner,Values=${AWSUSER}" "Name=tag:Name,Values=${instance_name_prefix}*" "Name=instance-state-name,Values=stopped" \
    --query 'Reservations[*].Instances[*].InstanceId' --output text) || {
    printf >&2 'Error: Failed to query instances\n'
    return 1
  }
  
  if [ -n "$instance_ids" ]; then
    (set -x; aws ec2 start-instances --instance-ids "${instance_ids}")
  else
    printf 'No stopped instances found matching %s\n' "${instance_name_prefix}"
  fi
}

awsstop() {
  validate_required_env || return 1
  awsenv
  local usage="Usage: awsstop [INSTANCE_NAME_PREFIX]"
  if [ "$#" -lt 1 ]; then 
    printf >&2 '%s\n' "${usage}"
    return 1
  fi
  
  local instance_name_prefix="$1"
  if [ -n "${AWSPREFIX}" ]; then
    instance_name_prefix="${AWSPREFIX}-${instance_name_prefix}"
  fi
  
  local instance_ids
  instance_ids=$(aws ec2 describe-instances \
    --filters "Name=tag:Owner,Values=${AWSUSER}" "Name=tag:Name,Values=${instance_name_prefix}*" "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].InstanceId' --output text) || {
    printf >&2 'Error: Failed to query instances\n'
    return 1
  }
  
  if [ -n "$instance_ids" ]; then
    (set -x; aws ec2 stop-instances --instance-ids "${instance_ids}")
  else
    printf 'No running instances found matching %s\n' "${instance_name_prefix}"
  fi
}

awsdelete() {
  validate_required_env || return 1
  awsenv
  local usage="Usage: awsdelete [INSTANCE_NAME_PREFIX]"
  if [ "$#" -lt 1 ]; then 
    printf >&2 '%s\n' "${usage}"
    return 1
  fi
  
  local instance_name_prefix="$1"
  if [ -n "${AWSPREFIX}" ]; then
    instance_name_prefix="${AWSPREFIX}-${instance_name_prefix}"
  fi
  
  local instance_ids
  instance_ids=$(aws ec2 describe-instances \
    --filters "Name=tag:Owner,Values=${AWSUSER}" "Name=tag:Name,Values=${instance_name_prefix}*" "Name=instance-state-name,Values=running,stopped,pending,stopping,starting" \
    --query 'Reservations[*].Instances[*].InstanceId' --output text) || {
    printf >&2 'Error: Failed to query instances\n'
    return 1
  }
  
  if [ -n "$instance_ids" ]; then
    printf 'Terminating instances: %s\n' "${instance_ids}"
    (set -x; aws ec2 terminate-instances --instance-ids "${instance_ids}")
  else
    printf 'No instances found matching %s\n' "${instance_name_prefix}"
  fi
}

awsssh() {
  validate_required_env || return 1
  awsenv
  local usage="Usage: awsssh [INSTANCE_NAME]"
  if [ "$#" -ne 1 ]; then 
    printf >&2 '%s\n' "${usage}"
    return 1
  fi
  
  local instance_name="$1"
  validate_instance_name "$instance_name" || return 1
  
  if [ -n "${AWSPREFIX}" ]; then
    instance_name="${AWSPREFIX}-${instance_name}"
  fi
  
  local public_ip
  public_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Owner,Values=${AWSUSER}" "Name=tag:Name,Values=${instance_name}" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text) || {
    printf >&2 'Error: Failed to query instance: %s\n' "$instance_name"
    return 1
  }
  
  if [ "$public_ip" = "None" ] || [ -z "$public_ip" ]; then
    printf >&2 'No running instance found with name %s or no public IP\n' "${instance_name}"
    return 1
  fi
  
  # Try common usernames for different AMIs
  local usernames=("ec2-user" "ubuntu" "admin" "centos" "fedora")
  for username in "${usernames[@]}"; do
    printf 'Trying to connect as %s@%s\n' "$username" "$public_ip"
    if timeout 10s ssh -o ConnectTimeout=10 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new -q "${username}@${public_ip}" exit 2>/dev/null; then
      ssh -o ConnectTimeout=10 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new "${username}@${public_ip}"
      return $?
    fi
  done
  printf >&2 'Could not connect to %s (%s) with any common username\n' "$instance_name" "$public_ip"
  return 1
}

awsssh-forward() {
  validate_required_env || return 1
  awsenv
  local usage="Usage: awsssh-forward [INSTANCE_NAME]"
  if [ "$#" -ne 1 ]; then 
    printf >&2 '%s\n' "${usage}"
    return 1
  fi
  
  local instance_name="$1"
  validate_instance_name "$instance_name" || return 1
  
  if [ -n "${AWSPREFIX}" ]; then
    instance_name="${AWSPREFIX}-${instance_name}"
  fi
  
  # Optimize by getting both IPs in one call
  local instance_data
  instance_data=$(aws ec2 describe-instances \
    --filters "Name=tag:Owner,Values=${AWSUSER}" "Name=tag:Name,Values=${instance_name}" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress]' --output text) || {
    printf >&2 'Error: Failed to query instance: %s\n' "$instance_name"
    return 1
  }
  
  local public_ip private_ip
  {
    read -r public_ip private_ip <<< "$instance_data"
  } 2>/dev/null || {
    printf >&2 'Error: Failed to parse instance data\n'
    return 1
  }
  
  if [ "$public_ip" = "None" ] || [ -z "$public_ip" ]; then
    printf >&2 'No running instance found with name %s or no public IP\n' "${instance_name}"
    return 1
  fi
  
  # Try common usernames
  local usernames=("ec2-user" "ubuntu" "admin" "centos" "fedora")
  for username in "${usernames[@]}"; do
    if timeout 10s ssh -o ConnectTimeout=10 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new -q "${username}@${public_ip}" exit 2>/dev/null; then
      printf 'Connecting with port forwarding: 8800:%s:8800 and 8888:%s:8888\n' "$private_ip" "$private_ip"
      ssh -L "8800:${private_ip}:8800" -L "8888:${private_ip}:8888" -o ConnectTimeout=10 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new "${username}@${public_ip}"
      return $?
    fi
  done
  printf >&2 'Could not connect to %s (%s) with any common username\n' "$instance_name" "$public_ip"
  return 1
}

awsvolume() {
  validate_required_env || return 1
  awsenv
  local usage="Usage: awsvolume [VOLUME_NAME] [SIZE_GB]"
  if [ "$#" -lt 2 ]; then 
    printf >&2 '%s\n' "${usage}"
    return 1
  fi
  
  local volume_name="$1"
  local size="$2"
  
  # Validate volume name and size
  validate_instance_name "$volume_name" || return 1
  
  if ! [[ "$size" =~ ^[0-9]+$ ]] || [ "$size" -lt 1 ] || [ "$size" -gt 16384 ]; then
    printf >&2 'Error: Invalid volume size: %s (must be 1-16384 GB)\n' "$size"
    return 1
  fi
  
  if [ -n "${AWSPREFIX}" ]; then
    volume_name="${AWSPREFIX}-vol-${volume_name}"
  else
    volume_name="vol-${volume_name}"
  fi
  
  local availability_zone
  availability_zone=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].ZoneName' --output text) || {
    printf >&2 'Error: Failed to get availability zone\n'
    return 1
  }
  
  # Get expiration date for volume  
  local expires
  expires=$(getdate) || {
    printf >&2 'Error: Failed to calculate expiration date\n'
    return 1
  }
  
  (set -x; aws ec2 create-volume \
    --size "${size}" \
    --volume-type "${AWS_DEFAULT_VOLUME_TYPE}" \
    --availability-zone "${availability_zone}" \
    --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=${volume_name}},{Key=owner,Value=${AWSUSER}},{Key=expires-on,Value=${expires}},{Key=managed-by,Value=oh-my-replicated}]")
}

awsattach() {
  validate_required_env || return 1
  awsenv
  local usage="Usage: awsattach [INSTANCE_NAME] [VOLUME_NAME]"
  if [ "$#" -ne 2 ]; then 
    printf >&2 '%s\n' "${usage}"
    return 1
  fi
  
  local instance_name="$1"
  local volume_name="$2"
  
  # Validate names
  validate_instance_name "$instance_name" || return 1
  validate_instance_name "$volume_name" || return 1
  
  if [ -n "${AWSPREFIX}" ]; then
    instance_name="${AWSPREFIX}-${instance_name}"
    volume_name="${AWSPREFIX}-vol-${volume_name}"
  else
    volume_name="vol-${volume_name}"
  fi
  
  local instance_id
  instance_id=$(aws ec2 describe-instances \
    --filters "Name=tag:Owner,Values=${AWSUSER}" "Name=tag:Name,Values=${instance_name}" "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text) || {
    printf >&2 'Error: Failed to query instance: %s\n' "$instance_name"
    return 1
  }
  
  local volume_id
  volume_id=$(aws ec2 describe-volumes \
    --filters "Name=tag:Owner,Values=${AWSUSER}" "Name=tag:Name,Values=${volume_name}" \
    --query 'Volumes[0].VolumeId' --output text) || {
    printf >&2 'Error: Failed to query volume: %s\n' "$volume_name"
    return 1
  }
  
  if [ "$instance_id" = "None" ] || [ -z "$instance_id" ]; then
    printf >&2 'Instance %s not found\n' "${instance_name}"
    return 1
  fi
  
  if [ "$volume_id" = "None" ] || [ -z "$volume_id" ]; then
    printf >&2 'Volume %s not found\n' "${volume_name}"
    return 1
  fi
  
  (set -x; aws ec2 attach-volume --volume-id "${volume_id}" --instance-id "${instance_id}" --device /dev/sdf)
}

awstag() {
  validate_required_env || return 1
  awsenv
  local usage="Usage: awstag [INSTANCE_NAME] [KEY=VALUE] [KEY=VALUE]..."
  if [ "$#" -lt 2 ]; then 
    printf >&2 '%s\n' "${usage}"
    return 1
  fi
  
  local instance_name="$1"
  validate_instance_name "$instance_name" || return 1
  shift
  
  if [ -n "${AWSPREFIX}" ]; then
    instance_name="${AWSPREFIX}-${instance_name}"
  fi
  
  local instance_id
  instance_id=$(aws ec2 describe-instances \
    --filters "Name=tag:Owner,Values=${AWSUSER}" "Name=tag:Name,Values=${instance_name}" "Name=instance-state-name,Values=running,stopped,pending" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text) || {
    printf >&2 'Error: Failed to query instance: %s\n' "$instance_name"
    return 1
  }
  
  if [ "$instance_id" = "None" ] || [ -z "$instance_id" ]; then
    printf >&2 'Instance %s not found\n' "${instance_name}"
    return 1
  fi
  
  local tags=""
  for tag in "$@"; do
    if [[ "$tag" =~ ^([^=]+)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"
      tags="${tags} Key=${key},Value=${value}"
    else
      printf >&2 'Invalid tag format: %s. Use KEY=VALUE format.\n' "$tag"
      return 1
    fi
  done
  
  (set -x; aws ec2 create-tags --resources "${instance_id}" --tags "${tags}")
}

awsamis() {
  validate_required_env || return 1
  awsenv
  local usage="Usage: awsamis [SEARCH_TERM]"
  local search_term="${1:-ubuntu}"
  
  # Validate search term
  if [[ ! "$search_term" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    printf >&2 'Error: Invalid search term: %s\n' "$search_term"
    printf >&2 'Search terms must contain only letters, numbers, dots, hyphens, and underscores\n'
    return 1
  fi
  
  printf 'Searching for AMIs containing: %s\n' "${search_term}"
  
  if ! aws ec2 describe-images \
    --owners 099720109477 137112412989 amazon \
    --filters "Name=name,Values=*${search_term}*" "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-10:].[ImageId,Name,CreationDate]' \
    --output table; then
    printf >&2 'Error: Failed to search AMIs\n'
    return 1
  fi
}