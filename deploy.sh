#!/usr/bin/env bash

set -euo pipefail

#==============================================================================
# Akamai Cloud (Linode) GPU Instance Setup Script
#
# This script automates the creation of a GPU instance with vLLM and Open-WebUI
#
# Usage:
#   ./setup.sh
#
#==============================================================================

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper functions
source "${SCRIPT_DIR}/script/ask_selection.sh"

# Additional colors not defined in ask_selection.sh
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
MAGENTA='\033[0;35m'
BOLD='\033[1m'

# API base URL
readonly API_BASE="https://api.linode.com/v4"

# Global variables
TOKEN=""
INSTANCE_LABEL=""
INSTANCE_PASSWORD=""
SSH_PUBLIC_KEY=""
SELECTED_REGION=""
SELECTED_TYPE=""
INSTANCE_IP=""
INSTANCE_ID=""

# Log file setup
LOG_FILE="${SCRIPT_DIR}/start-$(date +%Y%m%d-%H%M%S).log"

#==============================================================================
# Helper Functions
#==============================================================================

# Log to file (strips color codes)
log_to_file() {
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local level="$1"
    shift
    # Strip ANSI color codes and log
    echo "[$timestamp] [$level] $*" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
}

# Print colored message
print_msg() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# Print error and exit
error_exit() {
    local message="$1"
    local offer_delete="${2:-false}"

    print_msg "$RED" "❌ ERROR: $message"
    log_to_file "ERROR" "$message"

    # Offer to delete instance if requested and instance was created
    if [ "$offer_delete" = "true" ] && [ -n "${INSTANCE_ID:-}" ]; then
        echo ""
        printf '\n\n\n\033[3A'        # Print 3 blank lines to scroll up
        read -p "$(echo -e ${YELLOW}Do you want to delete the failed instance? [Y/n]:${NC} )" delete_choice
        delete_choice=${delete_choice:-Y}

        if [[ "$delete_choice" =~ ^[Yy]$ ]]; then
            echo ""
            print_msg "$YELLOW" "Deleting instance (ID: ${INSTANCE_ID})..."

            if curl -s -X DELETE \
                -H "Authorization: Bearer ${TOKEN}" \
                "${API_BASE}/linode/instances/${INSTANCE_ID}" > /dev/null; then
                success "Instance deleted successfully"
            else
                warn "Failed to delete instance. You may need to delete it manually from the Linode Cloud Manager"
                info "Instance ID: ${INSTANCE_ID}"
            fi
        else
            info "Instance was not deleted. You can manage it from the Linode Cloud Manager"
            info "Instance ID: ${INSTANCE_ID}"
        fi
    fi

    exit 1
}

# Print success message
success() {
    print_msg "$GREEN" "✅ $*"
}

# Print info message
info() {
    print_msg "$CYAN" "ℹ️  $*"
}

# Print warning message
warn() {
    print_msg "$YELLOW" "⚠️  $*"
}

# Show banner
show_banner() {
    clear
    cat "${SCRIPT_DIR}/script/logo/akamai.txt" || {
        echo "==================================="
        echo "  Akamai Cloud GPU Instance Setup"
        echo "==================================="
    }
    echo ""
}

#==============================================================================
# Show Logo
#==============================================================================
show_banner

print_msg "$CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_msg "$BOLD" "                    AI Quickstart LLM"
print_msg "$CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
print_msg "$YELLOW" "This script will:"
echo "  • Ask you to authenticate with your Linode/Akamai Cloud account"
echo "  • Deploy a fully configured GPU instance in your account with:"
echo "    - Docker and Docker Compose"
echo "    - NVIDIA drivers and Container Toolkit"
echo "    - vLLM (LLM inference server)"
echo "    - Pre-loaded model: unsloth/gpt-oss-20b"
echo "    - Open-WebUI (web interface)"
echo ""
print_msg "$GREEN" "Setup time: ~10-15 minutes"
print_msg "$CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

sleep 3

#==============================================================================
# Get Token from linode-cli or Linode OAuth
#==============================================================================
echo "------------------------------------------------------"
print_msg "$BOLD" "🔑 Step 1/10: Obtaining Linode API credentials..."
echo "------------------------------------------------------"

# Try to get token from check_linodecli_token.sh
if [ -f "${SCRIPT_DIR}/script/check_linodecli_token.sh" ]; then
    TOKEN=$("${SCRIPT_DIR}/script/check_linodecli_token.sh" --silent 2>/dev/null || true)
fi

# If no token, try OAuth
if [ -z "$TOKEN" ] && [ -f "${SCRIPT_DIR}/script/linode_oauth.sh" ]; then
    TOKEN=$("${SCRIPT_DIR}/script/linode_oauth.sh" || true)
fi

# Verify we have a token
if [ -z "$TOKEN" ]; then
    error_exit "Failed to get API token. Please configure linode-cli or run linode_oauth.sh"
fi

success "API credentials obtained successfully"
echo ""

#==============================================================================
# Get GPU Availability
#==============================================================================
echo "------------------------------------------------------"
print_msg "$BOLD" "📊 Step 2/10: Fetching GPU availability..."
echo "------------------------------------------------------"

if [ ! -f "${SCRIPT_DIR}/script/get_gpu_availability.sh" ]; then
    error_exit "get_gpu_availability.sh not found"
fi

# Export token so get_gpu_availability.sh doesn't need to fetch it again
export LINODE_TOKEN="$TOKEN"

GPU_DATA=$("${SCRIPT_DIR}/script/get_gpu_availability.sh" --silent)

if [ -z "$GPU_DATA" ]; then
    error_exit "Failed to fetch GPU availability data"
fi

info "GPU availability data fetched successfully"
echo ""

#==============================================================================
# Let User Select Region
#==============================================================================
echo "------------------------------------------------------"
print_msg "$BOLD" "🌍 Step 3/10: Select Region"
echo "------------------------------------------------------"

# Extract regions with available GPU instances
AVAILABLE_REGIONS=()
while IFS= read -r line; do
    AVAILABLE_REGIONS+=("$line")
done < <(echo "$GPU_DATA" | jq -r '.regions[] | "\(.id)|\(.label)|\(.instance_types | join(","))"')

if [ ${#AVAILABLE_REGIONS[@]} -eq 0 ]; then
    error_exit "No regions with available GPU instances found"
fi

print_msg "$GREEN" "Available Regions:"

# Build display array for regions with proper formatting
REGION_DISPLAY=()
for i in "${!AVAILABLE_REGIONS[@]}"; do
    IFS='|' read -r region_id region_label types <<< "${AVAILABLE_REGIONS[$i]}"
    # Format: "region_id (12 chars) region_label"
    printf -v formatted_option "%-12s %s" "$region_id" "$region_label"
    REGION_DISPLAY+=("$formatted_option")
done

# Use ask_selection for region choice
ask_selection "Enter region number" REGION_DISPLAY "" region_choice SELECTED_REGION_DISPLAY

# Get full region info from the original array using the selection index
IFS='|' read -r SELECTED_REGION region_label region_types <<< "${AVAILABLE_REGIONS[$((region_choice-1))]}"

echo "Selected region: $SELECTED_REGION ($region_label)"
log_to_file "INFO" "User selected region: $SELECTED_REGION ($region_label)"
echo ""

#==============================================================================
# Let User Select Instance Type
#==============================================================================
echo "------------------------------------------------------"
print_msg "$BOLD" "💻 Step 4/10: Select Instance Type"
echo "------------------------------------------------------"

# Get available instance types for selected region
print_msg "$GREEN" "Available Instance Types in $SELECTED_REGION:"

# Build arrays for instance types
declare -a TYPE_OPTIONS=()
declare -a TYPE_DISPLAY=()
default_type_index=""

while IFS= read -r type_data; do
    type_id=$(echo "$type_data" | jq -r '.id')
    echo "$region_types" | grep -q "$type_id" || continue

    # Extract all fields and format display string with proper spacing
    TYPE_OPTIONS+=("$type_data")
    IFS=$'\t' read -r id lbl vcpus mem hr mo < <(echo "$type_data" | jq -r '[.id, .label, .vcpus, (.memory/1024|floor), .hourly, .monthly] | @tsv')
    printf -v formatted_option "%-20s %-35s ${CYAN}%d vCPUs, %dGB RAM - \$%.2f/hr (\$%.1f/mo)${NC}" "$id" "$lbl" "$vcpus" "$mem" "$hr" "$mo"
    TYPE_DISPLAY+=("$formatted_option")

    # Set default to first g2-gpu-rtx4000a1-s found
    if [ "$id" = "g2-gpu-rtx4000a1-s" ] && [ -z "$default_type_index" ]; then
        default_type_index=${#TYPE_DISPLAY[@]}
    fi
done < <(echo "$GPU_DATA" | jq -c '.instance_types[]')

if [ ${#TYPE_OPTIONS[@]} -eq 0 ]; then
    error_exit "No instance types available in selected region"
fi

# Use ask_selection for instance type choice
ask_selection "Enter instance type number" TYPE_DISPLAY "$default_type_index" type_choice SELECTED_TYPE_DISPLAY "\n     ${MAGENTA}⭐ RECOMMENDED${NC}"

# Extract the actual type ID from the selected option
SELECTED_TYPE=$(echo "${TYPE_OPTIONS[$((type_choice-1))]}" | jq -r '.id')

echo "Selected instance type: $SELECTED_TYPE"
log_to_file "INFO" "User selected instance type: $SELECTED_TYPE"
echo ""

#==============================================================================
# Let User Specify Instance Label
#==============================================================================
echo "------------------------------------------------------"
print_msg "$BOLD" "🏷️  Step 5/10: Instance Label"
echo "------------------------------------------------------"
echo ""

# Validate label: alphanumeric start/end, only a-z A-Z 0-9 _ - . allowed, no consecutive specials
validate_label() {
    [[ ! "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?$ ]] && echo "Label must start/end with alphanumeric, use only: a-z A-Z 0-9 _ - ." && return 1
    [[ "$1" =~ --|__|\.\. ]] && echo "Label cannot contain consecutive -- __ or .." && return 1
    return 0
}

DEFAULT_LABEL="ai-quickstart-llm-$(date +%y%m%d%H%M)"
while true; do
    printf '\n\n\n\n\n\033[5A'        # Print 5 blank lines to scroll up
    read -p "$(echo -e ${YELLOW}Enter instance label [default: $DEFAULT_LABEL]:${NC} )" user_label
    INSTANCE_LABEL="${user_label:-$DEFAULT_LABEL}"
    validate_label "$INSTANCE_LABEL" && break
    print_msg "$RED" "❌ Invalid label format"
    echo ""
done

echo "Instance label: $INSTANCE_LABEL"
log_to_file "INFO" "User set instance label: $INSTANCE_LABEL"
echo ""

#==============================================================================
# Let User Specify Root Password
#==============================================================================
echo "------------------------------------------------------"
print_msg "$BOLD" "🔐 Step 6/10: Root Password"
echo "------------------------------------------------------"
echo ""

# Function to generate random password
generate_password() {
    # Generate a 15 character password with uppercase, lowercase, numbers, and special chars
    local chars='A-Za-z0-9!@#$%^&*()_+-='
    LC_ALL=C tr -dc "$chars" < /dev/urandom | head -c 15 2>/dev/null || true
}

# Function to validate password
validate_password() {
    local pwd="$1"
    [[ ${#pwd} -ge 11 && "$pwd" =~ [A-Z] && "$pwd" =~ [a-z] && "$pwd" =~ [0-9] && "$pwd" =~ [^A-Za-z0-9] ]]
}

info "Password requirements: min 11 chars, must include uppercase, lowercase, numbers, and special characters"

while true; do
    printf '\n\n\n\n\n\033[5A'        # Print 5 blank lines to scroll up
    read -s -p "$(echo -e ${YELLOW}Enter root password [leave empty to auto-generate]:${NC} )" user_password
    echo ""

    if [ -z "$user_password" ]; then
        INSTANCE_PASSWORD=$(generate_password)
        [ -z "$INSTANCE_PASSWORD" ] || [ ${#INSTANCE_PASSWORD} -lt 10 ] && error_exit "Failed to generate password"
        log_to_file "INFO" "Password auto-generated: $INSTANCE_PASSWORD"
        echo "Password Auto-generated." && break
    fi

    validate_password "$user_password" || { warn "Password does not meet requirements. Please try again."; continue; }
    read -s -p "$(echo -e ${YELLOW}Confirm password:${NC} )" user_password_confirm
    echo ""
    if [ "$user_password" = "$user_password_confirm" ]; then
        INSTANCE_PASSWORD="$user_password"
        log_to_file "INFO" "User typed password: *************"
        echo "Password accepted"
        break
    fi
    warn "Passwords do not match. Please try again."
done
echo ""

#==============================================================================
# Let User Select SSH Public Key
#==============================================================================
echo "------------------------------------------------------"
print_msg "$BOLD" "🔑 Step 7/10: SSH Public Key (Required)"
echo "------------------------------------------------------"
echo ""

info "An SSH key is required for secure access to the instance"

# Find SSH public keys (portable array population)
SSH_KEYS=()
while IFS= read -r key; do
    SSH_KEYS+=("$key")
done < <(find "$HOME/.ssh" -maxdepth 1 -name "*.pub" -type f 2>/dev/null | sort)

# Build display array for SSH keys
print_msg "$GREEN" "SSH Key Options:"
declare -a SSH_KEY_DISPLAY=()

for i in "${!SSH_KEYS[@]}"; do
    key_basename="$(basename "${SSH_KEYS[$i]}")"
    key_preview="$(head -c 60 "${SSH_KEYS[$i]}")"
    printf -v formatted_option "%-30s %s..." "$key_basename" "$key_preview"
    SSH_KEY_DISPLAY+=("$formatted_option")
done

# Add auto-generate option
SSH_KEY_DISPLAY+=("${YELLOW}Auto-generate new SSH key pair${NC}")

# Use ask_selection for SSH key choice
ask_selection "Enter SSH key option" SSH_KEY_DISPLAY "" key_choice SELECTED_KEY_DISPLAY

# Handle selection
if [ "$key_choice" -le ${#SSH_KEYS[@]} ]; then
    SSH_PUBLIC_KEY=$(cat "${SSH_KEYS[$((key_choice-1))]}")
    log_to_file "INFO" "User selected SSH key: $(basename "${SSH_KEYS[$((key_choice-1))]}")"
    echo "Selected SSH key: $(basename "${SSH_KEYS[$((key_choice-1))]}")"
else
    NEW_KEY_PATH="$HOME/.ssh/linode-${INSTANCE_LABEL}-$(date +%s)"
    NEW_KEY_NAME="$(basename "$NEW_KEY_PATH")"
    info "Generating new SSH key pair: ${NEW_KEY_NAME}"
    ssh-keygen -t ed25519 -f "$NEW_KEY_PATH" -N "" -C "${NEW_KEY_NAME}" >/dev/null 2>&1 || error_exit "Failed to generate SSH key"
    SSH_PUBLIC_KEY=$(cat "${NEW_KEY_PATH}.pub")
    log_to_file "INFO" "Auto-generated SSH key: ${NEW_KEY_PATH}"
    log_to_file "INFO" "SSH public key: ${SSH_PUBLIC_KEY}"
    success "Generated new SSH key: ${NEW_KEY_PATH}"
    info "Private key saved to: ${NEW_KEY_PATH}"
    warn "IMPORTANT: Save the private key securely!"
fi
echo ""

#==============================================================================
# Create Cloud-Init with Base64 Encoded Files
#==============================================================================

# Base64 encode docker-compose.yml
if [ ! -f "${SCRIPT_DIR}/template/docker-compose.yml" ]; then
    error_exit "template/docker-compose.yml not found"
fi
DOCKER_COMPOSE_BASE64=$(base64 < "${SCRIPT_DIR}/template/docker-compose.yml" | tr -d '\n')

# Base64 encode install.sh (need to add notify function)
if [ ! -f "${SCRIPT_DIR}/template/install.sh" ]; then
    error_exit "template/install.sh not found"
fi
INSTALL_SH_BASE64=$(base64 < "${SCRIPT_DIR}/template/install.sh" | tr -d '\n')

# Read cloud-init template
if [ ! -f "${SCRIPT_DIR}/template/cloud-init.yaml" ]; then
    error_exit "template/cloud-init.yaml not found"
fi

# Create temporary cloud-init file with replacements
CLOUD_INIT_DATA=$(cat "${SCRIPT_DIR}/template/cloud-init.yaml" | \
    sed "s|INSTANCE_LABEL_PLACEHOLDER|${INSTANCE_LABEL}|g" | \
    sed "s|DOCKER_COMPOSE_BASE64_CONTENT_PLACEHOLDER|${DOCKER_COMPOSE_BASE64}|g" | \
    sed "s|INSTALL_SH_BASE64_CONTENT_PLACEHOLDER|${INSTALL_SH_BASE64}|g")

#==============================================================================
# Show Confirmation Prompt
#==============================================================================
echo "------------------------------------------------------"
print_msg "$BOLD" "📝 Step 8/10: Confirmation ..."
echo "------------------------------------------------------"

UBUNTU_IMAGE="linode/ubuntu24.04"

info "Instance configuration:"
echo "  Region: $SELECTED_REGION"
echo "  Type: $SELECTED_TYPE"
echo "  Label: $INSTANCE_LABEL"
echo "  Image: $UBUNTU_IMAGE"
if [ "$key_choice" -gt ${#SSH_KEYS[@]} ]; then
    echo "  SSH Key: ${NEW_KEY_NAME} (auto-generated)"
else
    echo "  SSH Key: $(basename "${SSH_KEYS[$((key_choice-1))]}")"
fi
echo ""

# Ask for confirmation
printf '\n\n\n\n\n\033[5A'        # Print 5 blank lines to scroll up
read -p "$(echo -e ${YELLOW}Proceed with instance creation? [Y/n]:${NC} )" confirm
confirm=${confirm:-Y}

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    warn "Instance creation cancelled by user"
    exit 0
fi
echo ""

#==============================================================================
# Create Instance via Linode API
#==============================================================================
echo "------------------------------------------------------"
print_msg "$BOLD" "🚀 Step 9/10: Creating instance ..."
echo "------------------------------------------------------"
printf '\n\n\n\n\n\033[5A'        # Print 5 blank lines to scroll up

# Encode cloud-init as base64
USER_DATA_BASE64=$(echo "$CLOUD_INIT_DATA" | base64 | tr -d '\n')

# Build JSON payload
JSON_PAYLOAD=$(jq -n \
    --arg label "$INSTANCE_LABEL" \
    --arg region "$SELECTED_REGION" \
    --arg type "$SELECTED_TYPE" \
    --arg image "$UBUNTU_IMAGE" \
    --arg pass "$INSTANCE_PASSWORD" \
    --arg userdata "$USER_DATA_BASE64" \
    --arg sshkey "$SSH_PUBLIC_KEY" \
    '{label: $label, region: $region, type: $type, image: $image, root_pass: $pass,
      metadata: {user_data: $userdata}, authorized_keys: [$sshkey],
      booted: true, backups_enabled: false, private_ip: false}')

log_to_file "INFO" "API Request: POST ${API_BASE}/linode/instances"
log_to_file "INFO" "Request payload: label=$INSTANCE_LABEL, region=$SELECTED_REGION, type=$SELECTED_TYPE, image=$UBUNTU_IMAGE"

CREATE_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    "${API_BASE}/linode/instances" \
    -d "$JSON_PAYLOAD")

log_to_file "INFO" "API Response: $CREATE_RESPONSE"

# Check for errors
if echo "$CREATE_RESPONSE" | jq -e '.errors' > /dev/null 2>&1; then
    error_exit "Failed to create instance: $(echo "$CREATE_RESPONSE" | jq -r '.errors[0].reason')"
fi

INSTANCE_ID=$(echo "$CREATE_RESPONSE" | jq -r '.id')
INSTANCE_IP=$(echo "$CREATE_RESPONSE" | jq -r '.ipv4[0]')

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "null" ]; then
    error_exit "Failed to create instance: Invalid response"
fi

# Save instance data with password
INSTANCE_FILE="${SCRIPT_DIR}/${INSTANCE_LABEL}.json"
echo "$CREATE_RESPONSE" | jq --arg password "$INSTANCE_PASSWORD" '. + {root_password: $password}' > "$INSTANCE_FILE"

log_to_file "INFO" "Instance created: ID=$INSTANCE_ID, IP=$INSTANCE_IP, Label=$INSTANCE_LABEL"

info "Instance created successfully, starting up..."
echo "  Instance ID: $INSTANCE_ID"
echo "  IP Address: $INSTANCE_IP"
echo "  Instance detail saved to:   $INSTANCE_FILE"
echo ""

#==============================================================================
# Wait for Instance to be Ready
#==============================================================================
echo "------------------------------------------------------"
print_msg "$BOLD" "⏳ Step 10: Monitoring Deployment ..."
echo "------------------------------------------------------"
printf '\n\n\n\n\n\n\n\n\033[8A'        # Print 8 blank lines to scroll up

#------------------------------------------------------------------------------
# Phase 1: Wait for instance status to become "running" (max 3 minutes)
#------------------------------------------------------------------------------
print_msg "$YELLOW" "Waiting instance to boot up ... (this may take 2 - 3 minutes)"
START_TIME=$(date +%s)
TIMEOUT=180

while true; do
    STATUS=$(curl -s -H "Authorization: Bearer ${TOKEN}" "${API_BASE}/linode/instances/${INSTANCE_ID}" | jq -r '.status')
    [ "$STATUS" = "running" ] && break

    ELAPSED=$(($(date +%s) - START_TIME))
    [ $ELAPSED -ge $TIMEOUT ] && break

    ELAPSED_STR=$([ $ELAPSED -ge 60 ] && echo "$((ELAPSED / 60))m $((ELAPSED % 60))s" || echo "${ELAPSED}s")
    echo -ne "\r\033[K${YELLOW}Status: ${STATUS:-unknown} - Elapsed: ${ELAPSED_STR}${NC}"
    sleep 5
done

[ "$STATUS" != "running" ] && error_exit "Instance failed to reach 'running' status" true
ELAPSED=$(($(date +%s) - START_TIME))
log_to_file "INFO" "Instance status reached 'running' in ${ELAPSED}s"
echo -ne "\r\033[KInstance is now in running status (took ${ELAPSED}s)"
echo ""
echo ""

#------------------------------------------------------------------------------
# Phase 2: Waiting for cloud-init to finish package install (max 3 minutes)
#------------------------------------------------------------------------------
print_msg "$YELLOW" "Waiting cloud-init to finish installing required packages ... (this may take 3 - 5 minutes)"
printf '\n\n\n\n\n\n\n\n\033[8A'        # Print 8 blank lines to scroll up

# Start ntfy.sh JSON stream monitor
# Wait up to 180s for first message event, then continue until "Rebooting" or "Starting"
# Use --no-buffer to disable buffering
exec 3< <(curl -sN "https://ntfy.sh/${INSTANCE_LABEL}/json")

# Wait for first message event with 300s timeout
while IFS= read -t 300 -r line <&3; do
    event=$(echo "$line" | jq -r '.event // empty')
    [ "$event" = "message" ] && break
done || {
    exec 3<&-
    error_exit "Timeout: No cloud-init progress for 300 seconds" true
}

# Process first message and continue until termination keyword found
while true; do
    message=$(echo "$line" | jq -r '.message // empty')
    [ -n "$message" ] && {
        echo "$message" >&2
        echo "$message" | grep -qE "(Rebooting|Starting)" && break
    }

    IFS= read -r line <&3 || break
    [ "$(echo "$line" | jq -r '.event // empty')" = "message" ] || continue
done

exec 3<&-
log_to_file "INFO" "Cloud-init package installation completed"
echo ""

#------------------------------------------------------------------------------
# Phase 3: Wait for Instance to reboot (max 2 minutes)
#------------------------------------------------------------------------------
sleep 5
printf '\n\n\n\n\n\033[5A'
START_TIME=$(date +%s)

while true; do
    ELAPSED=$(($(date +%s) - START_TIME))
    echo -ne "\r\033[K${YELLOW}Waiting for Instance to reboot... Elapsed: $([ $ELAPSED -ge 60 ] && echo "$((ELAPSED / 60))m $((ELAPSED % 60))s" || echo "${ELAPSED}s")${NC}"
    sleep 2
    nc -z -w 3 "${INSTANCE_IP}" 22 &>/dev/null && break
    [ $ELAPSED -ge 120 ] && error_exit "Instance failed to become accessible" true
done
REBOOT_TIME=$(($(date +%s) - START_TIME))
log_to_file "INFO" "Instance rebooted and SSH accessible in ${REBOOT_TIME}s"
echo ""
echo "Instance is now running status (took ${REBOOT_TIME}s)"
echo ""

#------------------------------------------------------------------------------
# Phase 4: Verify Containers are Running
#------------------------------------------------------------------------------

# Determine SSH key file for SSH access
if [ -n "${NEW_KEY_PATH:-}" ]; then
    SSH_KEY_FILE="$NEW_KEY_PATH"
else
    SSH_KEY_FILE="${SSH_KEYS[$((key_choice-1))]%.pub}"
fi

# Setup SSH command with options to suppress warnings
SSH_CMD="ssh -i $SSH_KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes"

# Verify containers are running
printf '\n\n\n\n\n\033[5A'        # Print 5 blank lines to scroll up
print_msg "$YELLOW" "Waiting for containers to start..."
CONTAINER_CHECK=$($SSH_CMD "root@${INSTANCE_IP}" "docker ps --format '{{.Names}}' 2>/dev/null" || echo "")

if echo "$CONTAINER_CHECK" | grep -q "vllm" && echo "$CONTAINER_CHECK" | grep -q "open-webui"; then
    log_to_file "INFO" "Docker containers verified: vLLM and Open-WebUI running"
    echo "Both vLLM and Open-WebUI containers are running"
else
    log_to_file "WARN" "Container check incomplete: $CONTAINER_CHECK"
    warn "Some containers may still be starting. Check manually with: docker ps"
fi
echo ""

printf '\n\n\n\n\n\033[5A'
START_TIME=$(date +%s)

while true; do
    ELAPSED=$(($(date +%s) - START_TIME))
    if [ "$($SSH_CMD "root@${INSTANCE_IP}" "curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/health 2>/dev/null" || echo "000")" = "200" ]; then
        log_to_file "INFO" "Open-WebUI health check passed in ${ELAPSED}s"
        echo ""
        echo "Open-WebUI is ready (took ${ELAPSED}s)"
        echo ""
        break
    fi
    if [ $ELAPSED -ge 30 ]; then
        log_to_file "WARN" "Open-WebUI health check timeout after ${ELAPSED}s"
        warn "Timeout waiting for Open-WebUI health check. It may still be starting up."
        echo ""
        break
    fi
    echo -ne "\r\033[K${YELLOW}Waiting for Open-WebUI to be ready... Elapsed: $([ $ELAPSED -ge 60 ] && echo "$((ELAPSED / 60))m $((ELAPSED % 60))s" || echo "${ELAPSED}s")${NC}"
    sleep 2
done

printf '\n\n\n\n\n\033[5A'
START_TIME=$(date +%s)

while true; do
    ELAPSED=$(($(date +%s) - START_TIME))
    if $SSH_CMD "root@${INSTANCE_IP}" "curl -s http://localhost:8000/v1/models 2>/dev/null" | grep -q '"id":"unsloth/gpt-oss-20b"'; then
        log_to_file "INFO" "vLLM model loaded successfully in ${ELAPSED}s"
        echo ""
        echo "vLLM model is loaded and ready (took ${ELAPSED}s)"
        echo ""
        break
    fi
    if [ $ELAPSED -ge 600 ]; then
        log_to_file "WARN" "vLLM model load timeout after ${ELAPSED}s"
        warn "Timeout waiting for vLLM model to load. Model may still be downloading."
        echo ""
        break
    fi
    echo -ne "\r\033[K${YELLOW}Waiting for vLLM to download gpt-oss model... Elapsed: $([ $ELAPSED -ge 60 ] && echo "$((ELAPSED / 60))m $((ELAPSED % 60))s" || echo "${ELAPSED}s") - ( This make takes 2-3 minutes )${NC}"
    sleep 2
done

#==============================================================================
# Show Access URL
#==============================================================================
print_msg "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_msg "$BOLD" " 🎉 Setup Completed !!"
print_msg "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
print_msg "$BOLD$GREEN" "✅ Your AI LLM instance is now ready !!"
echo ""
print_msg "$CYAN" "📊 Instance Details:"
echo "   Instance ID:    $INSTANCE_ID"
echo "   Instance Label: $INSTANCE_LABEL"
echo "   IP Address:     $INSTANCE_IP"
echo "   Region:         $SELECTED_REGION"
echo "   Instance Type:  $SELECTED_TYPE"
echo ""
print_msg "$CYAN" "🔐 Access Credentials:"
if [ -n "${NEW_KEY_PATH:-}" ]; then
    echo "   SSH:         ssh -i ${NEW_KEY_PATH} root@${INSTANCE_IP}"
    echo "   SSH Key:     ${NEW_KEY_PATH}"
else
    echo "   SSH:         ssh root@${INSTANCE_IP}"
fi
echo "   Password:    ${INSTANCE_PASSWORD}"
echo ""
print_msg "$CYAN" "📋 Execution Log:"
echo "   Log file:       $LOG_FILE"
echo "   Instance Data:  $INSTANCE_FILE"
echo ""
print_msg "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
print_msg "$YELLOW" "💡 Next Steps:"
printf "   1. 🌐 Access Open-WebUI: ${CYAN}http://${INSTANCE_IP}:3000${NC}\n"
echo "   2. Create admin user account (your account data is stored only on your instance)"
echo "   3. Start chatting with the model running on your GPU instance !!"
echo ""
print_msg "$YELLOW" "📁 Check AI Stack Configuration:"
printf "   Docker Compose: ${CYAN}/opt/ai-quickstart-llm/docker-compose.yml${NC}\n"
echo "   Services: vLLM (port 8000) + OpenWebUI (port 3000)"
echo ""
echo ""
echo "🚀 Enjoy your AI Quickstart LLM on Akamai Cloud !!"
echo ""
echo ""
log_to_file "INFO" "Deployment completed successfully"
log_to_file "INFO" "Instance URL: http://${INSTANCE_IP}:3000"
