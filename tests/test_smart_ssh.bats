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

# Test: Invalid option
@test "smart-ssh with invalid option shows error" {
    run "$SMART_SSH" --invalid-option
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option" ]]
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

# Test: IP address validation (helper function test)
@test "validate IP address format" {
    # Source functions from script
    source <(sed -n '/^validate_ip()/,/^}/p' "$SMART_SSH")

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
    # Source necessary functions
    source <(sed -n '/^validate_ip()/,/^}/p' "$SMART_SSH")
    source <(sed -n '/^print_error()/,/^}/p' "$SMART_SSH")
    source <(sed -n '/^validate_cidr()/,/^}/p' "$SMART_SSH")
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
    # Source the function
    source <(sed -n '/^ip_to_int()/,/^}/p' "$SMART_SSH")

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
    # Create a dummy SSH config to pass check_ssh_config
    mkdir -p ~/.ssh
    echo -e "Host test-host\n    HostName example.com" > ~/.ssh/config

    # Create dummy security key
    touch "$SECURITY_KEY_PATH"

    run "$SMART_SSH" --dry-run --security-key test-host
    [ "$status" -eq 0 ]
    [[ "$output" =~ "DRY RUN" ]]
    [[ "$output" =~ "Would execute:" ]]

    # Cleanup
    rm -f ~/.ssh/config "$SECURITY_KEY_PATH"
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
    source <(sed -n '/^validate_ip()/,/^}/p' "$SMART_SSH")
    source <(sed -n '/^print_error()/,/^}/p' "$SMART_SSH")
    source <(sed -n '/^validate_cidr()/,/^}/p' "$SMART_SSH")
    source <(sed -n '/^ip_to_int()/,/^}/p' "$SMART_SSH")
    source <(sed -n '/^ip_in_cidr()/,/^}/p' "$SMART_SSH")
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

# Helper: source functions from smart-ssh via temp file (bash 3.2 compatible)
# Usage: _source_fn func_name [func_name ...]
_source_fn() {
    local _tmp
    _tmp=$(mktemp)
    for _fn in "$@"; do
        sed -n "/^${_fn}()/,/^}/p" "$SMART_SSH" >> "$_tmp"
    done
    # shellcheck disable=SC1090
    source "$_tmp"
    rm -f "$_tmp"
}

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

# Test: --oidc with missing OIDC config shows error
@test "--oidc with missing OIDC config shows error" {
    run env OIDC_ISSUER="" OIDC_CA_URL="" "$SMART_SSH" --dry-run --oidc test-host
    [ "$status" -ne 0 ]
}
