#!/usr/bin/env bash
export LC_NUMERIC=C

#==============================================================================
# quickstart_tools.sh - Shared utilities for AI Quickstart projects
#
# A consolidated library of reusable functions for Akamai Cloud (Linode)
# AI quickstart deployments.
#
# Usage:
#   # Local sourcing
#   source "${SCRIPT_DIR}/script/quickstart_tools.sh"
#
#   # Remote sourcing
#   source <(curl -fsSL https://raw.githubusercontent.com/linode/ai-quickstart-tools/main/quickstart_tools.sh)
#
# Repository: https://github.com/linode/ai-quickstart-tools
#==============================================================================

#==============================================================================
# GUARD: Prevent double-sourcing
#==============================================================================
[ -n "${_QS_TOOLS_LOADED:-}" ] && return 0
readonly _QS_TOOLS_LOADED=1

#==============================================================================
# SECTION 1: Constants & Colors
#==============================================================================

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# API Constants
readonly API_BASE="https://api.linode.com/v4"
readonly OAUTH_CLIENT_ID="5823b4627e45411d18e9"
readonly OAUTH_LOGIN_URL="https://login.linode.com/oauth/authorize"

#==============================================================================
# SECTION 2: Embedded Assets (Logo)
#==============================================================================

# Return Akamai ASCII logo
get_akamai_logo() {
    cat <<'EOF'
    ___    __                         _
   /   |  / /______ _____ ___  ____ _(_)
  / /| | / //_/ __ `/ __ `__ \/ __ `/ /
 / ___ |/ ,< / /_/ / / / / / / /_/ / /
/_/  |_/_/|_|\__,_/_/ /_/ /_/\__,_/_/
             ____      ____                                  ________                __
            /  _/___  / __/__  ________  ____  ________     / ____/ /___  __  ______/ /
            / // __ \/ /_/ _ \/ ___/ _ \/ __ \/ ___/ _ \   / /   / / __ \/ / / / __  /
          _/ // / / / __/  __/ /  /  __/ / / / /__/  __/  / /___/ / /_/ / /_/ / /_/ /
         /___/_/ /_/_/  \___/_/   \___/_/ /_/\___/\___/   \____/_/\____/\__,_/\__,_/

EOF
}

# Show Akamai banner
# Usage: show_banner
show_banner() {
    clear
    get_akamai_logo
    echo ""
}

#==============================================================================
# SECTION 3: Output/Logging Functions (Public)
#==============================================================================

# Log to file (strips color codes)
# Usage: log_to_file <level> <message>
# Requires LOG_FILE to be set
log_to_file() {
    [ -z "${LOG_FILE:-}" ] && return 0
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local level="$1"
    shift
    # Strip ANSI color codes and log
    echo "[$timestamp] [$level] $*" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
}

# Print colored message
# Usage: print_msg <color> <message>
print_msg() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# Print progress message (overwrites current line)
# Usage: progress <color> <message>
progress() {
    local color="$1"
    shift
    echo -en "\r\033[K${color}$*${NC}"
}

# Add bottom spacing
# Usage: scroll_up <bottom_spacing>
scroll_up() {
    local bottom_spacing="${1:-5}"
    if [ "$bottom_spacing" -gt 0 ]; then
        local j
        for j in $(seq 1 "$bottom_spacing"); do
            printf '\n' >&2
        done
        printf '\033[%dA' "$bottom_spacing" >&2
    fi
}

# Print error and exit
# Usage: error_exit <message>
error_exit() {
    local message="$1"
    print_msg "$RED" "❌ ERROR: $message"
    log_to_file "ERROR" "$message"
    exit 1
}

# Print success message
# Usage: success <message>
success() {
    print_msg "$GREEN" "✅ $*"
}

# Print info message
# Usage: info <message>
info() {
    print_msg "$CYAN" "ℹ️  $*"
}

# Print warning message
# Usage: warn <message>
warn() {
    print_msg "$YELLOW" "⚠️  $*"
}

# Print step header
# Usage: show_step <message>
show_step() {
    echo "------------------------------------------------------"
    print_msg "$BOLD" "$*"
    echo "------------------------------------------------------"
    echo ""
}

#==============================================================================
# SECTION 4: Utility Functions (Public)
#==============================================================================

# Cross-platform command detection
# Usage: check_command <command>
# Returns: 0 if found, 1 if not found
check_command() {
    local cmd="$1"
    if type -p "$cmd" &> /dev/null || type -p "${cmd}.exe" &> /dev/null || \
       which "$cmd" &> /dev/null || which "${cmd}.exe" &> /dev/null || \
       command -v "$cmd" &> /dev/null || command -v "${cmd}.exe" &> /dev/null; then
        return 0
    fi
    return 1
}

# Ensure jq is available (auto-install if missing)
ensure_jq() {
    check_command jq && jq --version &>/dev/null && return 0
    echo "jq not found. Attempting to install..." >&2
    local jq_base="https://github.com/jqlang/jq/releases/download/jq-1.8.1"

    # Windows Git Bash
    if [[ "$OSTYPE" == "msys" || -n "${MSYSTEM:-}" ]]; then
        curl -fsSL -o "/usr/bin/jq.exe" "$jq_base/jq-windows-amd64.exe" 2>/dev/null && chmod +x /usr/bin/jq.exe && jq --version &>/dev/null && return 0
        echo "Failed. Run: curl -L -o /usr/bin/jq.exe $jq_base/jq-windows-amd64.exe" >&2 && return 1
    fi
    # macOS - try brew first, then download binary
    if [[ "$OSTYPE" == "darwin"* ]]; then
        command -v brew &>/dev/null && brew install -q jq &>/dev/null && jq --version &>/dev/null && return 0
        local arch="amd64" && [[ "$(uname -m)" == "arm64" ]] && arch="arm64"
        curl -fsSL -o "/usr/local/bin/jq" "$jq_base/jq-macos-$arch" 2>/dev/null && chmod +x /usr/local/bin/jq && jq --version &>/dev/null && return 0
        echo "Failed. Run: sudo curl -L -o /usr/local/bin/jq $jq_base/jq-macos-$arch && sudo chmod +x /usr/local/bin/jq" >&2 && return 1
    fi
    # Linux - apt/dnf/yum
    command -v apt &>/dev/null && sudo apt-get install -y -qq jq &>/dev/null && jq --version &>/dev/null && return 0
    command -v dnf &>/dev/null && sudo dnf install -y -q jq &>/dev/null && jq --version &>/dev/null && return 0
    command -v yum &>/dev/null && sudo yum install -y -q jq &>/dev/null && jq --version &>/dev/null && return 0

    echo "Could not auto install jq. Please install manually." >&2 && return 1
}

#==============================================================================
# SECTION 5: Interactive Selection (Public)
#==============================================================================

# Interactive menu selection with default support
# Usage: ask_selection <prompt> <options_array_name> <default_index> <index_var> [default_label] [bottom_spacing]
ask_selection() {
    local prompt_text="$1"
    local options_array_name="$2"
    local default_index="${3:-}"
    local index_var_name="$4"
    local default_label="${5:-(default)}"
    local bottom_spacing="${6:-5}"

    # Get array length using eval (compatible with bash 3.2+)
    local array_length
    eval "array_length=\${#${options_array_name}[@]}"

    # Validate that array is not empty
    if [ "$array_length" -eq 0 ]; then
        echo -e "${RED}Error: Options array is empty${NC}" >&2
        return 1
    fi

    # Validate default index
    if [ -n "$default_index" ] && [ "$default_index" != "0" ]; then
        if ! [[ "$default_index" =~ ^[0-9]+$ ]] || [ "$default_index" -lt 1 ] || [ "$default_index" -gt "$array_length" ]; then
            echo -e "${RED}Error: Invalid default index: $default_index (must be 1-${array_length})${NC}" >&2
            return 1
        fi
    else
        default_index=""
    fi

    # Display options
    echo "" >&2
    local i
    for i in $(seq 0 $((array_length - 1))); do
        local display_num=$((i + 1))
        local option
        eval "option=\"\${${options_array_name}[$i]}\""

        if [ -n "$default_index" ] && [ "$display_num" -eq "$default_index" ]; then
            echo -e "  ${CYAN}${display_num}.${NC} ${YELLOW}${option}${NC} ${default_label}" >&2
        else
            echo -e "  ${CYAN}${display_num}.${NC} ${option}" >&2
        fi
    done

    echo "" >&2

    # Add bottom spacing if requested
    if [ "$bottom_spacing" -gt 0 ]; then
        local j
        for j in $(seq 1 "$bottom_spacing"); do
            printf '\n' >&2
        done
        printf '\033[%dA' "$bottom_spacing" >&2
    fi

    # Prompt for selection
    local selection
    while true; do
        if [ -n "$default_index" ]; then
            read -r -p "$(echo -e "${YELLOW}${prompt_text} [default: ${default_index}]:${NC}")" selection </dev/tty
        else
            read -r -p "$(echo -e "${YELLOW}${prompt_text}:${NC}")" selection </dev/tty
        fi

        # Use default if empty input and default is set
        if [ -z "$selection" ] && [ -n "$default_index" ]; then
            selection="$default_index"
        fi

        # Validate input is a number
        if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid input. Please enter a number between 1 and ${array_length}.${NC}" >&2
            continue
        fi

        # Validate input is in range
        if [ "$selection" -lt 1 ] || [ "$selection" -gt "$array_length" ]; then
            echo -e "${RED}Invalid selection. Please enter a number between 1 and ${array_length}.${NC}" >&2
            continue
        fi

        break
    done

    # Store result in caller's variable (1-based index)
    eval "${index_var_name}='${selection}'"

    return 0
}

# Interactive text input with validation
# Usage: ask_input <prompt> <default_value> <validation_func> <error_msg> <result_var> [bottom_spacing]
# Parameters:
#   prompt          - Prompt text to display
#   default_value   - Default value (can be empty)
#   validation_func - Name of validation function (must return 0 for valid, 1 for invalid)
#   error_msg       - Error message to show on validation failure
#   result_var      - Name of variable to store the result
#   bottom_spacing  - Number of blank lines to add below prompt (default: 5)
# Example:
#   ask_input "Enter instance label" "my-instance" "validate_instance_label" "Invalid label format" label_result
ask_input() {
    local prompt_text="$1"
    local default_value="${2:-}"
    local validation_func="$3"
    local error_msg="$4"
    local result_var="$5"
    local bottom_spacing="${6:-5}"

    # Add bottom spacing if requested
    if [ "$bottom_spacing" -gt 0 ]; then
        local j
        for j in $(seq 1 "$bottom_spacing"); do
            printf '\n' >&2
        done
        printf '\033[%dA' "$bottom_spacing" >&2
    fi

    local user_input
    while true; do
        if [ -n "$default_value" ]; then
            read -r -p "$(echo -e "${YELLOW}${prompt_text} ${NC}[default: ${default_value}]: ")" user_input </dev/tty
        else
            read -r -p "$(echo -e "${YELLOW}${prompt_text}:${NC} ")" user_input </dev/tty
        fi

        # Use default if empty input and default is set
        if [ -z "$user_input" ] && [ -n "$default_value" ]; then
            user_input="$default_value"
        fi

        # Skip validation if no validation function provided
        if [ -z "$validation_func" ]; then
            break
        fi

        # Run validation function
        if "$validation_func" "$user_input" > /dev/null 2>&1; then
            break
        else
            print_msg "$RED" "$error_msg"
        fi
    done

    # Store result in caller's variable
    eval "${result_var}='${user_input}'"

    return 0
}

# Interactive password input with confirmation and auto-generation
# Usage: ask_password <result_var> [bottom_spacing]
# Parameters:
#   result_var      - Name of variable to store the result
#   bottom_spacing  - Number of blank lines to add below prompt (default: 5)
# Example:
#   ask_password INSTANCE_PASSWORD
ask_password() {
    local result_var="$1"
    local bottom_spacing="${2:-5}"

    # Add bottom spacing if requested
    if [ "$bottom_spacing" -gt 0 ]; then
        local j
        for j in $(seq 1 "$bottom_spacing"); do
            printf '\n' >&2
        done
        printf '\033[%dA' "$bottom_spacing" >&2
    fi

    local user_password
    while true; do
        read -s -p "$(echo -e ${YELLOW}Enter root password ${NC}[empty to auto-generate]: )" user_password
        echo ""

        if [ -z "$user_password" ]; then
            local generated_password
            generated_password=$(generate_root_password)
            [ -z "$generated_password" ] || [ ${#generated_password} -lt 10 ] && error_exit "Failed to generate password"
            log_to_file "INFO" "Password auto-generated: $generated_password"
            eval "${result_var}='${generated_password}'"
            echo "Password Auto-generated." && break
        fi

        validate_root_password "$user_password" || { warn "Password does not meet requirements. Please try again."; continue; }
        read -s -p "$(echo -e ${YELLOW}Confirm password:${NC} )" user_password_confirm
        echo ""
        if [ "$user_password" = "$user_password_confirm" ]; then
            eval "${result_var}='${user_password}'"
            log_to_file "INFO" "User typed password: *************"
            echo "Password accepted"
            break
        fi
        warn "Passwords do not match. Please try again."
    done
}

#==============================================================================
# SECTION 6: Internal Helper Functions (Private - prefixed with _)
#==============================================================================

#------------------------------------------------------------------------------
# Authentication helpers
#------------------------------------------------------------------------------

# Find linode-cli executable
_find_linode_cli() {
    # Check if in PATH
    if command -v linode-cli &> /dev/null; then
        command -v linode-cli
        return 0
    fi

    # Check common installation locations
    local locations=(
        "$HOME/.local/bin/linode-cli"
        "/usr/local/bin/linode-cli"
        "/usr/bin/linode-cli"
    )

    # Add Windows-specific locations
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" || "$OSTYPE" == "cygwin" ]]; then
        if [ -n "${APPDATA:-}" ]; then
            locations+=("$APPDATA/Python/Python311/Scripts/linode-cli.exe")
            locations+=("$APPDATA/Python/Python312/Scripts/linode-cli.exe")
            locations+=("$APPDATA/Python/Python313/Scripts/linode-cli.exe")
        fi
        if [ -n "${LOCALAPPDATA:-}" ]; then
            locations+=("$LOCALAPPDATA/Programs/Python/Python311/Scripts/linode-cli.exe")
            locations+=("$LOCALAPPDATA/Programs/Python/Python312/Scripts/linode-cli.exe")
            locations+=("$LOCALAPPDATA/Programs/Python/Python313/Scripts/linode-cli.exe")
        fi
        locations+=("/c/Python311/Scripts/linode-cli.exe")
        locations+=("/c/Python312/Scripts/linode-cli.exe")
        locations+=("/c/Python313/Scripts/linode-cli.exe")
    fi

    for loc in "${locations[@]}"; do
        if [ -x "$loc" ]; then
            echo "$loc"
            return 0
        fi
    done

    # Last resort: try via python -m
    if command -v python3 &> /dev/null; then
        if python3 -m linodecli --version &> /dev/null; then
            echo "python3 -m linodecli"
            return 0
        fi
    fi

    if command -v python &> /dev/null; then
        if python -m linodecli --version &> /dev/null; then
            echo "python -m linodecli"
            return 0
        fi
    fi

    return 1
}

# Find linode-cli config file
_find_config_file() {
    # Priority 1: Custom config path from environment
    if [ -n "${LINODE_CLI_CONFIG:-}" ]; then
        echo "$LINODE_CLI_CONFIG"
        return
    fi

    # Priority 2: Legacy location
    if [ -f "$HOME/.linode-cli" ]; then
        echo "$HOME/.linode-cli"
        return
    fi

    # Priority 3: Platform-specific config location
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" || "$OSTYPE" == "cygwin" ]]; then
        local win_config="${USERPROFILE:-$HOME}/.config/linode-cli"
        if [ -f "$win_config" ]; then
            echo "$win_config"
            return
        fi
        echo "$win_config"
        return
    fi

    # Priority 4: XDG config location
    local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
    if [ -f "$xdg_config/linode-cli" ]; then
        echo "$xdg_config/linode-cli"
        return
    fi

    echo "$xdg_config/linode-cli"
}

# Parse INI file value
_get_ini_value() {
    local file="$1"
    local section="$2"
    local key="$3"

    awk -F '=' -v section="[$section]" -v key="$key" '
        $0 == section { in_section=1; next }
        /^\[/ { in_section=0 }
        in_section {
            gsub(/^[ \t]+|[ \t]+$/, "", $1)
            if ($1 == key) {
                gsub(/^[ \t]+|[ \t]+$/, "", $2)
                print $2
                exit
            }
        }
    ' "$file"
}

# Run linode-cli (handles both direct executable and python -m)
_run_linode_cli() {
    local linode_cli="$1"
    shift
    if [[ "$linode_cli" == *"python"* ]]; then
        $linode_cli "$@"
    else
        "$linode_cli" "$@"
    fi
}

#------------------------------------------------------------------------------
# OAuth helpers
#------------------------------------------------------------------------------

# Check OAuth dependencies
_check_oauth_dependencies() {
    local missing=()

    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    local has_server=false
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" || "$OSTYPE" == "cygwin" ]]; then
        if command -v powershell.exe &> /dev/null || command -v pwsh.exe &> /dev/null; then
            has_server=true
        elif command -v python3 &> /dev/null; then
            has_server=true
        fi
    else
        if command -v nc &> /dev/null && nc -h 2>&1 | grep -q "\-l"; then
            has_server=true
        elif command -v python3 &> /dev/null; then
            has_server=true
        fi
    fi

    if [ "$has_server" = false ]; then
        if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" || "$OSTYPE" == "cygwin" ]]; then
            missing+=("PowerShell or Python 3")
        else
            missing+=("netcat or Python 3")
        fi
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}❌ Missing dependencies: ${missing[*]}${NC}" >&2
        return 1
    fi
    return 0
}

# Parse JSON (prefer jq, fallback to grep/sed)
_parse_json() {
    local json="$1"
    local key="$2"

    if command -v jq &> /dev/null; then
        echo "$json" | jq -r ".${key} // empty"
    else
        echo "$json" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*:.*"\(.*\)".*/\1/'
    fi
}

# Validate token against API
_validate_token() {
    local token="$1"
    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $token" \
        "${API_BASE}/profile" 2>&1)

    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        _parse_json "$body" "username"
        return 0
    else
        return 1
    fi
}

# Open URL in browser (cross-platform)
_open_browser() {
    local url="$1"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        open "$url" 2>/dev/null || true
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" || "$OSTYPE" == "cygwin" ]]; then
        start "$url" 2>/dev/null || cmd.exe /c start "$url" 2>/dev/null || true
    elif grep -qi microsoft /proc/version 2>/dev/null || grep -qi wsl /proc/version 2>/dev/null; then
        if command -v powershell.exe &> /dev/null; then
            local escaped_url="${url//\'/\'\'}"
            powershell.exe -NoProfile -Command "Start-Process '${escaped_url}'" 2>/dev/null || true
        elif command -v wslview &> /dev/null; then
            wslview "$url" 2>/dev/null || true
        elif command -v cmd.exe &> /dev/null; then
            cmd.exe /c "start \"\" \"$url\"" 2>/dev/null || true
        else
            return 1
        fi
    elif command -v xdg-open &> /dev/null; then
        xdg-open "$url" 2>/dev/null || true
    else
        return 1
    fi
}

# Find an available port
_find_available_port() {
    local port
    local port_list
    if command -v shuf &> /dev/null; then
        port_list=$(shuf -i 8000-9000 -n 20)
    else
        port_list=$(seq 8000 8050)
    fi

    for port in $port_list; do
        if ! nc -z localhost "$port" 2>/dev/null && ! netstat -an 2>/dev/null | grep -q ":${port} "; then
            echo "$port"
            return 0
        fi
    done
    return 1
}

# Create HTML landing page for OAuth callback
_create_landing_page() {
    local port="$1"
    cat <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Authentication Success</title>
    <meta charset="UTF-8">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
            text-align: center;
            padding: 50px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            border-radius: 8px;
            padding: 40px;
            max-width: 500px;
            margin: 0 auto;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h2 { color: #02b159; margin-bottom: 20px; }
        .success { font-size: 48px; margin-bottom: 10px; }
        .info { color: #666; margin-top: 20px; line-height: 1.6; }
        .countdown {
            font-size: 24px;
            font-weight: bold;
            color: #02b159;
            margin-top: 15px;
        }
        .hint {
            color: #999;
            font-size: 14px;
            margin-top: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="success">✓</div>
        <h2>Authentication Successful</h2>
        <p>Token has been sent to your terminal.</p>
        <p class="info">Return to your terminal to continue.</p>
        <div class="countdown" id="countdown">Closing in 5...</div>
        <p class="hint">Press Enter or Esc to close now</p>
    </div>
    <script>
        var r = new XMLHttpRequest();
        r.open('GET', 'http://localhost:PORT/token/' + window.location.hash.substr(1));
        r.send();
        var secondsLeft = 5;
        var countdownElement = document.getElementById('countdown');
        function updateCountdown() {
            countdownElement.textContent = 'Closing in ' + secondsLeft + '...';
        }
        function attemptClose() {
            countdownElement.textContent = 'Closing...';
            window.close();
            if (window.opener) {
                window.opener = null;
                window.close();
            }
            setTimeout(function() {
                countdownElement.innerHTML = '<span style="color: #ff6b6b;">Please close this tab manually (Ctrl+W / Cmd+W)</span>';
            }, 500);
        }
        var countdownInterval = setInterval(function() {
            secondsLeft--;
            if (secondsLeft > 0) {
                updateCountdown();
            } else {
                clearInterval(countdownInterval);
                attemptClose();
            }
        }, 1000);
        document.addEventListener('keydown', function(event) {
            if (event.key === 'Enter' || event.key === 'Escape') {
                clearInterval(countdownInterval);
                attemptClose();
            }
        });
        window.focus();
    </script>
</body>
</html>
EOF
}

# Start server using Python
_start_python_server() {
    local port="$1"
    local landing_page="$2"

    python3 - "$port" "$landing_page" <<'PYTHON_EOF'
import sys
import re
from http.server import HTTPServer, BaseHTTPRequestHandler

port = int(sys.argv[1])
landing_page = sys.argv[2]
token = None

class OAuthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global token
        if "token" in self.path:
            match = re.search(r"access_token=([^&\s]+)", self.path)
            if match:
                token = match.group(1)
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        self.wfile.write(landing_page.encode('utf-8'))
    def log_message(self, format, *args):
        pass

server = HTTPServer(("localhost", port), OAuthHandler)
while token is None:
    server.handle_request()
print(token)
PYTHON_EOF
}

# Start server using PowerShell (Windows only)
_start_powershell_server() {
    local port="$1"
    local landing_page="$2"
    local escaped_page="${landing_page//\'/\'\'}"
    local ps_cmd="powershell.exe"
    if command -v pwsh.exe &> /dev/null; then
        ps_cmd="pwsh.exe"
    fi

    "$ps_cmd" -Command "
        \$landingPage = '$escaped_page'
        \$listener = New-Object System.Net.HttpListener
        \$listener.Prefixes.Add('http://localhost:$port/')
        \$listener.Start()
        \$token = \$null
        while (\$token -eq \$null) {
            \$context = \$listener.GetContext()
            \$request = \$context.Request
            \$response = \$context.Response
            if (\$request.Url.PathAndQuery -match 'access_token=([^&]+)') {
                \$token = \$matches[1]
            }
            \$buffer = [System.Text.Encoding]::UTF8.GetBytes(\$landingPage)
            \$response.ContentLength64 = \$buffer.Length
            \$response.OutputStream.Write(\$buffer, 0, \$buffer.Length)
            \$response.OutputStream.Close()
        }
        \$listener.Stop()
        Write-Output \$token
    "
}

# Start server using netcat (Unix/macOS/Linux only)
_start_nc_server() {
    local port="$1"
    local landing_page="$2"
    local token=""

    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" || "$OSTYPE" == "cygwin" ]]; then
        return 1
    fi

    local fifo="/tmp/linode_oauth_$$"
    mkfifo "$fifo" || return 1
    trap "rm -f $fifo" EXIT

    while [ -z "$token" ]; do
        {
            read -r request_line
            request_path=$(echo "$request_line" | cut -d' ' -f2)
            while read -r header; do
                [ "$header" = $'\r' ] && break
            done
            if [[ "$request_path" =~ /token/.*access_token=([^&[:space:]]+) ]]; then
                token="${BASH_REMATCH[1]}"
            fi
            echo -e "HTTP/1.1 200 OK\r"
            echo -e "Content-Type: text/html\r"
            echo -e "Content-Length: ${#landing_page}\r"
            echo -e "\r"
            echo -e "$landing_page"
        } < "$fifo" | nc -l -p "$port" > "$fifo" 2>/dev/null || true
        [ -n "$token" ] && break
    done

    echo "$token"
}

# Start OAuth callback server (auto-selects best method)
_start_oauth_server() {
    local port="$1"
    local landing_page="$2"
    local oauth_url="$3"

    landing_page="${landing_page//PORT/$port}"
    _open_browser "$oauth_url" || echo -e "${YELLOW}Please open the URL manually${NC}" >&2

    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" || "$OSTYPE" == "cygwin" ]]; then
        if type -p powershell.exe &> /dev/null || type -p pwsh.exe &> /dev/null || \
           which powershell.exe &> /dev/null || which pwsh.exe &> /dev/null || \
           [[ -f /c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe ]]; then
            _start_powershell_server "$port" "$landing_page"
        elif type -p python3 &> /dev/null || type -p python.exe &> /dev/null || \
             which python3 &> /dev/null || which python.exe &> /dev/null; then
            _start_python_server "$port" "$landing_page"
        else
            echo -e "${RED}Neither PowerShell nor Python 3 is available${NC}" >&2
            return 1
        fi
    else
        if command -v nc &> /dev/null && nc -h 2>&1 | grep -q "\-l"; then
            _start_nc_server "$port" "$landing_page"
        elif command -v python3 &> /dev/null; then
            _start_python_server "$port" "$landing_page"
        else
            echo -e "${RED}Neither netcat nor Python 3 is available${NC}" >&2
            return 1
        fi
    fi
}

#==============================================================================
# SECTION 7: Authentication Functions (Public)
#==============================================================================

# Get Linode API token (env → linode-cli → OAuth)
# Usage: get_linode_token [silent]
# Returns: Token string on stdout
get_linode_token() {
    local silent="${1:-false}"

    # Check environment variable first
    if [ -n "${LINODE_TOKEN:-}" ]; then
        echo "$LINODE_TOKEN"
        return 0
    fi

    # Try to get token from linode-cli config (silent, no messages)
    local token
    token=$(extract_linodecli_token true 2>/dev/null || true)
    if [ -n "$token" ]; then
        echo "$token"
        return 0
    fi

    # Fallback to OAuth (allow messages to stderr based on silent flag)
    token=$(extract_oauth_token "$silent" || true)
    if [ -n "$token" ]; then
        echo "$token"
        return 0
    fi

    return 1
}

# Extract token from linode-cli configuration
# Usage: extract_linodecli_token [silent]
# Returns: Token string on stdout
extract_linodecli_token() {
    local silent="${1:-false}"

    # Find linode-cli executable
    local linode_cli
    linode_cli=$(_find_linode_cli) || {
        if [ "$silent" = false ]; then
            echo "❌ linode-cli is not installed" >&2
        fi
        return 1
    }

    if [ "$silent" = false ]; then
        local version
        version=$(_run_linode_cli "$linode_cli" --version 2>&1 | head -n 1 | awk '{print $2}')
        echo "✅ linode-cli is installed ( ver: $version  path: $linode_cli )"
    fi

    # Check config file
    local config_file
    config_file=$(_find_config_file)
    if [ ! -f "$config_file" ]; then
        if [ "$silent" = false ]; then
            echo "❌ linode-cli is not configured (config file not found: $config_file)" >&2
        fi
        return 1
    fi

    # Verify configuration
    if ! timeout 5 _run_linode_cli "$linode_cli" profile view &> /dev/null; then
        if [ "$silent" = false ]; then
            echo "❌ linode-cli configuration is invalid or incomplete" >&2
        fi
        return 1
    fi

    # Check environment variable
    if [ -n "${LINODE_CLI_TOKEN:-}" ]; then
        if [ "$silent" = false ]; then
            echo "✅ linode-cli is configured"
            echo "Token:${LINODE_CLI_TOKEN}"
        else
            echo "${LINODE_CLI_TOKEN}"
        fi
        return 0
    fi

    # Get default user
    local username
    username=$(_get_ini_value "$config_file" "DEFAULT" "default-user")
    if [ -z "$username" ]; then
        if [ "$silent" = false ]; then
            echo "❌ No default user found in config" >&2
        fi
        return 1
    fi

    if [ "$silent" = false ]; then
        echo "✅ linode-cli is configured ( user : $username )"
    fi

    # Extract token
    local token
    token=$(_get_ini_value "$config_file" "$username" "token")
    if [ -z "$token" ]; then
        if [ "$silent" = false ]; then
            echo "❌ No token found for user '$username'" >&2
        fi
        return 1
    fi

    if [ "$silent" = false ]; then
        echo "Token:${token}"
    else
        echo "${token}"
    fi
}

# Extract token via OAuth flow
# Usage: extract_oauth_token [silent]
# Returns: Token string on stdout
extract_oauth_token() {
    local silent="${1:-false}"

    _check_oauth_dependencies || return 1

    if [ "$silent" = false ]; then
        echo -e "Starting Linode OAuth authentication..." >&2
    fi

    local port
    port=$(_find_available_port)
    if [ -z "$port" ]; then
        echo -e "${RED}Could not find an available port${NC}" >&2
        return 1
    fi

    local landing_page
    landing_page=$(_create_landing_page "$port")
    local oauth_url="${OAUTH_LOGIN_URL}?client_id=${OAUTH_CLIENT_ID}&response_type=token&scopes=*&redirect_uri=http://localhost:${port}"

    if [ "$silent" = false ]; then
        echo "" >&2
        echo -e "${GREEN}Opening browser. Please login with your Linode credential.${NC}" >&2
        echo "" >&2
        sleep 3
        echo -e "If the browser doesn't open automatically, visit:" >&2
        echo "" >&2
        echo "$oauth_url" >&2
        echo "" >&2
        echo -e "Waiting for OAuth callback..." >&2
    fi

    local token
    token=$(_start_oauth_server "$port" "$landing_page" "$oauth_url")

    if [ -z "$token" ]; then
        echo -e "${RED}Failed to receive OAuth token${NC}" >&2
        return 1
    fi

    if [ "$silent" = false ]; then
        echo -e "OAuth callback received" >&2
        echo -e "Validating token..." >&2
    fi

    local username
    if ! username=$(_validate_token "$token"); then
        echo -e "${RED}Token validation failed${NC}" >&2
        return 1
    fi

    if [ -z "$username" ]; then
        echo -e "${RED}Could not get username${NC}" >&2
        return 1
    fi

    if [ "$silent" = false ]; then
        echo "" >&2
        echo -e "${GREEN}========================================${NC}" >&2
        echo -e "${GREEN}✅ Authentication Successful${NC}" >&2
        echo -e "${GREEN}========================================${NC}" >&2
        echo "" >&2
        echo -e "${YELLOW}⚠️  IMPORTANT:${NC}" >&2
        echo "  • This short term token expires in 2 hours" >&2
        echo "  • Token is NOT saved to disk & used only for this setup script" >&2
        echo "" >&2
        echo "User:$username" >&2
        echo "Token:$token" >&2
    fi

    echo "$token"
}

#==============================================================================
# SECTION 8: API Functions (Public)
#==============================================================================

# Make authenticated Linode API call
# Usage: linode_api_call <endpoint> <token> [method] [json_payload]
linode_api_call() {
    local endpoint="$1"
    local token="$2"
    local method="${3:-GET}"
    local payload="${4:-}"

    local curl_args=(
        -s
        -X "$method"
        -H "Authorization: Bearer ${token}"
        -H "Content-Type: application/json"
    )

    if [ -n "$payload" ]; then
        curl_args+=(-d "$payload")
    fi

    curl "${curl_args[@]}" "${API_BASE}${endpoint}"
}

# Get GPU availability data (returns JSON)
# Usage: get_gpu_availability [token]
# If token not provided, will attempt to get one
get_gpu_availability() {
    local token="${1:-}"

    if [ -z "$token" ]; then
        token=$(get_linode_token true) || {
            echo -e "${RED}❌ Failed to get API token${NC}" >&2
            return 1
        }
    fi

    local temp_dir="${TMPDIR:-/tmp}"

    # Fetch pages in parallel
    for page in 1 2 3 4; do
        linode_api_call "/regions/availability?page_size=500&page=${page}" "$token" > "${temp_dir}/avail_page_${page}.json" &
    done
    linode_api_call "/linode/types" "$token" > "${temp_dir}/types.json" &
    linode_api_call "/regions" "$token" > "${temp_dir}/regions.json" &
    wait

    # Verify temp files
    for file in "${temp_dir}/avail_page_"{1,2,3,4}".json" "${temp_dir}/types.json" "${temp_dir}/regions.json"; do
        if [ ! -f "$file" ]; then
            echo -e "${RED}❌ Failed to fetch data from API${NC}" >&2
            return 1
        fi
    done

    # Combine availability pages into temp file (avoids "Argument list too long" on Git Bash/Windows)
    jq -n -c '{data: [inputs.data[]] | unique}' "${temp_dir}/avail_page_"{1,2,3,4}".json" > "${temp_dir}/availability.json" || {
        echo -e "${RED}❌ Failed to process availability data${NC}" >&2
        return 1
    }

    # Extract RTX4000 types to temp file
    jq -c '
        [.data[] | select(.id | startswith("g2-gpu-rtx4000")) |
        {
            id: .id,
            label: .label,
            hourly: .price.hourly,
            monthly: .price.monthly,
            vcpus: .vcpus,
            memory: .memory,
            gpus: .gpus,
            sort_gpu: (.id | capture("a(?<gpu>[0-9]+)").gpu | tonumber),
            sort_size: (if (.id | endswith("-s")) then 1
                       elif (.id | endswith("-m")) then 2
                       elif (.id | endswith("-l")) then 3
                       elif (.id | endswith("-xl")) then 4
                       elif (.id | endswith("-hs")) then 5
                       else 9 end)
        }] | sort_by(.sort_gpu, .sort_size)
    ' "${temp_dir}/types.json" > "${temp_dir}/rtx4000_types.json"

    local rtx4000_types
    rtx4000_types=$(cat "${temp_dir}/rtx4000_types.json")

    if [ "$rtx4000_types" = "[]" ]; then
        rm -f "${temp_dir}/avail_page_"{1,2,3,4}".json" "${temp_dir}/types.json" "${temp_dir}/regions.json" "${temp_dir}/availability.json" "${temp_dir}/rtx4000_types.json"
        echo -e "${RED}❌ No RTX4000 instances found${NC}" >&2
        return 1
    fi

    # Output JSON using --slurpfile to read from files (avoids "Argument list too long" on Git Bash/Windows)
    jq -n -c \
        --slurpfile availability "${temp_dir}/availability.json" \
        --slurpfile regions "${temp_dir}/regions.json" \
        --slurpfile types "${temp_dir}/rtx4000_types.json" \
        '{
            instance_types: ($types[0] | map(del(.sort_gpu, .sort_size))),
            regions: ($regions[0].data | sort_by(.id) | map(
                . as $region |
                {
                    id: $region.id,
                    label: $region.label,
                    instance_types: [
                        $availability[0].data[] |
                        select(.region == $region.id and .plan != null and (.plan | startswith("g2-gpu-rtx4000")) and .available == true) |
                        .plan
                    ] | unique | sort
                }
            ) | map(select(.instance_types | length > 0)))
        }'

    # Clean up temp files
    rm -f "${temp_dir}/avail_page_"{1,2,3,4}".json" "${temp_dir}/types.json" "${temp_dir}/regions.json" "${temp_dir}/availability.json" "${temp_dir}/rtx4000_types.json"
}

# Get available regions from GPU data
# Usage: get_available_regions <gpu_data_json> <display_array_name> <data_array_name>
# Parameters:
#   gpu_data_json      - JSON from get_gpu_availability
#   display_array_name - Name of array to store formatted display strings (for ask_selection)
#   data_array_name    - Name of array to store raw data "region_id|region_label|instance_types"
# Example:
#   get_available_regions "$GPU_DATA" REGION_DISPLAY REGION_DATA
#   ask_selection "Select region" REGION_DISPLAY 1 sel_idx
#   IFS='|' read -r region_id region_label available_instance_types <<< "${REGION_DATA[$((sel_idx-1))]}"
get_available_regions() {
    local gpu_data="$1"
    local display_array_name="$2"
    local data_array_name="$3"

    if [ -z "$gpu_data" ]; then
        echo -e "${RED}Error: GPU data is required${NC}" >&2
        return 1
    fi

    if [ -z "$display_array_name" ] || [ -z "$data_array_name" ]; then
        echo -e "${RED}Error: display_array_name and data_array_name are required${NC}" >&2
        return 1
    fi

    # Clear the arrays
    eval "$display_array_name=()"
    eval "$data_array_name=()"

    # Parse regions and build arrays
    local raw_data
    raw_data=$(echo "$gpu_data" | jq -r '.regions[] | "\(.id)|\(.label)|\(.instance_types | join(","))"')

    while IFS= read -r line; do
        IFS='|' read -r region_id region_label types <<< "$line"
        # Format: "region_id (12 chars) region_label" for display
        local formatted_option
        printf -v formatted_option "%-12s %s" "$region_id" "$region_label"
        eval "$display_array_name+=(\"\$formatted_option\")"
        eval "$data_array_name+=(\"\$line\")"
    done <<< "$raw_data"
}

# Get GPU instance type details for selection menu
# Usage: get_gpu_details <gpu_data_json> <available_types_csv> <default_type> <display_array_name> <data_array_name> <default_index_var>
# Parameters:
#   gpu_data_json       - JSON from get_gpu_availability
#   available_types_csv - Comma-separated list of available instance types for the region
#   default_type        - Default instance type ID (e.g., "g2-gpu-rtx4000a1-s")
#   display_array_name  - Name of array to store formatted display strings (for ask_selection)
#   data_array_name     - Name of array to store raw JSON data for each type
#   default_index_var   - Name of variable to store the default index (1-based)
# Example:
#   get_gpu_details "$GPU_DATA" "$available_instance_types" "g2-gpu-rtx4000a1-s" TYPE_DISPLAY TYPE_DATA default_idx
#   ask_selection "Select instance type" TYPE_DISPLAY "$default_idx" sel_idx
#   selected_type=$(echo "${TYPE_DATA[$((sel_idx-1))]}" | jq -r '.id')
get_gpu_details() {
    local gpu_data="$1"
    local available_types="$2"
    local default_type="${3:-}"
    local display_array_name="$4"
    local data_array_name="$5"
    local default_index_var="$6"

    if [ -z "$gpu_data" ]; then
        echo -e "${RED}Error: GPU data is required${NC}" >&2
        return 1
    fi

    if [ -z "$display_array_name" ] || [ -z "$data_array_name" ] || [ -z "$default_index_var" ]; then
        echo -e "${RED}Error: display_array_name, data_array_name, and default_index_var are required${NC}" >&2
        return 1
    fi

    # Clear the arrays and default index
    eval "$display_array_name=()"
    eval "$data_array_name=()"
    eval "$default_index_var=''"

    # Process each instance type
    local idx=0
    while IFS= read -r type_data; do
        local type_id
        type_id=$(echo "$type_data" | jq -r '.id')

        # Skip if not in available types list
        echo "$available_types" | grep -q "$type_id" || continue

        # Store raw data (escape single quotes in JSON for eval)
        local escaped_data="${type_data//\'/\'\\\'\'}"
        eval "$data_array_name+=('$escaped_data')"

        # Format display string
        local id lbl vcpus mem hr mo
        IFS=$'\t' read -r id lbl vcpus mem hr mo < <(echo "$type_data" | jq -r '[.id, .label, .vcpus, (.memory/1024|floor), .hourly, .monthly] | @tsv')

        local formatted_option
        printf -v formatted_option "%-20s %-35s ${CYAN}%d vCPUs, %dGB RAM - \$%.2f/hr (\$%.1f/mo)${NC}" "$id" "$lbl" "$vcpus" "$mem" "$hr" "$mo"
        eval "$display_array_name+=(\"\$formatted_option\")"

        idx=$((idx + 1))

        # Set default index if this matches default_type
        if [ -n "$default_type" ] && [ "$id" = "$default_type" ]; then
            eval "$default_index_var=$idx"
        fi
    done < <(echo "$gpu_data" | jq -c '.instance_types[]')
}

# Create a Linode instance with cloud-init
# Usage: create_instance <token> <label> <region> <type> <image> <root_pass> <ssh_key> <user_data_base64>
# Returns: JSON response from API
create_instance() {
    local token="$1"
    local label="$2"
    local region="$3"
    local type="$4"
    local image="$5"
    local root_pass="$6"
    local ssh_key="$7"
    local user_data_base64="$8"

    local payload
    payload=$(jq -n \
        --arg label "$label" \
        --arg region "$region" \
        --arg type "$type" \
        --arg image "$image" \
        --arg pass "$root_pass" \
        --arg userdata "$user_data_base64" \
        --arg sshkey "$ssh_key" \
        '{
            label: $label,
            region: $region,
            type: $type,
            image: $image,
            root_pass: $pass,
            metadata: {user_data: $userdata},
            authorized_keys: [$sshkey],
            booted: true,
            backups_enabled: false,
            private_ip: false
        }')

    linode_api_call "/linode/instances" "$token" "POST" "$payload"
}

# Delete a Linode instance
# Usage: delete_instance <token> <instance_id>
delete_instance() {
    local token="$1"
    local instance_id="$2"

    linode_api_call "/linode/instances/${instance_id}" "$token" "DELETE"
}

#==============================================================================
# SECTION 9: Validation Functions (Public)
#==============================================================================

# Validate instance label format
# Usage: validate_instance_label <label>
# Returns: 0 if valid, 1 with error message if invalid
validate_instance_label() {
    local label="$1"
    if [[ ! "$label" =~ ^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?$ ]]; then
        echo "Label must start/end with alphanumeric, use only: a-z A-Z 0-9 _ - ."
        return 1
    fi
    if [[ "$label" =~ --|__|\.\. ]]; then
        echo "Label cannot contain consecutive -- __ or .."
        return 1
    fi
    return 0
}

# Validate root password requirements
# Usage: validate_root_password <password>
# Returns: 0 if valid, 1 if invalid
validate_root_password() {
    local pwd="$1"
    [[ ${#pwd} -ge 11 && "$pwd" =~ [A-Z] && "$pwd" =~ [a-z] && "$pwd" =~ [0-9] && "$pwd" =~ [^A-Za-z0-9] ]]
}

# Generate random root password
# Usage: generate_root_password
# Returns: 15-char password with upper, lower, numbers, special chars
generate_root_password() {
    local chars='A-Za-z0-9!@#$%^&*()_+-='
    LC_ALL=C tr -dc "$chars" < /dev/urandom | head -c 15 2>/dev/null || true
}

#==============================================================================
# SECTION 10: SSH Key (Public)
#==============================================================================

# Get SSH public keys from ~/.ssh directory
# Usage: get_ssh_keys <display_array_name> <path_array_name> [include_auto_generate]
# Parameters:
#   display_array_name   - Name of array to store formatted display strings (for ask_selection)
#   path_array_name      - Name of array to store full paths to key files
#   include_auto_generate - If "true", adds auto-generate option at end (default: true)
# Example:
#   get_ssh_keys SSH_DISPLAY SSH_PATHS
#   ask_selection "Select SSH key" SSH_DISPLAY "" key_choice
#   if [ "$key_choice" -le ${#SSH_PATHS[@]} ]; then
#       SSH_PUBLIC_KEY=$(cat "${SSH_PATHS[$((key_choice-1))]}")
#   else
#       # User selected auto-generate
#   fi
get_ssh_keys() {
    local display_array_name="$1"
    local path_array_name="$2"
    local include_auto_generate="${3:-true}"

    # Clear the arrays
    eval "$display_array_name=()"
    eval "$path_array_name=()"

    # Find SSH public keys
    local key_files=()
    while IFS= read -r key; do
        [ -n "$key" ] && key_files+=("$key")
    done < <(find "$HOME/.ssh" -maxdepth 1 -name "*.pub" -type f 2>/dev/null | sort)

    # Build display and path arrays
    for key_path in "${key_files[@]}"; do
        local key_basename key_preview formatted_option
        key_basename="$(basename "$key_path")"
        key_preview="$(head -c 60 "$key_path" 2>/dev/null || true)"
        printf -v formatted_option "%-30s %s..." "$key_basename" "$key_preview"
        eval "$display_array_name+=(\"\$formatted_option\")"
        eval "$path_array_name+=(\"\$key_path\")"
    done

    # Add auto-generate option if requested
    if [ "$include_auto_generate" = "true" ]; then
        eval "$display_array_name+=(\"\${YELLOW}Auto-generate new SSH key pair\${NC}\")"
    fi
}

# Generate new SSH key pair
# Usage: generate_ssh_key <key_path> [comment]
# Parameters:
#   key_path - Path for the new key (without .pub extension)
#   comment  - Optional comment for the key (default: "linode-quickstart")
# Returns: 0 on success, 1 on failure
# Outputs: Public key content on stdout
# Example:
#   NEW_KEY_PATH="$HOME/.ssh/linode-myinstance-$(date +%s)"
#   SSH_PUBLIC_KEY=$(generate_ssh_key "$NEW_KEY_PATH" "my-instance-key")
generate_ssh_key() {
    local key_path="$1"
    local comment="${2:-linode-quickstart}"

    # Generate key pair (Ed25519, no passphrase)
    if ! ssh-keygen -t ed25519 -f "$key_path" -N "" -C "$comment" > /dev/null 2>&1; then
        echo -e "${RED}❌ Failed to generate SSH key${NC}" >&2
        return 1
    fi

    # Set proper permissions
    chmod 600 "$key_path" 2>/dev/null || true
    chmod 644 "${key_path}.pub" 2>/dev/null || true

    # Output public key content
    cat "${key_path}.pub"
}

