#!/usr/bin/env bats

# Test suite for smart-ssh
# Run with: bats tests/test_smart_ssh.bats

setup() {
    # Source the script to test individual functions
    export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export SMART_SSH="$SCRIPT_DIR/smart-ssh"

    # Create temporary config directory for tests
    export TEST_CONFIG_DIR=$(mktemp -d)
    export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
    export CONFIG_DIR="$TEST_CONFIG_DIR/smart-ssh"
    export CONFIG_FILE="$CONFIG_DIR/config"

    # Set test environment variables
    export HOME_NETWORK="192.168.1.0/24"
    export SECURITY_KEY_PATH="/tmp/test_key"
    export NO_COLOR=1  # Disable color output for tests
}

teardown() {
    # Clean up temporary directory
    rm -rf "$TEST_CONFIG_DIR"
}

# Test: Script exists and is executable
@test "smart-ssh script exists and is executable" {
    [ -f "$SMART_SSH" ]
    [ -x "$SMART_SSH" ]
}

# Test: Help option
@test "smart-ssh --help shows usage information" {
    run "$SMART_SSH" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "--help" ]]
}

# Test: Invalid option (treated as SSH option, but no hostname → error)
@test "smart-ssh with invalid option shows error" {
    run "$SMART_SSH" --invalid-option
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Please specify a hostname" ]]
}

# Test: No hostname argument
@test "smart-ssh without hostname shows error" {
    run "$SMART_SSH"
    [ "$status" -eq 0 ]  # Shows usage
    [[ "$output" =~ "Usage:" ]]
}

# Test: Configuration file initialization
@test "smart-ssh --init-config creates config file" {
    run "$SMART_SSH" --init-config
    [ "$status" -eq 0 ]
    [ -f "$CONFIG_FILE" ]
    [[ "$output" =~ "Configuration file created" ]]
}

# Test: Configuration file content
@test "config file contains expected keys" {
    "$SMART_SSH" --init-config > /dev/null 2>&1
    [ -f "$CONFIG_FILE" ]
    grep -q "HOME_NETWORK=" "$CONFIG_FILE"
    grep -q "SECURITY_KEY_PATH=" "$CONFIG_FILE"
    grep -q "LOG_LEVEL=" "$CONFIG_FILE"
}

# Helper: source functions from smart-ssh via temp file (bash 3.2 compatible)
# Uses awk with brace-depth counting to correctly handle nested functions
# Usage: _source_fn func_name [func_name ...]
_source_fn() {
    local _tmp
    _tmp=$(mktemp)
    for _fn in "$@"; do
        awk -v fn="${_fn}" '
        $0 ~ "^" fn "\\(\\)" { found=1; depth=0 }
        found {
            print
            for (i=1; i<=length($0); i++) {
                c = substr($0, i, 1)
                if (c == "{") depth++
                if (c == "}") depth--
            }
            if (found && depth <= 0 && NR > 1 && $0 ~ /}/) { found=0 }
        }
        ' "$SMART_SSH" >> "$_tmp"
    done
    # shellcheck disable=SC1090
    source "$_tmp"
    # Verify function was extracted successfully
    for _fn in "$@"; do
        if ! declare -f "$_fn" >/dev/null 2>&1; then
            echo "ERROR: _source_fn failed to extract function: $_fn" >&2
            rm -f "$_tmp"
            return 1
        fi
    done
    rm -f "$_tmp"
}

# Test: IP address validation (helper function test)
@test "validate IP address format" {
    _source_fn validate_ip

    # Valid IPs
    run validate_ip "192.168.1.1"
    [ "$status" -eq 0 ]

    run validate_ip "10.0.0.1"
    [ "$status" -eq 0 ]

    # Invalid IPs
    run validate_ip "999.999.999.999"
    [ "$status" -eq 1 ]

    run validate_ip "192.168.1"
    [ "$status" -eq 1 ]

    run validate_ip "not-an-ip"
    [ "$status" -eq 1 ]
}

# Test: CIDR validation
@test "validate CIDR format" {
    _source_fn validate_ip print_error validate_cidr
    export COLOR_RED='' COLOR_RESET=''

    # Valid CIDR
    run validate_cidr "192.168.1.0/24" 2>&1
    [ "$status" -eq 0 ]

    run validate_cidr "10.0.0.0/8" 2>&1
    [ "$status" -eq 0 ]

    # Invalid CIDR - no mask
    run validate_cidr "192.168.1.0" 2>&1
    [ "$status" -eq 1 ]

    # Invalid CIDR - mask out of range
    run validate_cidr "192.168.1.0/33" 2>&1
    [ "$status" -eq 1 ]
}

# Test: IP to integer conversion
@test "convert IP to integer" {
    _source_fn ip_to_int

    result=$(ip_to_int "192.168.1.1")
    [ "$result" -eq 3232235777 ]

    result=$(ip_to_int "10.0.0.1")
    [ "$result" -eq 167772161 ]
}

# Test: Debug mode
@test "smart-ssh --debug shows debug information" {
    run "$SMART_SSH" --debug
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Debug Information" ]]
    [[ "$output" =~ "Configuration:" ]]
    [[ "$output" =~ "Network:" ]]
}

# Test: Environment variable override
@test "environment variable overrides config file" {
    # Create config file
    "$SMART_SSH" --init-config > /dev/null 2>&1

    # Override with environment variable
    export HOME_NETWORK="10.0.0.0/8"

    run "$SMART_SSH" --debug
    [[ "$output" =~ "10.0.0.0/8" ]]
}

# Test: Multiple home networks
@test "support multiple comma-separated home networks" {
    export HOME_NETWORK="192.168.1.0/24,10.0.0.0/8,172.16.0.0/12"

    run "$SMART_SSH" --debug
    [ "$status" -eq 0 ]
    [[ "$output" =~ "192.168.1.0/24,10.0.0.0/8,172.16.0.0/12" ]]
}

# Test: Dry-run mode with security key option
@test "dry-run mode shows command without executing" {
    # Use isolated HOME to avoid touching real ~/.ssh/config
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    printf "Host test-host\n    HostName example.com\n" > "$HOME/.ssh/config"

    # Create dummy security key
    touch "$SECURITY_KEY_PATH"

    run "$SMART_SSH" --dry-run --security-key test-host
    [ "$status" -eq 0 ]
    [[ "$output" =~ "DRY RUN" ]]
    [[ "$output" =~ "Would execute:" ]]
    # Cleanup handled by teardown (rm -rf TEST_CONFIG_DIR)
}

# Test: Configuration file overwrite protection
@test "init-config asks before overwriting existing file" {
    # Create initial config
    "$SMART_SSH" --init-config > /dev/null 2>&1

    # Try to create again (should ask for confirmation)
    run bash -c "echo 'n' | $SMART_SSH --init-config"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "already exists" ]]
}

# Test: Log level configuration
@test "log level can be configured" {
    export LOG_LEVEL="debug"

    run "$SMART_SSH" --debug
    [ "$status" -eq 0 ]
    [[ "$output" =~ "LOG_LEVEL: debug" ]]
}

# Test: Tailscale CGNAT IP range detection
@test "Tailscale CGNAT IP range (100.64.0.0/10) is detected" {
    _source_fn validate_ip print_error validate_cidr ip_to_int ip_in_cidr
    export COLOR_RED='' COLOR_RESET=''

    # Tailscale IPs (100.64.0.0/10 = 100.64.0.0 - 100.127.255.255)
    run ip_in_cidr "100.100.1.1" "100.64.0.0/10"
    [ "$status" -eq 0 ]

    run ip_in_cidr "100.64.0.1" "100.64.0.0/10"
    [ "$status" -eq 0 ]

    run ip_in_cidr "100.127.255.254" "100.64.0.0/10"
    [ "$status" -eq 0 ]

    # Non-Tailscale IPs
    run ip_in_cidr "192.168.1.1" "100.64.0.0/10"
    [ "$status" -eq 1 ]

    run ip_in_cidr "100.128.0.1" "100.64.0.0/10"
    [ "$status" -eq 1 ]

    run ip_in_cidr "10.0.0.1" "100.64.0.0/10"
    [ "$status" -eq 1 ]
}

# Test: TAILSCALE_AS_HOME shown in debug output
@test "debug output shows TAILSCALE_AS_HOME setting" {
    export TAILSCALE_AS_HOME="true"

    run "$SMART_SSH" --debug
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TAILSCALE_AS_HOME: true" ]]
}

# Test: TAILSCALE_AS_HOME can be disabled
@test "TAILSCALE_AS_HOME can be set to false" {
    export TAILSCALE_AS_HOME="false"

    run "$SMART_SSH" --debug
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TAILSCALE_AS_HOME: false" ]]
}

# Test: Config file contains TAILSCALE_AS_HOME
@test "config file contains TAILSCALE_AS_HOME key" {
    "$SMART_SSH" --init-config > /dev/null 2>&1
    [ -f "$CONFIG_FILE" ]
    grep -q "TAILSCALE_AS_HOME=" "$CONFIG_FILE"
}

# ============================================================
# OIDC Tests
# ============================================================

# Test: Config file contains OIDC keys
@test "config file contains OIDC keys" {
    "$SMART_SSH" --init-config > /dev/null 2>&1
    [ -f "$CONFIG_FILE" ]
    grep -q "OIDC_ENABLED=" "$CONFIG_FILE"
    grep -q "OIDC_ISSUER=" "$CONFIG_FILE"
    grep -q "OIDC_AUTH_MODE=" "$CONFIG_FILE"
}

# Test: OIDC settings shown in debug output
@test "OIDC settings shown in debug output" {
    run "$SMART_SSH" --debug
    [ "$status" -eq 0 ]
    [[ "$output" =~ "OIDC:" ]]
    [[ "$output" =~ "OIDC_ENABLED:" ]]
}

# Test: validate_oidc_urls() accepts https:// URLs
@test "validate_oidc_urls accepts https:// URLs" {
    _source_fn print_error log_error validate_oidc_urls
    export COLOR_RED='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3
    export OIDC_ISSUER="https://accounts.example.com"
    export OIDC_CA_URL="https://ca.example.com"

    validate_oidc_urls 2>/dev/null
    [ "$?" -eq 0 ]
}

# Test: validate_oidc_urls() rejects http:// URLs
@test "validate_oidc_urls rejects http:// URLs" {
    _source_fn print_error log_error validate_oidc_urls
    export COLOR_RED='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3
    export OIDC_ISSUER="http://accounts.example.com"
    export OIDC_CA_URL="https://ca.example.com"

    ret=0; validate_oidc_urls 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]
}

# Test: validate_oidc_urls() rejects empty OIDC_ISSUER
@test "validate_oidc_urls rejects empty OIDC_ISSUER" {
    _source_fn print_error log_error validate_oidc_urls
    export COLOR_RED='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3
    export OIDC_ISSUER=""
    export OIDC_CA_URL="https://ca.example.com"

    ret=0; validate_oidc_urls 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]
}

# Test: check_oidc_dependencies() returns 0 when jq and curl are available
@test "check_oidc_dependencies succeeds when jq and curl are available" {
    # Skip if jq or curl is not installed
    if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        skip "jq or curl not available"
    fi

    _source_fn print_error log_error check_oidc_dependencies
    export COLOR_RED='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3

    check_oidc_dependencies 2>/dev/null
    [ "$?" -eq 0 ]
}

# Test: should_use_oidc() - auto mode with sk key missing returns 0 (use OIDC)
@test "should_use_oidc: auto mode with sk key missing returns 0" {
    _source_fn should_use_oidc
    export FORCE_OIDC=false
    export OIDC_ENABLED=true
    export OIDC_AUTH_MODE=auto
    export SECURITY_KEY_PATH="$TEST_CONFIG_DIR/nonexistent_key"  # does not exist

    should_use_oidc
    [ "$?" -eq 0 ]
}

# Test: should_use_oidc() - auto mode with sk key present returns 1 (skip OIDC)
@test "should_use_oidc: auto mode with sk key present returns 1" {
    _source_fn should_use_oidc
    touch "$TEST_CONFIG_DIR/sk_key"
    export FORCE_OIDC=false
    export OIDC_ENABLED=true
    export OIDC_AUTH_MODE=auto
    export SECURITY_KEY_PATH="$TEST_CONFIG_DIR/sk_key"

    ret=0; should_use_oidc || ret=$?
    [ "$ret" -eq 1 ]
}

# Test: should_use_oidc() - prefer mode returns 0
@test "should_use_oidc: prefer mode returns 0" {
    _source_fn should_use_oidc
    export FORCE_OIDC=false
    export OIDC_ENABLED=true
    export OIDC_AUTH_MODE=prefer

    should_use_oidc
    [ "$?" -eq 0 ]
}

# Test: should_use_oidc() - only mode returns 0
@test "should_use_oidc: only mode returns 0" {
    _source_fn should_use_oidc
    export FORCE_OIDC=false
    export OIDC_ENABLED=true
    export OIDC_AUTH_MODE=only

    should_use_oidc
    [ "$?" -eq 0 ]
}

# Test: should_use_oidc() - disabled mode returns 1
@test "should_use_oidc: disabled mode returns 1" {
    _source_fn should_use_oidc
    export FORCE_OIDC=false
    export OIDC_ENABLED=true
    export OIDC_AUTH_MODE=disabled

    ret=0; should_use_oidc || ret=$?
    [ "$ret" -eq 1 ]
}

# Test: should_use_oidc() - OIDC_ENABLED=false returns 1
@test "should_use_oidc: OIDC_ENABLED=false returns 1" {
    _source_fn should_use_oidc
    export FORCE_OIDC=false
    export OIDC_ENABLED=false
    export OIDC_AUTH_MODE=prefer

    ret=0; should_use_oidc || ret=$?
    [ "$ret" -eq 1 ]
}

# Test: should_use_oidc() - FORCE_OIDC=true overrides OIDC_ENABLED=false
@test "should_use_oidc: FORCE_OIDC=true overrides OIDC_ENABLED=false" {
    _source_fn should_use_oidc
    export FORCE_OIDC=true
    export OIDC_ENABLED=false
    export OIDC_AUTH_MODE=disabled

    should_use_oidc
    [ "$?" -eq 0 ]
}

# Test: oidc_check_cached_cert() returns 1 when cert file is absent
@test "oidc_check_cached_cert returns 1 when cert file is absent" {
    _source_fn print_error print_debug log_error log_debug oidc_check_cached_cert
    export COLOR_RED='' COLOR_BLUE='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3
    export OIDC_CERT_DIR="$TEST_CONFIG_DIR/oidc-certs"
    mkdir -p "$OIDC_CERT_DIR"
    # Neither cert nor key exists

    ret=0; oidc_check_cached_cert 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]
}

# Test: oidc_check_cached_cert() returns 1 when key file is absent
@test "oidc_check_cached_cert returns 1 when key file is absent" {
    _source_fn print_error print_debug log_error log_debug oidc_check_cached_cert
    export COLOR_RED='' COLOR_BLUE='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3
    export OIDC_CERT_DIR="$TEST_CONFIG_DIR/oidc-certs"
    mkdir -p "$OIDC_CERT_DIR"
    # Create cert file but not key file
    touch "$OIDC_CERT_DIR/id_oidc-cert.pub"

    ret=0; oidc_check_cached_cert 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]
}

# Test: validate_oidc_urls() rejects empty OIDC_CA_URL
@test "validate_oidc_urls rejects empty OIDC_CA_URL" {
    _source_fn print_error log_error validate_oidc_urls
    export COLOR_RED='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3
    export OIDC_ISSUER="https://accounts.example.com"
    export OIDC_CA_URL=""

    ret=0; validate_oidc_urls 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]
}

# Test: validate_oidc_urls() rejects http:// OIDC_CA_URL
@test "validate_oidc_urls rejects http:// OIDC_CA_URL" {
    _source_fn print_error log_error validate_oidc_urls
    export COLOR_RED='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3
    export OIDC_ISSUER="https://accounts.example.com"
    export OIDC_CA_URL="http://ca.example.com"

    ret=0; validate_oidc_urls 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]
}

# Test: ensure_oidc_cert_dir() creates cert directory
@test "ensure_oidc_cert_dir creates cert directory" {
    _source_fn print_error print_warning print_debug log_error log_warn log_debug ensure_secure_dir ensure_oidc_cert_dir
    export COLOR_RED='' COLOR_YELLOW='' COLOR_BLUE='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3
    export HOME="$TEST_CONFIG_DIR"
    export OIDC_CERT_DIR="$TEST_CONFIG_DIR/.ssh/oidc-certs"

    ensure_oidc_cert_dir 2>/dev/null
    [ "$?" -eq 0 ]
    [ -d "$OIDC_CERT_DIR" ]
    # Verify directory permissions are 700 (portable across macOS/Linux)
    local perms
    if stat -c '%a' /dev/null >/dev/null 2>&1; then
        # GNU stat (Linux)
        perms=$(stat -c '%a' "$OIDC_CERT_DIR")
    else
        # BSD stat (macOS)
        perms=$(stat -f '%Lp' "$OIDC_CERT_DIR")
    fi
    [ "$perms" = "700" ]
}

# Test: ensure_oidc_cert_dir() rejects symlink in OIDC_CERT_DIR
@test "ensure_oidc_cert_dir rejects symlink" {
    _source_fn print_error print_warning print_debug log_error log_warn log_debug ensure_secure_dir ensure_oidc_cert_dir
    export COLOR_RED='' COLOR_YELLOW='' COLOR_BLUE='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$TEST_CONFIG_DIR/.ssh"
    # Create a symlink as OIDC_CERT_DIR target
    ln -s /tmp "$TEST_CONFIG_DIR/.ssh/oidc-certs"
    export OIDC_CERT_DIR="$TEST_CONFIG_DIR/.ssh/oidc-certs"

    ret=0; ensure_oidc_cert_dir 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]
}

# Test: ensure_oidc_cert_dir() rejects symlink on ~/.ssh itself
@test "ensure_oidc_cert_dir rejects symlink on ssh dir" {
    _source_fn print_error print_warning print_debug log_error log_warn log_debug ensure_secure_dir ensure_oidc_cert_dir
    export COLOR_RED='' COLOR_YELLOW='' COLOR_BLUE='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3
    export HOME="$TEST_CONFIG_DIR"
    # Create ~/.ssh as a symlink
    ln -s /tmp "$TEST_CONFIG_DIR/.ssh"
    export OIDC_CERT_DIR="$TEST_CONFIG_DIR/.ssh/oidc-certs"

    ret=0; ensure_oidc_cert_dir 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]
}

# Test: ensure_oidc_cert_dir() creates both ~/.ssh and cert dir
@test "ensure_oidc_cert_dir creates ssh dir and cert dir" {
    _source_fn print_error print_warning print_debug log_error log_warn log_debug ensure_secure_dir ensure_oidc_cert_dir
    export COLOR_RED='' COLOR_YELLOW='' COLOR_BLUE='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3
    export HOME="$TEST_CONFIG_DIR"
    export OIDC_CERT_DIR="$TEST_CONFIG_DIR/.ssh/oidc-certs"
    # Neither ~/.ssh nor cert dir exist

    ensure_oidc_cert_dir 2>/dev/null
    [ "$?" -eq 0 ]
    [ -d "$TEST_CONFIG_DIR/.ssh" ]
    [ -d "$OIDC_CERT_DIR" ]
}

# Test: --oidc with missing OIDC config shows error
@test "--oidc with missing OIDC config shows error" {
    run env OIDC_ISSUER="" OIDC_CA_URL="" \
        OIDC_CERT_DIR="$TEST_CONFIG_DIR/empty-oidc-certs" \
        "$SMART_SSH" --dry-run --oidc test-host
    [ "$status" -ne 0 ]
}

# ============================================================
# Version Tests
# ============================================================

# Test: --version flag
@test "smart-ssh --version shows version string" {
    run "$SMART_SSH" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ "smart-ssh " ]]
    # Version must be semver format
    [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

# ============================================================
# Input Sanitization Tests
# ============================================================

# Test: validate_ssh_hostname accepts valid hostnames
@test "validate_ssh_hostname accepts valid hostnames" {
    _source_fn print_error log_error validate_ssh_hostname
    export COLOR_RED='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3

    validate_ssh_hostname "example.com" 2>/dev/null
    [ "$?" -eq 0 ]

    validate_ssh_hostname "192.168.1.1" 2>/dev/null
    [ "$?" -eq 0 ]

    validate_ssh_hostname "my-host.local" 2>/dev/null
    [ "$?" -eq 0 ]

    validate_ssh_hostname "host:2222" 2>/dev/null
    [ "$?" -eq 0 ]

    validate_ssh_hostname "user%host" 2>/dev/null
    [ "$?" -eq 0 ]
}

# Test: validate_ssh_hostname rejects unsafe characters
@test "validate_ssh_hostname rejects unsafe characters" {
    _source_fn print_error log_error validate_ssh_hostname
    export COLOR_RED='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3

    # Wildcard
    ret=0; validate_ssh_hostname "host*" 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]

    # Space
    ret=0; validate_ssh_hostname "host name" 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]

    # Empty
    ret=0; validate_ssh_hostname "" 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]

    # Question mark
    ret=0; validate_ssh_hostname "host?" 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]
}

# Test: validate_oidc_cert_lifetime accepts valid values
@test "validate_oidc_cert_lifetime accepts valid values" {
    _source_fn print_error log_error validate_oidc_cert_lifetime
    export COLOR_RED='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3

    OIDC_CERT_LIFETIME="3600"
    validate_oidc_cert_lifetime 2>/dev/null
    [ "$?" -eq 0 ]

    OIDC_CERT_LIFETIME="86400"
    validate_oidc_cert_lifetime 2>/dev/null
    [ "$?" -eq 0 ]

    OIDC_CERT_LIFETIME="1"
    validate_oidc_cert_lifetime 2>/dev/null
    [ "$?" -eq 0 ]
}

# Test: validate_oidc_cert_lifetime rejects invalid values
@test "validate_oidc_cert_lifetime rejects invalid values" {
    _source_fn print_error log_error validate_oidc_cert_lifetime
    export COLOR_RED='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3

    # Zero
    OIDC_CERT_LIFETIME="0"
    ret=0; validate_oidc_cert_lifetime 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]

    # Over max
    OIDC_CERT_LIFETIME="86401"
    ret=0; validate_oidc_cert_lifetime 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]

    # Non-numeric
    OIDC_CERT_LIFETIME="abc"
    ret=0; validate_oidc_cert_lifetime 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]

    # Negative
    OIDC_CERT_LIFETIME="-1"
    ret=0; validate_oidc_cert_lifetime 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]
}

# ============================================================
# Tailscale whois Tests
# ============================================================

# Helper: create a temp script that sources functions and calls is_tailscale_host
# Usage: _create_ts_test_script <mock_dir> <hostname>
# The script sets PATH to mock_dir internally, so bash can find mock commands
_create_ts_test_script() {
    local mock_dir="$1"
    local test_hostname="$2"
    local _tmp
    _tmp=$(mktemp)

    # Set environment at top of script
    cat >> "$_tmp" <<HEADER
#!/bin/bash
export PATH="$mock_dir"
export COLOR_RED='' COLOR_BLUE='' COLOR_YELLOW='' COLOR_RESET=''
export CURRENT_LOG_LEVEL=0
HEADER

    # Extract all needed functions from smart-ssh
    for _fn in print_error print_warning print_debug log_error log_warn log_debug log_info validate_ip validate_cidr ip_to_int ip_in_cidr resolve_hostname is_tailscale_host; do
        awk -v fn="${_fn}" '
        $0 ~ "^" fn "\\(\\)" { found=1; depth=0 }
        found {
            print
            for (i=1; i<=length($0); i++) {
                c = substr($0, i, 1)
                if (c == "{") depth++
                if (c == "}") depth--
            }
            if (found && depth <= 0 && NR > 1 && $0 ~ /}/) { found=0 }
        }
        ' "$SMART_SSH" >> "$_tmp"
    done

    echo "is_tailscale_host \"$test_hostname\"" >> "$_tmp"
    echo "$_tmp"
}

# Test: is_tailscale_host falls back to heuristic when CLI not found
@test "is_tailscale_host: fallback to CGNAT heuristic when CLI absent" {
    local mock_dir
    mock_dir=$(mktemp -d "$TEST_CONFIG_DIR/ts_mock.XXXXXX")
    cat > "$mock_dir/ssh" <<'MOCK_SSH'
#!/bin/bash
echo "hostname 100.100.1.1"
MOCK_SSH
    chmod +x "$mock_dir/ssh"

    # Link common utilities needed by functions
    for cmd in grep awk cut head tr; do
        local cmd_path
        cmd_path=$(command -v "$cmd" 2>/dev/null) && ln -sf "$cmd_path" "$mock_dir/$cmd"
    done

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "test-ts-host")

    run bash "$test_script"
    [ "$status" -eq 0 ]
}

# Test: is_tailscale_host returns 1 for non-Tailscale host when CLI absent
@test "is_tailscale_host: non-CGNAT host returns 1 when CLI absent" {
    local mock_dir
    mock_dir=$(mktemp -d "$TEST_CONFIG_DIR/ts_mock.XXXXXX")
    cat > "$mock_dir/ssh" <<'MOCK_SSH'
#!/bin/bash
echo "hostname 203.0.113.1"
MOCK_SSH
    chmod +x "$mock_dir/ssh"
    for cmd in grep awk cut head tr; do
        local cmd_path
        cmd_path=$(command -v "$cmd" 2>/dev/null) && ln -sf "$cmd_path" "$mock_dir/$cmd"
    done

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "test-external-host")

    run bash "$test_script"
    [ "$status" -eq 1 ]
}

# Test: is_tailscale_host uses tailscale whois when CLI available and daemon running
@test "is_tailscale_host: uses tailscale whois when available" {
    command -v jq >/dev/null 2>&1 || skip "jq not available"

    local mock_dir
    mock_dir=$(mktemp -d "$TEST_CONFIG_DIR/ts_mock.XXXXXX")

    cat > "$mock_dir/ssh" <<'MOCK_SSH'
#!/bin/bash
echo "hostname myhost.example.com"
MOCK_SSH
    chmod +x "$mock_dir/ssh"

    cat > "$mock_dir/tailscale" <<'MOCK_TS'
#!/bin/bash
if [ "$1" = "status" ]; then
    exit 0
fi
if [ "$1" = "whois" ] && [ "$2" = "--json" ]; then
    echo '{"Node":{"ID":12345,"Name":"myhost"}}'
    exit 0
fi
exit 1
MOCK_TS
    chmod +x "$mock_dir/tailscale"

    for cmd in jq grep awk cut head tr; do
        local cmd_path
        cmd_path=$(command -v "$cmd" 2>/dev/null) && ln -sf "$cmd_path" "$mock_dir/$cmd"
    done

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "test-ts-host")

    run bash "$test_script"
    [ "$status" -eq 0 ]
}

# Test: is_tailscale_host falls back when daemon not running
@test "is_tailscale_host: fallback when daemon not running" {
    local mock_dir
    mock_dir=$(mktemp -d "$TEST_CONFIG_DIR/ts_mock.XXXXXX")

    cat > "$mock_dir/ssh" <<'MOCK_SSH'
#!/bin/bash
echo "hostname myhost.tail12345.ts.net"
MOCK_SSH
    chmod +x "$mock_dir/ssh"

    cat > "$mock_dir/tailscale" <<'MOCK_TS'
#!/bin/bash
if [ "$1" = "status" ]; then
    echo "failed to connect to local Tailscale daemon" >&2
    exit 1
fi
exit 1
MOCK_TS
    chmod +x "$mock_dir/tailscale"
    for cmd in grep awk cut head tr; do
        local cmd_path
        cmd_path=$(command -v "$cmd" 2>/dev/null) && ln -sf "$cmd_path" "$mock_dir/$cmd"
    done

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "test-ts-host")

    run bash "$test_script"
    [ "$status" -eq 0 ]
}

# Test: is_tailscale_host rejects non-tailscale host via whois
@test "is_tailscale_host: whois returns non-tailscale host" {
    local mock_dir
    mock_dir=$(mktemp -d "$TEST_CONFIG_DIR/ts_mock.XXXXXX")

    cat > "$mock_dir/ssh" <<'MOCK_SSH'
#!/bin/bash
echo "hostname 203.0.113.1"
MOCK_SSH
    chmod +x "$mock_dir/ssh"

    cat > "$mock_dir/tailscale" <<'MOCK_TS'
#!/bin/bash
if [ "$1" = "status" ]; then
    exit 0
fi
if [ "$1" = "whois" ]; then
    echo "not a Tailscale IP" >&2
    exit 1
fi
exit 1
MOCK_TS
    chmod +x "$mock_dir/tailscale"
    for cmd in grep awk cut head tr; do
        local cmd_path
        cmd_path=$(command -v "$cmd" 2>/dev/null) && ln -sf "$cmd_path" "$mock_dir/$cmd"
    done

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "test-external-host")

    run bash "$test_script"
    [ "$status" -eq 1 ]
}

# ============================================================
# get_log_level_number Tests
# ============================================================

# Test: get_log_level_number returns 0 for debug
@test "get_log_level_number returns 0 for debug" {
    _source_fn get_log_level_number
    export LOG_LEVEL_DEBUG=0
    export LOG_LEVEL_INFO=1
    export LOG_LEVEL_WARN=2
    export LOG_LEVEL_ERROR=3

    LOG_LEVEL="debug"
    result=$(get_log_level_number)
    [ "$result" -eq 0 ]
}

# Test: get_log_level_number returns 1 for info
@test "get_log_level_number returns 1 for info" {
    _source_fn get_log_level_number
    export LOG_LEVEL_DEBUG=0
    export LOG_LEVEL_INFO=1
    export LOG_LEVEL_WARN=2
    export LOG_LEVEL_ERROR=3

    LOG_LEVEL="info"
    result=$(get_log_level_number)
    [ "$result" -eq 1 ]
}

# Test: get_log_level_number returns 2 for warn
@test "get_log_level_number returns 2 for warn" {
    _source_fn get_log_level_number
    export LOG_LEVEL_DEBUG=0
    export LOG_LEVEL_INFO=1
    export LOG_LEVEL_WARN=2
    export LOG_LEVEL_ERROR=3

    LOG_LEVEL="warn"
    result=$(get_log_level_number)
    [ "$result" -eq 2 ]
}

# Test: get_log_level_number returns 3 for error
@test "get_log_level_number returns 3 for error" {
    _source_fn get_log_level_number
    export LOG_LEVEL_DEBUG=0
    export LOG_LEVEL_INFO=1
    export LOG_LEVEL_WARN=2
    export LOG_LEVEL_ERROR=3

    LOG_LEVEL="error"
    result=$(get_log_level_number)
    [ "$result" -eq 3 ]
}

# Test: get_log_level_number is case-insensitive (uppercase)
@test "get_log_level_number is case-insensitive for uppercase input" {
    _source_fn get_log_level_number
    export LOG_LEVEL_DEBUG=0
    export LOG_LEVEL_INFO=1
    export LOG_LEVEL_WARN=2
    export LOG_LEVEL_ERROR=3

    LOG_LEVEL="DEBUG"
    result=$(get_log_level_number)
    [ "$result" -eq 0 ]

    LOG_LEVEL="WARN"
    result=$(get_log_level_number)
    [ "$result" -eq 2 ]
}

# Test: get_log_level_number returns 1 for unknown level
@test "get_log_level_number returns 1 for unknown level" {
    _source_fn get_log_level_number
    export LOG_LEVEL_DEBUG=0
    export LOG_LEVEL_INFO=1
    export LOG_LEVEL_WARN=2
    export LOG_LEVEL_ERROR=3

    LOG_LEVEL="verbose"
    result=$(get_log_level_number)
    [ "$result" -eq 1 ]
}

# Test: get_log_level_number returns 1 for empty log level
@test "get_log_level_number returns 1 for empty log level" {
    _source_fn get_log_level_number
    export LOG_LEVEL_DEBUG=0
    export LOG_LEVEL_INFO=1
    export LOG_LEVEL_WARN=2
    export LOG_LEVEL_ERROR=3

    LOG_LEVEL=""
    result=$(get_log_level_number)
    [ "$result" -eq 1 ]
}

# ============================================================
# is_home_gateway_mac Tests
# ============================================================

# Test: is_home_gateway_mac matches single MAC address
@test "is_home_gateway_mac matches single MAC address" {
    _source_fn is_home_gateway_mac

    HOME_GATEWAY_MAC="aa:bb:cc:dd:ee:ff"
    run is_home_gateway_mac "aa:bb:cc:dd:ee:ff"
    [ "$status" -eq 0 ]
}

# Test: is_home_gateway_mac is case-insensitive
@test "is_home_gateway_mac is case-insensitive" {
    _source_fn is_home_gateway_mac

    HOME_GATEWAY_MAC="AA:BB:CC:DD:EE:FF"
    run is_home_gateway_mac "aa:bb:cc:dd:ee:ff"
    [ "$status" -eq 0 ]
}

# Test: is_home_gateway_mac matches from comma-separated list
@test "is_home_gateway_mac matches from comma-separated list" {
    _source_fn is_home_gateway_mac

    HOME_GATEWAY_MAC="11:22:33:44:55:66,aa:bb:cc:dd:ee:ff,77:88:99:00:aa:bb"
    run is_home_gateway_mac "aa:bb:cc:dd:ee:ff"
    [ "$status" -eq 0 ]
}

# Test: is_home_gateway_mac returns 1 for non-matching MAC
@test "is_home_gateway_mac returns 1 for non-matching MAC" {
    _source_fn is_home_gateway_mac

    HOME_GATEWAY_MAC="aa:bb:cc:dd:ee:ff"
    run is_home_gateway_mac "11:22:33:44:55:66"
    [ "$status" -eq 1 ]
}

# Test: is_home_gateway_mac returns 1 when current_mac is empty
@test "is_home_gateway_mac returns 1 when current_mac is empty" {
    _source_fn is_home_gateway_mac

    HOME_GATEWAY_MAC="aa:bb:cc:dd:ee:ff"
    run is_home_gateway_mac ""
    [ "$status" -eq 1 ]
}

# Test: is_home_gateway_mac returns 1 when HOME_GATEWAY_MAC is empty
@test "is_home_gateway_mac returns 1 when HOME_GATEWAY_MAC is empty" {
    _source_fn is_home_gateway_mac

    HOME_GATEWAY_MAC=""
    run is_home_gateway_mac "aa:bb:cc:dd:ee:ff"
    [ "$status" -eq 1 ]
}

# Test: is_home_gateway_mac handles whitespace around MACs in list
@test "is_home_gateway_mac handles whitespace around MACs in list" {
    _source_fn is_home_gateway_mac

    HOME_GATEWAY_MAC="11:22:33:44:55:66 , aa:bb:cc:dd:ee:ff"
    run is_home_gateway_mac "aa:bb:cc:dd:ee:ff"
    [ "$status" -eq 0 ]
}

# ============================================================
# is_home_network Tests
# ============================================================

# Test: is_home_network returns 0 for IP within home network
@test "is_home_network returns 0 for IP within home network" {
    _source_fn validate_ip print_error validate_cidr ip_to_int ip_in_cidr is_home_network
    export COLOR_RED='' COLOR_RESET=''

    HOME_NETWORK="192.168.1.0/24"
    run is_home_network "192.168.1.100"
    [ "$status" -eq 0 ]
}

# Test: is_home_network returns 1 for IP outside home network
@test "is_home_network returns 1 for IP outside home network" {
    _source_fn validate_ip print_error validate_cidr ip_to_int ip_in_cidr is_home_network
    export COLOR_RED='' COLOR_RESET=''

    HOME_NETWORK="192.168.1.0/24"
    run is_home_network "10.0.0.1"
    [ "$status" -eq 1 ]
}

# Test: is_home_network matches from comma-separated network list
@test "is_home_network matches from comma-separated network list" {
    _source_fn validate_ip print_error validate_cidr ip_to_int ip_in_cidr is_home_network
    export COLOR_RED='' COLOR_RESET=''

    HOME_NETWORK="192.168.1.0/24,10.0.0.0/8"
    run is_home_network "10.5.5.5"
    [ "$status" -eq 0 ]
}

# Test: is_home_network returns 1 for NOT_CONNECTED
@test "is_home_network returns 1 for NOT_CONNECTED" {
    _source_fn validate_ip print_error validate_cidr ip_to_int ip_in_cidr is_home_network
    export COLOR_RED='' COLOR_RESET=''

    HOME_NETWORK="192.168.1.0/24"
    run is_home_network "NOT_CONNECTED"
    [ "$status" -eq 1 ]
}

# Test: is_home_network returns 1 for empty IP
@test "is_home_network returns 1 for empty IP" {
    _source_fn validate_ip print_error validate_cidr ip_to_int ip_in_cidr is_home_network
    export COLOR_RED='' COLOR_RESET=''

    HOME_NETWORK="192.168.1.0/24"
    run is_home_network ""
    [ "$status" -eq 1 ]
}

# Test: is_home_network handles network ranges with spaces
@test "is_home_network handles network ranges with surrounding spaces" {
    _source_fn validate_ip print_error validate_cidr ip_to_int ip_in_cidr is_home_network
    export COLOR_RED='' COLOR_RESET=''

    HOME_NETWORK=" 192.168.1.0/24 , 10.0.0.0/8 "
    run is_home_network "192.168.1.50"
    [ "$status" -eq 0 ]
}

# ============================================================
# ensure_secure_dir Tests
# ============================================================

# Test: ensure_secure_dir creates directory with 700 permissions
@test "ensure_secure_dir creates directory with 700 permissions" {
    _source_fn print_error print_warning log_error log_warn ensure_secure_dir
    export COLOR_RED='' COLOR_YELLOW='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3

    local test_dir="$TEST_CONFIG_DIR/secure_test_dir"
    ensure_secure_dir "$test_dir" 2>/dev/null
    [ "$?" -eq 0 ]
    [ -d "$test_dir" ]

    local perms
    if stat -c '%a' /dev/null >/dev/null 2>&1; then
        perms=$(stat -c '%a' "$test_dir")
    else
        perms=$(stat -f '%Lp' "$test_dir")
    fi
    [ "$perms" = "700" ]
}

# Test: ensure_secure_dir returns 1 when path is a symlink
@test "ensure_secure_dir returns 1 when path is a symlink" {
    _source_fn print_error print_warning log_error log_warn ensure_secure_dir
    export COLOR_RED='' COLOR_YELLOW='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3

    local link_path="$TEST_CONFIG_DIR/sym_secure_dir"
    ln -s /tmp "$link_path"

    ret=0; ensure_secure_dir "$link_path" 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]
}

# Test: ensure_secure_dir returns 0 for existing directory with correct permissions
@test "ensure_secure_dir returns 0 for existing 700 directory" {
    _source_fn print_error print_warning log_error log_warn ensure_secure_dir
    export COLOR_RED='' COLOR_YELLOW='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3

    local test_dir="$TEST_CONFIG_DIR/already_secure"
    mkdir -m 700 "$test_dir"

    ensure_secure_dir "$test_dir" 2>/dev/null
    [ "$?" -eq 0 ]
}

# Test: ensure_secure_dir returns 1 when path exists as a regular file
@test "ensure_secure_dir returns 1 when path is a regular file" {
    _source_fn print_error print_warning log_error log_warn ensure_secure_dir
    export COLOR_RED='' COLOR_YELLOW='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3

    local file_path="$TEST_CONFIG_DIR/not_a_dir"
    touch "$file_path"

    ret=0; ensure_secure_dir "$file_path" 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]
}

# ============================================================
# load_config Tests
# ============================================================

# Test: load_config reads HOME_NETWORK from config file
@test "load_config reads HOME_NETWORK from config file" {
    _source_fn load_config
    mkdir -p "$CONFIG_DIR"
    printf 'HOME_NETWORK=10.10.0.0/16\n' > "$CONFIG_FILE"

    unset CONFIG_HOME_NETWORK
    load_config

    [ "$CONFIG_HOME_NETWORK" = "10.10.0.0/16" ]
}

# Test: load_config reads HOME_GATEWAY_MAC from config file
@test "load_config reads HOME_GATEWAY_MAC from config file" {
    _source_fn load_config
    mkdir -p "$CONFIG_DIR"
    printf 'HOME_GATEWAY_MAC=aa:bb:cc:dd:ee:ff\n' > "$CONFIG_FILE"

    unset CONFIG_HOME_GATEWAY_MAC
    load_config

    [ "$CONFIG_HOME_GATEWAY_MAC" = "aa:bb:cc:dd:ee:ff" ]
}

# Test: load_config reads LOG_LEVEL from config file
@test "load_config reads LOG_LEVEL from config file" {
    _source_fn load_config
    mkdir -p "$CONFIG_DIR"
    printf 'LOG_LEVEL=debug\n' > "$CONFIG_FILE"

    unset CONFIG_LOG_LEVEL
    load_config

    [ "$CONFIG_LOG_LEVEL" = "debug" ]
}

# Test: load_config skips comment lines
@test "load_config skips comment lines" {
    _source_fn load_config
    mkdir -p "$CONFIG_DIR"
    printf '# This is a comment\nHOME_NETWORK=172.16.0.0/12\n' > "$CONFIG_FILE"

    unset CONFIG_HOME_NETWORK
    load_config

    [ "$CONFIG_HOME_NETWORK" = "172.16.0.0/12" ]
}

# Test: load_config strips double quotes from values
@test "load_config strips double quotes from values" {
    _source_fn load_config
    mkdir -p "$CONFIG_DIR"
    printf 'HOME_NETWORK="192.168.2.0/24"\n' > "$CONFIG_FILE"

    unset CONFIG_HOME_NETWORK
    load_config

    [ "$CONFIG_HOME_NETWORK" = "192.168.2.0/24" ]
}

# Test: load_config strips single quotes from values
@test "load_config strips single quotes from values" {
    _source_fn load_config
    mkdir -p "$CONFIG_DIR"
    printf "HOME_NETWORK='192.168.3.0/24'\n" > "$CONFIG_FILE"

    unset CONFIG_HOME_NETWORK
    load_config

    [ "$CONFIG_HOME_NETWORK" = "192.168.3.0/24" ]
}

# Test: load_config does nothing when config file is absent
@test "load_config does nothing when config file is absent" {
    _source_fn load_config
    # CONFIG_FILE is set in setup() but the file doesn't exist yet

    unset CONFIG_HOME_NETWORK
    load_config

    # Variable should remain unset
    [ -z "${CONFIG_HOME_NETWORK+x}" ] || [ -z "$CONFIG_HOME_NETWORK" ]
}

# Test: load_config reads OIDC_ENABLED from config file
@test "load_config reads OIDC_ENABLED from config file" {
    _source_fn load_config
    mkdir -p "$CONFIG_DIR"
    printf 'OIDC_ENABLED=true\n' > "$CONFIG_FILE"

    unset CONFIG_OIDC_ENABLED
    load_config

    [ "$CONFIG_OIDC_ENABLED" = "true" ]
}

# Test: load_config reads TAILSCALE_AS_HOME from config file
@test "load_config reads TAILSCALE_AS_HOME from config file" {
    _source_fn load_config
    mkdir -p "$CONFIG_DIR"
    printf 'TAILSCALE_AS_HOME=false\n' > "$CONFIG_FILE"

    unset CONFIG_TAILSCALE_AS_HOME
    load_config

    [ "$CONFIG_TAILSCALE_AS_HOME" = "false" ]
}

# ============================================================
# check_ssh_config Tests
# ============================================================

# Test: check_ssh_config returns 0 for known host in SSH config
@test "check_ssh_config returns 0 when SSH config exists for hostname" {
    _source_fn check_ssh_config
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    printf 'Host test-known-host\n    HostName example.com\n    User testuser\n' \
        > "$HOME/.ssh/config"

    check_ssh_config "test-known-host" 2>/dev/null
    [ "$?" -eq 0 ]
}

# Test: check_ssh_config returns 1 when ssh -G fails (no config at all)
@test "check_ssh_config returns 1 when ssh -G fails" {
    _source_fn check_ssh_config

    # Override ssh to always fail
    ssh() { return 1; }
    export -f ssh

    ret=0; check_ssh_config "nonexistent-host-xyz" 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]

    unset -f ssh
}

# Test: check_ssh_config outputs warning message on failure
@test "check_ssh_config outputs warning when host not found" {
    _source_fn check_ssh_config

    ssh() { return 1; }
    export -f ssh

    run check_ssh_config "missing-host" 2>&1
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Warning" ]] || [[ "$output" =~ "missing-host" ]]

    unset -f ssh
}
