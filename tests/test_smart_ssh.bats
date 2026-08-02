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
    _assert_output_has "Usage:"
    _assert_output_has "--help"
}

# Test: Invalid option (treated as SSH option, but no hostname → error)
@test "smart-ssh with invalid option shows error" {
    run "$SMART_SSH" --invalid-option
    [ "$status" -eq 1 ]
    _assert_output_has "Please specify a hostname"
}

# Test: No hostname argument
@test "smart-ssh without hostname shows error" {
    run "$SMART_SSH"
    [ "$status" -eq 0 ]  # Shows usage
    _assert_output_has "Usage:"
}

# Test: Configuration file initialization
@test "smart-ssh --init-config creates config file" {
    run "$SMART_SSH" --init-config
    [ "$status" -eq 0 ]
    [ -f "$CONFIG_FILE" ]
    _assert_output_has "Configuration file created"
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
# `[[ ]]` is a shell keyword, and a non-final one that fails does not trip
# bats' errexit — the assertion silently passes and the test proves nothing.
# Route substring checks through a function so a failure is a real command
# failure, which errexit does catch wherever it appears.
# Usage: _assert_output_has <substring> / _refute_output_has <substring>
#        _assert_output_matches <extended regex>
_assert_output_matches() {
    if [[ "$output" =~ $1 ]]; then
        return 0
    fi
    echo "expected output to match: $1" >&2
    echo "actual output: $output" >&2
    return 1
}

_assert_output_has() {
    case "$output" in
        *"$1"*) return 0 ;;
    esac
    echo "expected output to contain: $1" >&2
    echo "actual output: $output" >&2
    return 1
}

_refute_output_has() {
    case "$output" in
        *"$1"*)
            echo "expected output NOT to contain: $1" >&2
            echo "actual output: $output" >&2
            return 1
            ;;
    esac
    return 0
}

# Print one function's body from the script under test, on stdout.
# Brace-depth counting so a nested function does not end the extraction early.
# Usage: _extract_fn func_name
_extract_fn() {
    awk -v fn="$1" '
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
    ' "$SMART_SSH"
}

# Usage: _source_fn func_name [func_name ...]
_source_fn() {
    local _tmp
    _tmp=$(mktemp "$TEST_CONFIG_DIR/src_fn.XXXXXX")
    for _fn in "$@"; do
        _extract_fn "$_fn" >> "$_tmp"
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
    _assert_output_has "Debug Information"
    _assert_output_has "Configuration:"
    _assert_output_has "Network:"
}

# Test: Environment variable override
@test "environment variable overrides config file" {
    # Create config file
    "$SMART_SSH" --init-config > /dev/null 2>&1

    # Override with environment variable
    export HOME_NETWORK="10.0.0.0/8"

    run "$SMART_SSH" --debug
    _assert_output_has "10.0.0.0/8"
}

# Test: Multiple home networks
@test "support multiple comma-separated home networks" {
    export HOME_NETWORK="192.168.1.0/24,10.0.0.0/8,172.16.0.0/12"

    run "$SMART_SSH" --debug
    [ "$status" -eq 0 ]
    _assert_output_has "192.168.1.0/24,10.0.0.0/8,172.16.0.0/12"
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
    _assert_output_has "DRY RUN"
    _assert_output_has "Would execute:"
    # Cleanup handled by teardown (rm -rf TEST_CONFIG_DIR)
}

# Test: Configuration file overwrite protection
@test "init-config asks before overwriting existing file" {
    # Create initial config
    "$SMART_SSH" --init-config > /dev/null 2>&1

    # Try to create again (should ask for confirmation)
    run bash -c "echo 'n' | $SMART_SSH --init-config"
    [ "$status" -eq 1 ]
    _assert_output_has "already exists"
}

# Test: Log level configuration
@test "log level can be configured" {
    export LOG_LEVEL="debug"

    run "$SMART_SSH" --debug
    [ "$status" -eq 0 ]
    _assert_output_has "LOG_LEVEL: debug"
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
    _assert_output_has "TAILSCALE_AS_HOME: true"
}

# Test: TAILSCALE_AS_HOME can be disabled
@test "TAILSCALE_AS_HOME can be set to false" {
    export TAILSCALE_AS_HOME="false"

    run "$SMART_SSH" --debug
    [ "$status" -eq 0 ]
    _assert_output_has "TAILSCALE_AS_HOME: false"
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
    _assert_output_has "OIDC:"
    _assert_output_has "OIDC_ENABLED:"
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

# Test: oidc_check_cached_cert() returns 1 when cert/key fingerprints mismatch
@test "oidc_check_cached_cert returns 1 when cert and key fingerprints mismatch" {
    _source_fn print_error print_debug log_error log_debug oidc_check_cached_cert
    export COLOR_RED='' COLOR_BLUE='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3
    export OIDC_CERT_DIR="$TEST_CONFIG_DIR/oidc-certs"
    mkdir -p "$OIDC_CERT_DIR"

    # Generate two different key pairs — cert from one, private key from the other
    ssh-keygen -t ed25519 -f "$OIDC_CERT_DIR/key_a" -N "" -q
    ssh-keygen -t ed25519 -f "$OIDC_CERT_DIR/key_b" -N "" -q

    # Create a self-signed cert for key_a (using ssh-keygen -s requires a CA;
    # instead, just use key_a's public key as the "cert" — ssh-keygen -L will
    # fail to parse it, triggering the empty-fingerprint path)
    # For a proper test, generate a real cert:
    ssh-keygen -s "$OIDC_CERT_DIR/key_a" -I test -n testuser -V +1h "$OIDC_CERT_DIR/key_a.pub"
    cp "$OIDC_CERT_DIR/key_a-cert.pub" "$OIDC_CERT_DIR/id_oidc-cert.pub"
    # Use key_b as the private key (mismatched)
    cp "$OIDC_CERT_DIR/key_b" "$OIDC_CERT_DIR/id_oidc"

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
    # Give the alias a config entry so check_ssh_config settles it from the
    # host list. Without one it falls through to name resolution against the
    # live resolver, which has taken minutes on an unresolvable name.
    mkdir -p "$TEST_CONFIG_DIR/.ssh"
    printf 'Host test-host\n    HostName example.com\n' > "$TEST_CONFIG_DIR/.ssh/config"

    run env HOME="$TEST_CONFIG_DIR" OIDC_ISSUER="" OIDC_CA_URL="" \
        OIDC_CERT_DIR="$TEST_CONFIG_DIR/empty-oidc-certs" \
        "$SMART_SSH" --dry-run --oidc test-host
    [ "$status" -ne 0 ]
}

# Test: OIDC + ProxyJump offers OIDC cert to proxy host alongside original key
# Background: PR #21 stopped applying IdentitiesOnly/IdentityAgent-none on the
# proxy hop (so the proxy's own key + ssh-agent stay usable). This test locks
# in the follow-up: the OIDC IdentityFile/CertificateFile are also offered to
# the proxy host as the PRIMARY identity (written before the original
# identityfile), so a proxy sshd configured with TrustedUserCAKeys can
# authenticate the user with the same OIDC cert as the target — without
# falling back to a second key. The proxy's configured identityfile and the
# ssh-agent remain as fallbacks for proxies that do not trust the OIDC CA.
@test "ssh_with_oidc ProxyJump offers OIDC cert as primary identity on proxy host" {
    _source_fn print_error print_warning print_info print_success print_debug \
        log_error log_warn log_info log_debug \
        validate_ssh_hostname ssh_with_oidc
    export COLOR_RED='' COLOR_YELLOW='' COLOR_BLUE='' COLOR_RESET=''
    export CURRENT_LOG_LEVEL=3

    # Set OIDC config
    export OIDC_CERT_DIR="$TEST_CONFIG_DIR/oidc-certs"
    mkdir -p "$OIDC_CERT_DIR"

    # Mock OIDC prerequisites to succeed
    check_oidc_dependencies() { return 0; }
    validate_oidc_urls() { return 0; }
    validate_oidc_cert_lifetime() { return 0; }
    ensure_oidc_cert_dir() { return 0; }
    oidc_check_cached_cert() { return 0; }

    # Mock ssh to return controlled -G output. The host is read as the last
    # argument rather than $2, because the real calls carry config options and
    # a `--` separator ahead of it.
    ssh() {
        [ "$1" = "-G" ] || return 0
        local host
        for host in "$@"; do :; done
        case "$host" in
            target)
                printf "user deploy\nhostname 10.0.0.5\nport 22\nproxyjump bastion\n" ;;
            bastion)
                printf "user admin\nhostname bastion.example.com\nport 22\nidentityfile /home/testuser/.ssh/id_ed25519\n" ;;
        esac
    }

    run ssh_with_oidc target true
    [ "$status" -eq 0 ]

    # Extract the proxy host stanza (Host bastion ... up to the next blank line)
    # avoids the prior `grep -AN` window-size fragility that silently truncated
    # assertions when the stanza grew.
    proxy_stanza=$(echo "$output" | awk '/^[[:space:]]*Host bastion[[:space:]]*$/{p=1; next} p && /^[[:space:]]*$/{p=0} p')
    target_stanza=$(echo "$output" | awk '/^[[:space:]]*Host target[[:space:]]*$/{p=1; next} p && /^[[:space:]]*$/{p=0} p')

    # Proxy stanza MUST contain the OIDC IdentityFile and CertificateFile
    echo "$proxy_stanza" | grep -q "CertificateFile $OIDC_CERT_DIR/id_oidc-cert.pub"
    echo "$proxy_stanza" | grep -q "IdentityFile $OIDC_CERT_DIR/id_oidc"
    # Proxy stanza MUST retain the original identityfile as a fallback
    echo "$proxy_stanza" | grep -qi "identityfile /home/testuser/.ssh/id_ed25519"
    # Proxy stanza MUST NOT pin to a single identity — ssh-agent + the proxy's
    # own key must remain usable when the proxy does not trust the OIDC CA.
    ! echo "$proxy_stanza" | grep -q "IdentitiesOnly yes"
    ! echo "$proxy_stanza" | grep -q "IdentityAgent none"

    # OIDC IdentityFile must appear BEFORE the original identityfile (OpenSSH
    # tries IdentityFile directives in listed order; cert-first lets a
    # TrustedUserCAKeys-configured proxy accept the OIDC cert without
    # consuming MaxAuthTries on the fallback key).
    oidc_line=$(echo "$proxy_stanza" | grep -n "IdentityFile $OIDC_CERT_DIR/id_oidc$" | head -1 | cut -d: -f1)
    fallback_line=$(echo "$proxy_stanza" | grep -ni "identityfile /home/testuser/.ssh/id_ed25519" | head -1 | cut -d: -f1)
    [ -n "$oidc_line" ] && [ -n "$fallback_line" ] && [ "$oidc_line" -lt "$fallback_line" ]

    # Target host stanza must contain OIDC CertificateFile
    echo "$target_stanza" | grep -q "CertificateFile"
}

# ============================================================
# Version Tests
# ============================================================

# Test: --version flag
@test "smart-ssh --version shows version string" {
    run "$SMART_SSH" --version
    [ "$status" -eq 0 ]
    _assert_output_has "smart-ssh "
    # Version must be semver format
    _assert_output_matches '[0-9]+\.[0-9]+\.[0-9]+'
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
# Usage: _create_ts_test_script <mock_dir> <hostname> [log level]
# The script sets PATH to mock_dir internally, so bash can find mock commands.
# The log level defaults to info, the level a user actually runs at — a message
# asserted only at debug proves nothing about what they would see.
_create_ts_test_script() {
    local mock_dir="$1"
    local test_hostname="$2"
    local log_level="${3:-1}"
    local _tmp
    _tmp=$(mktemp "$TEST_CONFIG_DIR/ts_script.XXXXXX")

    # Set environment at top of script. The heredoc is unquoted so $mock_dir
    # expands, which means every value here must be a literal — an inherited
    # TAILSCALE_CLI_BUNDLE_PATH must not be allowed to win, or a real
    # Tailscale.app on the machine running the suite answers for the mock.
    cat >> "$_tmp" <<HEADER
#!/bin/bash
export PATH="$mock_dir"
export COLOR_RED='' COLOR_BLUE='' COLOR_YELLOW='' COLOR_RESET=''
# The log functions compare against these thresholds; without them every
# comparison errors out and the script runs silently, hiding the messages that
# tell a user why their credential was downgraded
export LOG_LEVEL_DEBUG=0 LOG_LEVEL_INFO=1 LOG_LEVEL_WARN=2 LOG_LEVEL_ERROR=3
export CURRENT_LOG_LEVEL=$log_level
TAILSCALE_CLI_BUNDLE_PATH="$mock_dir/bundled-tailscale"
HEADER

    # Extract all needed functions from smart-ssh
    local _fn
    for _fn in print_error print_warning print_debug log_error log_warn log_debug log_info validate_ip validate_cidr ip_to_int ip_in_cidr resolve_hostname_via_os resolve_hostname find_tailscale_cli tailscale_peer_ip is_tailscale_host; do
        _extract_fn "$_fn" >> "$_tmp"
        # A silently missing function turns every allow-side test into an
        # unexplained "status 1", so fail here instead
        grep -q "^${_fn}()" "$_tmp" || {
            echo "failed to extract $_fn from $SMART_SSH" >&2
            return 1
        }
    done

    # Report the address the daemon vouched for, so a test can assert the
    # connection would be pinned to it rather than re-resolved
    echo "is_tailscale_host \"$test_hostname\" || exit 1" >> "$_tmp"
    echo 'printf "TAILSCALE_PEER_IP=%s\n" "$TAILSCALE_PEER_IP"' >> "$_tmp"
    echo "$_tmp"
}

# Helper: mock dir with an `ssh -G` stub reporting <hostname> and the coreutils
# the extracted functions need. No tailscale CLI, so the daemon cannot be asked.
# Usage: _make_ts_mocks <hostname>
_make_ts_mocks() {
    local resolved_host="$1"
    local mock_dir
    mock_dir=$(mktemp -d "$TEST_CONFIG_DIR/ts_mock.XXXXXX")

    # `ssh -G` reports the config as ssh will apply it, so the stub has to
    # honour the same command-line options — that a `-o HostName=` on the
    # command line moves the target is the whole point of verifying with them
    cat > "$mock_dir/ssh" <<SSH_STUB
#!/bin/bash
host="$resolved_host"
alias=""
for arg in "\$@"; do
    case "\$arg" in
        HostName=*) host="\${arg#HostName=}" ;;
        HostKeyAlias=*) alias="\${arg#HostKeyAlias=}" ;;
    esac
done
echo "hostname \$host"
[ -n "\$alias" ] && echo "hostkeyalias \$alias"
exit 0
SSH_STUB
    chmod +x "$mock_dir/ssh"

    local cmd cmd_path
    for cmd in jq grep awk cut head tr sed printf cat stat; do
        cmd_path=$(command -v "$cmd" 2>/dev/null) && ln -sf "$cmd_path" "$mock_dir/$cmd"
    done

    echo "$mock_dir"
}

# Assert the `ssh -G` stub is reachable and reports what the test intends.
# Without this, every deny-side test below passes just as well when the fixture
# is dead: is_tailscale_host returns 1 on an empty HostName before touching any
# Tailscale logic, and the "was never called" sentinels are satisfied by a
# function that never ran.
# Usage: _assert_ts_mocks_live <mock_dir> <expected hostname>
_assert_ts_mocks_live() {
    local mock_dir="$1"
    local expected="$2"
    [ -x "$mock_dir/ssh" ]
    [ "$(PATH="$mock_dir" ssh -G anything)" = "hostname $expected" ]
    # and it honours a command-line override, as the real ssh -G does
    [ "$(PATH="$mock_dir" ssh -G -o HostName=probe.invalid anything)" = "hostname probe.invalid" ]
}

# Helper: a tailscale CLI mock that keeps the real CLI's contract, because the
# bugs worth catching here live in that contract:
#   - `whois` takes an address and rejects a name, printing nothing on stdout
#     (measured against 1.98.8; its exit status has varied across releases, so
#     the mock exits non-zero and the caller must not depend on either)
#   - `status --json` is the only place a name maps to a tailnet address, and
#     every node carries both an IPv4 and an IPv6 address
# It records the argument whois was called with, so a test can prove the caller
# passed an address rather than merely that the outcome was right.
# Usage: _make_tailscale_mock <mock_dir> <cli name> <up|down> [whois json]
# The fourth argument is what whois prints for a known address. `{}` is a
# well-formed reply identifying nobody; an empty string is no reply at all.
# Both must read as a refusal rather than a pass.
_make_tailscale_mock() {
    local mock_dir="$1"
    local cli_name="$2"
    local daemon="$3"
    local whois_body="${4-DEFAULT}"
    [ "$whois_body" = "DEFAULT" ] && whois_body='{"Node":{"ID":12345,"Name":"myhost"}}'

    cat > "$mock_dir/$cli_name" <<MOCK_TS
#!/bin/bash
if [ "\$1" = "status" ]; then
    [ "$daemon" = "up" ] || { echo "failed to connect to local Tailscale daemon" >&2; exit 1; }
    [ "\$2" = "--json" ] || exit 0
    cat <<'JSON'
{
  "Self": {"DNSName": "self.tailnet-test.ts.net.",
           "TailscaleIPs": ["100.64.10.1", "fd7a:115c:a1e0::1"]},
  "Peer": {
    "nodekey:aaa": {"DNSName": "myhost.tailnet-test.ts.net.",
                    "TailscaleIPs": ["100.64.10.2", "fd7a:115c:a1e0::2"]},
    "nodekey:bbb": {"DNSName": "other.tailnet-test.ts.net.",
                    "TailscaleIPs": ["100.64.10.3", "fd7a:115c:a1e0::3"]},
    "nodekey:ccc": {"TailscaleIPs": ["100.64.10.4", "fd7a:115c:a1e0::4"]},
    "nodekey:ddd": {"DNSName": "", "TailscaleIPs": ["100.64.10.5"]},
    "nodekey:eee": {"DNSName": "myhost.other-tailnet.ts.net.", "TailscaleIPs": []}
  }
}
JSON
    exit 0
fi

if [ "\$1" = "whois" ]; then
    addr="\$3"
    [ "\$2" = "--json" ] || addr="\$2"
    echo "\$addr" > "$TEST_CONFIG_DIR/whois_arg"
    # The real CLI answers only for an address and prints nothing for anything
    # else. It accepts either address family.
    case "\$addr" in
        100.64.10.*|fd7a:115c:a1e0::*) [ -n '$whois_body' ] && echo '$whois_body'; exit 0 ;;
        *.*[a-zA-Z]*|*[a-zA-Z]*.*)
            echo "400 Bad Request: invalid 'addr' parameter" >&2; exit 1 ;;
        *) echo "no peer found with IP \$addr" >&2; exit 1 ;;
    esac
fi

exit 1
MOCK_TS
    chmod +x "$mock_dir/$cli_name"
}

# --- No daemon to ask -------------------------------------------------------
# Every case here shares one claim: without the daemon there is no answer to
# "is this a Tailscale node", so no destination property may stand in for one.
# Each shape was previously accepted by the heuristic and is now refused.

# Test: a CGNAT destination is not evidence. 100.64.0.0/10 is shared CGNAT
# space a hostile DHCP server can hand out, on both ends of the connection.
@test "is_tailscale_host: CGNAT destination refused when the daemon cannot be asked" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "100.100.1.1")
    _assert_ts_mocks_live "$mock_dir" "100.100.1.1"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "test-ts-host")

    run bash "$test_script"
    [ "$status" -eq 1 ]
}

# Test: a *.ts.net name is a label chosen in the user's own config, not proof
# that a tailnet path exists right now
@test "is_tailscale_host: ts.net name refused when the daemon cannot be asked" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "myhost.tailnet-test.ts.net")
    _assert_ts_mocks_live "$mock_dir" "myhost.tailnet-test.ts.net"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "myhost.tailnet-test.ts.net")

    run bash "$test_script"
    [ "$status" -eq 1 ]
    _assert_output_has "CLI not found"
    _assert_output_has "treating as external"
}

# Test: a DNS answer in the CGNAT range is refused too — the resolver on an
# untrusted network is the attacker's, so it can name any address it likes
@test "is_tailscale_host: DNS-resolved CGNAT address refused when the daemon cannot be asked" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "nas.example.com")
    printf '#!/bin/bash\ntouch %q\necho "nas.example.com has address 100.64.10.2"\n' \
        "$TEST_CONFIG_DIR/resolver_was_called" > "$mock_dir/host"
    chmod +x "$mock_dir/host"
    _assert_ts_mocks_live "$mock_dir" "nas.example.com"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "nas.example.com")

    run bash "$test_script"
    [ "$status" -eq 1 ]
    # Not merely refused after asking — name resolution no longer feeds the
    # credential decision at all
    [ ! -e "$TEST_CONFIG_DIR/resolver_was_called" ]
}

# Test: a stopped daemon is the same situation as an absent one. The message
# matters: an unexplained key prompt is what makes users disable the check.
@test "is_tailscale_host: refuses when daemon not running" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "myhost.tailnet-test.ts.net")
    _make_tailscale_mock "$mock_dir" tailscale down
    _assert_ts_mocks_live "$mock_dir" "myhost.tailnet-test.ts.net"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "test-ts-host")

    run bash "$test_script"
    [ "$status" -eq 1 ]
    _assert_output_has "daemon is not running"
    _assert_output_has "treating as external"
}

# Test: jq is what reads the daemon's answer; without it there is no answer
@test "is_tailscale_host: refuses and says why when jq is unavailable" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "myhost.tailnet-test.ts.net")
    _make_tailscale_mock "$mock_dir" tailscale up
    rm -f "$mock_dir/jq"
    _assert_ts_mocks_live "$mock_dir" "myhost.tailnet-test.ts.net"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "myhost.tailnet-test.ts.net")

    run bash "$test_script"
    [ "$status" -eq 1 ]
    _assert_output_has "jq"
    _assert_output_has "treating as external"
}

# --- The daemon answers -----------------------------------------------------
# HostName in ssh_config can name a node several ways. Each must reach whois as
# an address, since that is the only argument the real CLI accepts — and the
# caller must come away with that address, not just a yes.

# Test: MagicDNS FQDN. Also pins that whois was handed an address, not the
# name, and that the verified address is published for the caller to connect to.
@test "is_tailscale_host: accepts a MagicDNS FQDN and reports the verified address" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "myhost.tailnet-test.ts.net")
    _make_tailscale_mock "$mock_dir" tailscale up
    _assert_ts_mocks_live "$mock_dir" "myhost.tailnet-test.ts.net"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "myhost.tailnet-test.ts.net")

    run bash "$test_script"
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_CONFIG_DIR/whois_arg")" = "100.64.10.2" ]
    _assert_output_has "TAILSCALE_PEER_IP=100.64.10.2"
}

# Test: MagicDNS FQDN with the trailing dot the daemon itself reports
@test "is_tailscale_host: accepts a MagicDNS FQDN with a trailing dot" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "myhost.tailnet-test.ts.net.")
    _make_tailscale_mock "$mock_dir" tailscale up
    _assert_ts_mocks_live "$mock_dir" "myhost.tailnet-test.ts.net."

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "myhost.tailnet-test.ts.net.")

    run bash "$test_script"
    [ "$status" -eq 0 ]
    _assert_output_has "TAILSCALE_PEER_IP=100.64.10.2"
}

# Test: DNS names are case-insensitive, so the match must be too
@test "is_tailscale_host: accepts a MagicDNS FQDN in a different case" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "MyHost.Tailnet-Test.TS.NET")
    _make_tailscale_mock "$mock_dir" tailscale up
    _assert_ts_mocks_live "$mock_dir" "MyHost.Tailnet-Test.TS.NET"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "MyHost.Tailnet-Test.TS.NET")

    run bash "$test_script"
    [ "$status" -eq 0 ]
    _assert_output_has "TAILSCALE_PEER_IP=100.64.10.2"
}

# Test: the local node, reached by its own MagicDNS name. Self is a separate
# branch of the candidate list from Peer and needs its own coverage.
@test "is_tailscale_host: accepts the local node by its MagicDNS name" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "self.tailnet-test.ts.net")
    _make_tailscale_mock "$mock_dir" tailscale up
    _assert_ts_mocks_live "$mock_dir" "self.tailnet-test.ts.net"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "self.tailnet-test.ts.net")

    run bash "$test_script"
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_CONFIG_DIR/whois_arg")" = "100.64.10.1" ]
}

# Test: a tailnet IPv4 address written directly in ssh_config
@test "is_tailscale_host: accepts a tailnet IPv4 address" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "100.64.10.3")
    _make_tailscale_mock "$mock_dir" tailscale up
    _assert_ts_mocks_live "$mock_dir" "100.64.10.3"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "other")

    run bash "$test_script"
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_CONFIG_DIR/whois_arg")" = "100.64.10.3" ]
}

# Test: every node also has an IPv6 tailnet address, and ssh_config may carry
# it in any case
@test "is_tailscale_host: accepts a tailnet IPv6 address in any case" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "FD7A:115C:A1E0::3")
    _make_tailscale_mock "$mock_dir" tailscale up
    _assert_ts_mocks_live "$mock_dir" "FD7A:115C:A1E0::3"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "other")

    run bash "$test_script"
    [ "$status" -eq 0 ]
    # The address handed to whois is the daemon's own first entry for that node
    [ "$(cat "$TEST_CONFIG_DIR/whois_arg")" = "100.64.10.3" ]
}

# Test: the CLI is found inside the macOS app bundle, where the App Store build
# leaves it with no PATH symlink. Losing the heuristic costs those users
# nothing only if this lookup works.
@test "is_tailscale_host: finds the CLI in the macOS app bundle" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "myhost.tailnet-test.ts.net")
    _make_tailscale_mock "$mock_dir" bundled-tailscale up
    _assert_ts_mocks_live "$mock_dir" "myhost.tailnet-test.ts.net"

    # find_tailscale_cli requires root ownership before running a binary from
    # this path; a test fixture cannot have it, so exercise the lookup with the
    # ownership check stubbed to agree
    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "myhost.tailnet-test.ts.net")
    # _make_ts_mocks symlinked the real stat; replace the link, do not write through it
    rm -f "$mock_dir/stat"
    printf '#!/bin/bash\necho 0\n' > "$mock_dir/stat"
    chmod +x "$mock_dir/stat"

    run bash "$test_script"
    [ "$status" -eq 0 ]
    _assert_output_has "TAILSCALE_PEER_IP=100.64.10.2"
}

# Test: a bundle CLI nobody privileged installed is not run. This path is
# consulted only when Tailscale is absent, and on macOS /Applications is
# group-writable, so anything sitting there was put there by an ordinary
# process — running it would let it vouch for any host.
@test "is_tailscale_host: refuses a bundle CLI that root does not own" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "myhost.tailnet-test.ts.net")
    _make_tailscale_mock "$mock_dir" bundled-tailscale up
    _assert_ts_mocks_live "$mock_dir" "myhost.tailnet-test.ts.net"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "myhost.tailnet-test.ts.net")
    rm -f "$mock_dir/stat"
    printf '#!/bin/bash\necho 501\n' > "$mock_dir/stat"
    chmod +x "$mock_dir/stat"

    run bash "$test_script"
    [ "$status" -eq 1 ]
    _assert_output_has "not owned by root"
}

# Test: a bundle path pointing at a directory is not a CLI. A directory is
# executable, so accepting one would run it, fail with exit 126, and report
# "daemon is not running" — sending the user to debug the wrong thing.
@test "is_tailscale_host: refuses a bundle path that is a directory" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "myhost.tailnet-test.ts.net")
    _assert_ts_mocks_live "$mock_dir" "myhost.tailnet-test.ts.net"
    mkdir -p "$mock_dir/bundled-tailscale"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "myhost.tailnet-test.ts.net")
    # Root owns /Applications, so the ownership check would pass a directory
    # sitting there; the file check is what has to reject it
    rm -f "$mock_dir/stat"
    printf '#!/bin/bash\necho 0\n' > "$mock_dir/stat"
    chmod +x "$mock_dir/stat"

    run bash "$test_script"
    [ "$status" -eq 1 ]
    _assert_output_has "CLI not found"
    _refute_output_has "daemon is not running"
}

# --- The daemon answers no --------------------------------------------------

# Test: a host the daemon does not list is refused, and whois is never asked
# about it — a name would only draw the CLI's "invalid addr" complaint anyway
@test "is_tailscale_host: refuses a host the daemon does not list" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "203.0.113.1")
    _make_tailscale_mock "$mock_dir" tailscale up
    _assert_ts_mocks_live "$mock_dir" "203.0.113.1"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "test-external-host")

    run bash "$test_script"
    [ "$status" -eq 1 ]
    [ ! -e "$TEST_CONFIG_DIR/whois_arg" ]
    _assert_output_has "not a node on this tailnet"
}

# Test: a name that merely looks like a tailnet member is not one. Only the
# daemon's peer list decides membership.
@test "is_tailscale_host: refuses a ts.net name absent from the peer list" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "impostor.tailnet-test.ts.net")
    _make_tailscale_mock "$mock_dir" tailscale up
    _assert_ts_mocks_live "$mock_dir" "impostor.tailnet-test.ts.net"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "impostor.tailnet-test.ts.net")

    run bash "$test_script"
    [ "$status" -eq 1 ]
    [ ! -e "$TEST_CONFIG_DIR/whois_arg" ]
}

# Test: a bare node label is refused. `HostName nas` for a LAN machine must not
# match a tailnet peer that happens to be called nas — the label is the user's
# own shorthand, with no binding to the tailnet.
@test "is_tailscale_host: refuses a bare node label" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "myhost")
    _make_tailscale_mock "$mock_dir" tailscale up
    _assert_ts_mocks_live "$mock_dir" "myhost"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "myhost")

    run bash "$test_script"
    [ "$status" -eq 1 ]
    [ ! -e "$TEST_CONFIG_DIR/whois_arg" ]
}

# Test: peers with no DNSName, an empty DNSName, or no addresses are ordinary
# entries in a real peer list. One of them must not take the whole lookup down.
@test "is_tailscale_host: tolerates peers with missing DNSName or addresses" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "other.tailnet-test.ts.net")
    _make_tailscale_mock "$mock_dir" tailscale up
    _assert_ts_mocks_live "$mock_dir" "other.tailnet-test.ts.net"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "other.tailnet-test.ts.net")

    run bash "$test_script"
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_CONFIG_DIR/whois_arg")" = "100.64.10.3" ]
}

# Test: an empty HostName must not match the nameless peer in the list
@test "is_tailscale_host: an empty HostName matches nothing" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "")
    _make_tailscale_mock "$mock_dir" tailscale up

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "")

    run bash "$test_script"
    [ "$status" -eq 1 ]
    [ ! -e "$TEST_CONFIG_DIR/whois_arg" ]
}

# Test: whois saying nothing at all is a refusal. Distinguishing "no answer"
# from "an answer naming nobody" is what keeps the debug trail readable.
@test "is_tailscale_host: refuses when whois answers nothing" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "myhost.tailnet-test.ts.net")
    _make_tailscale_mock "$mock_dir" tailscale up ""
    _assert_ts_mocks_live "$mock_dir" "myhost.tailnet-test.ts.net"

    local test_script
    # This message is debug-level detail, so ask for debug
    test_script=$(_create_ts_test_script "$mock_dir" "myhost.tailnet-test.ts.net" 0)

    run bash "$test_script"
    [ "$status" -eq 1 ]
    # The lookup did happen — this is a refusal on the answer, not a short-circuit
    [ "$(cat "$TEST_CONFIG_DIR/whois_arg")" = "100.64.10.2" ]
    _assert_output_has "no answer"
}

# Test: whois answering with no Node.ID is a refusal, not a pass
@test "is_tailscale_host: refuses when whois reports no node id" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "myhost.tailnet-test.ts.net")
    _make_tailscale_mock "$mock_dir" tailscale up '{}'
    _assert_ts_mocks_live "$mock_dir" "myhost.tailnet-test.ts.net"

    local test_script
    test_script=$(_create_ts_test_script "$mock_dir" "myhost.tailnet-test.ts.net")

    run bash "$test_script"
    [ "$status" -eq 1 ]
    [ "$(cat "$TEST_CONFIG_DIR/whois_arg")" = "100.64.10.2" ]
}

# --- End to end -------------------------------------------------------------

# Test: a confirmed Tailscale connection is pinned to the address the daemon
# vouched for. Verifying an address and then letting ssh resolve the name again
# would put the decision and the connection on different hosts, which is the
# whole reason the heuristics were removed.
@test "smart-ssh pins a Tailscale connection to the verified address" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "myhost.tailnet-test.ts.net")
    _make_tailscale_mock "$mock_dir" tailscale up
    _assert_ts_mocks_live "$mock_dir" "myhost.tailnet-test.ts.net"

    # check_ssh_config runs first and needs the alias to exist
    mkdir -p "$TEST_CONFIG_DIR/.ssh"
    printf 'Host myhost\n    HostName myhost.tailnet-test.ts.net\n' \
        > "$TEST_CONFIG_DIR/.ssh/config"

    run env PATH="$mock_dir:$PATH" NO_COLOR=1 HOME="$TEST_CONFIG_DIR" \
        "$SMART_SSH" --dry-run myhost
    [ "$status" -eq 0 ]
    _assert_output_has "Tailscale"
    _assert_output_has "-o HostName=100.64.10.2"
    # known_hosts stays keyed on the name the user typed, so pinning the
    # address costs no host-key prompts
    _assert_output_has "-o HostKeyAlias=myhost.tailnet-test.ts.net"
}

# Test: a command-line HostName cannot ride on the Tailscale verdict. ssh takes
# the FIRST value of an option, so a pin appended after the caller's arguments
# would lose to their own -o HostName= — and the alias would have been verified
# while the connection went somewhere else entirely.
@test "smart-ssh refuses to vouch for a host redirected by -o HostName" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "myhost.tailnet-test.ts.net")
    _make_tailscale_mock "$mock_dir" tailscale up
    _assert_ts_mocks_live "$mock_dir" "myhost.tailnet-test.ts.net"

    mkdir -p "$TEST_CONFIG_DIR/.ssh"
    printf 'Host myhost\n    HostName myhost.tailnet-test.ts.net\n' \
        > "$TEST_CONFIG_DIR/.ssh/config"

    run env PATH="$mock_dir:$PATH" NO_COLOR=1 HOME="$TEST_CONFIG_DIR" \
        HOME_NETWORK="192.0.2.0/24" \
        "$SMART_SSH" --dry-run myhost -o HostName=external.example
    [ "$status" -eq 0 ]
    # The verdict is about the host ssh will actually reach, which is not a peer
    _refute_output_has "detected (Tailscale"
    _refute_output_has "HostName=100.64.10.2"
    _assert_output_has "is not a node on this tailnet"
}

# Test: when the target is genuinely a peer, the pin is placed ahead of the
# caller's own options so it is the value ssh uses
@test "smart-ssh places the address pin ahead of caller options" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "myhost.tailnet-test.ts.net")
    _make_tailscale_mock "$mock_dir" tailscale up
    _assert_ts_mocks_live "$mock_dir" "myhost.tailnet-test.ts.net"

    mkdir -p "$TEST_CONFIG_DIR/.ssh"
    printf 'Host myhost\n    HostName myhost.tailnet-test.ts.net\n' \
        > "$TEST_CONFIG_DIR/.ssh/config"

    run env PATH="$mock_dir:$PATH" NO_COLOR=1 HOME="$TEST_CONFIG_DIR" \
        "$SMART_SSH" --dry-run myhost -p 2222
    [ "$status" -eq 0 ]
    _assert_output_matches 'ssh -o HostName=100\.64\.10\.2 .*-p 2222'
}

# Test: a HostKeyAlias the user already configured stays authoritative —
# overriding it would send known_hosts to the wrong entry and prompt
@test "smart-ssh keeps a configured HostKeyAlias when pinning" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "myhost.tailnet-test.ts.net")
    _make_tailscale_mock "$mock_dir" tailscale up
    _assert_ts_mocks_live "$mock_dir" "myhost.tailnet-test.ts.net"

    mkdir -p "$TEST_CONFIG_DIR/.ssh"
    printf 'Host myhost\n    HostName myhost.tailnet-test.ts.net\n' \
        > "$TEST_CONFIG_DIR/.ssh/config"

    run env PATH="$mock_dir:$PATH" NO_COLOR=1 HOME="$TEST_CONFIG_DIR" \
        "$SMART_SSH" --dry-run myhost -o HostKeyAlias=mine
    [ "$status" -eq 0 ]
    _assert_output_has "-o HostName=100.64.10.2"
    _refute_output_has "HostKeyAlias=myhost.tailnet-test.ts.net"
    _assert_output_has "-o HostKeyAlias=mine"
}

# Test: the away path is not pinned — nothing vouched for an address there
@test "smart-ssh does not pin when Tailscale cannot vouch for the host" {
    local mock_dir
    mock_dir=$(_make_ts_mocks "203.0.113.1")
    _make_tailscale_mock "$mock_dir" tailscale up
    _assert_ts_mocks_live "$mock_dir" "203.0.113.1"

    mkdir -p "$TEST_CONFIG_DIR/.ssh"
    printf 'Host external-host\n    HostName 203.0.113.1\n' \
        > "$TEST_CONFIG_DIR/.ssh/config"

    run env PATH="$mock_dir:$PATH" NO_COLOR=1 HOME="$TEST_CONFIG_DIR" \
        HOME_NETWORK="192.0.2.0/24" \
        "$SMART_SSH" --dry-run --security-key external-host
    [ "$status" -eq 0 ]
    _refute_output_has "HostName="
    _refute_output_has "HostKeyAlias="
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
    _source_fn trim_whitespace load_config
    mkdir -p "$CONFIG_DIR"
    printf 'HOME_NETWORK=10.10.0.0/16\n' > "$CONFIG_FILE"

    unset CONFIG_HOME_NETWORK
    load_config

    [ "$CONFIG_HOME_NETWORK" = "10.10.0.0/16" ]
}

# Test: load_config reads HOME_GATEWAY_MAC from config file
@test "load_config reads HOME_GATEWAY_MAC from config file" {
    _source_fn trim_whitespace load_config
    mkdir -p "$CONFIG_DIR"
    printf 'HOME_GATEWAY_MAC=aa:bb:cc:dd:ee:ff\n' > "$CONFIG_FILE"

    unset CONFIG_HOME_GATEWAY_MAC
    load_config

    [ "$CONFIG_HOME_GATEWAY_MAC" = "aa:bb:cc:dd:ee:ff" ]
}

# Test: load_config reads LOG_LEVEL from config file
@test "load_config reads LOG_LEVEL from config file" {
    _source_fn trim_whitespace load_config
    mkdir -p "$CONFIG_DIR"
    printf 'LOG_LEVEL=debug\n' > "$CONFIG_FILE"

    unset CONFIG_LOG_LEVEL
    load_config

    [ "$CONFIG_LOG_LEVEL" = "debug" ]
}

# Test: load_config skips comment lines
@test "load_config skips comment lines" {
    _source_fn trim_whitespace load_config
    mkdir -p "$CONFIG_DIR"
    printf '# This is a comment\nHOME_NETWORK=172.16.0.0/12\n' > "$CONFIG_FILE"

    unset CONFIG_HOME_NETWORK
    load_config

    [ "$CONFIG_HOME_NETWORK" = "172.16.0.0/12" ]
}

# Test: load_config strips double quotes from values
@test "load_config strips double quotes from values" {
    _source_fn trim_whitespace load_config
    mkdir -p "$CONFIG_DIR"
    printf 'HOME_NETWORK="192.168.2.0/24"\n' > "$CONFIG_FILE"

    unset CONFIG_HOME_NETWORK
    load_config

    [ "$CONFIG_HOME_NETWORK" = "192.168.2.0/24" ]
}

# Test: load_config strips single quotes from values
@test "load_config strips single quotes from values" {
    _source_fn trim_whitespace load_config
    mkdir -p "$CONFIG_DIR"
    printf "HOME_NETWORK='192.168.3.0/24'\n" > "$CONFIG_FILE"

    unset CONFIG_HOME_NETWORK
    load_config

    [ "$CONFIG_HOME_NETWORK" = "192.168.3.0/24" ]
}

# Test: load_config does nothing when config file is absent
@test "load_config does nothing when config file is absent" {
    _source_fn trim_whitespace load_config
    # CONFIG_FILE is set in setup() but the file doesn't exist yet

    unset CONFIG_HOME_NETWORK
    load_config

    # Variable should remain unset
    [ -z "${CONFIG_HOME_NETWORK+x}" ] || [ -z "$CONFIG_HOME_NETWORK" ]
}

# Test: load_config reads OIDC_ENABLED from config file
@test "load_config reads OIDC_ENABLED from config file" {
    _source_fn trim_whitespace load_config
    mkdir -p "$CONFIG_DIR"
    printf 'OIDC_ENABLED=true\n' > "$CONFIG_FILE"

    unset CONFIG_OIDC_ENABLED
    load_config

    [ "$CONFIG_OIDC_ENABLED" = "true" ]
}

# Test: load_config reads TAILSCALE_AS_HOME from config file
@test "load_config reads TAILSCALE_AS_HOME from config file" {
    _source_fn trim_whitespace load_config
    mkdir -p "$CONFIG_DIR"
    printf 'TAILSCALE_AS_HOME=false\n' > "$CONFIG_FILE"

    unset CONFIG_TAILSCALE_AS_HOME
    load_config

    [ "$CONFIG_TAILSCALE_AS_HOME" = "false" ]
}

# ============================================================
# SSH host listing Tests
# ============================================================

@test "list_ssh_hosts reads Include files and skips wildcard hosts" {
    _source_fn trim_whitespace _list_ssh_hosts_from_file list_ssh_hosts
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh/conf.d"

    cat > "$HOME/.ssh/config" <<EOF
Host direct-host *.ignored
    HostName direct.example.com
Include ~/.ssh/conf.d/*.conf
EOF

    cat > "$HOME/.ssh/conf.d/extra.conf" <<EOF
Host included-host
    HostName included.example.com
EOF

    run list_ssh_hosts
    [ "$status" -eq 0 ]
    _assert_output_has "direct-host"
    _assert_output_has "included-host"
    _refute_output_has "ignored"
}

@test "list_ssh_hosts does not execute Include shell metacharacters" {
    _source_fn trim_whitespace _list_ssh_hosts_from_file list_ssh_hosts
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh/conf.d"
    local marker="$TEST_CONFIG_DIR/include-command-ran"

    printf 'Include ~/.ssh/conf.d/*.conf$(touch${IFS}%s)\nHost safe-host\n    HostName safe.example.com\n' \
        "$marker" > "$HOME/.ssh/config"

    cat > "$HOME/.ssh/conf.d/safe.conf" <<EOF
Host included-safe-host
    HostName included-safe.example.com
EOF

    run list_ssh_hosts
    [ "$status" -eq 0 ]
    [ ! -e "$marker" ]
    _assert_output_has "safe-host"
}

@test "smart-ssh --list-hosts prints expanded host aliases" {
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh/conf.d"

    cat > "$HOME/.ssh/config" <<EOF
Host base-host
    HostName base.example.com
Include ~/.ssh/conf.d/*.conf
EOF

    cat > "$HOME/.ssh/conf.d/dev.conf" <<EOF
Host dev-host
    HostName dev.example.com
EOF

    run "$SMART_SSH" --list-hosts
    [ "$status" -eq 0 ]
    _assert_output_has "base-host"
    _assert_output_has "dev-host"
}

# ============================================================
# resolve_hostname Tests
# ============================================================

# Helper: mock dir where unicast DNS answers nothing, so the OS resolver
# decides the outcome. `getent` is stubbed as an existing-but-empty command so
# the tests behave the same on Linux CI, where a real working getent would
# otherwise resolve the name itself.
# Usage: _make_resolver_mocks <dscacheutil body> [getent body]
_make_resolver_mocks() {
    local dscacheutil_body="$1"
    local getent_body="${2:-}"
    local mock_dir
    mock_dir=$(mktemp -d "$TEST_CONFIG_DIR/resolve_mock.XXXXXX")

    for cmd in host dig; do
        printf '#!/bin/bash\nexit 1\n' > "$mock_dir/$cmd"
        chmod +x "$mock_dir/$cmd"
    done

    # Real dscacheutil exits 0 with no output when the name does not resolve
    printf '#!/bin/bash\n%s\nexit 0\n' "$dscacheutil_body" > "$mock_dir/dscacheutil"
    printf '#!/bin/bash\n%s\nexit 0\n' "$getent_body" > "$mock_dir/getent"
    chmod +x "$mock_dir/dscacheutil" "$mock_dir/getent"

    echo "$mock_dir"
}

# Assert the mock dir is actually reachable and runnable. Without this the
# "OS resolver was not consulted" tests below pass just as well when the mocks
# never made it onto PATH — a green that proves nothing.
# Usage: _assert_mocks_live <mock_dir>
_assert_mocks_live() {
    local mock_dir="$1"
    for cmd in host dig getent dscacheutil; do
        [ -x "$mock_dir/$cmd" ]
        [ "$(PATH="$mock_dir:$PATH" command -v "$cmd")" = "$mock_dir/$cmd" ]
    done
}

# Test: mDNS/.local names resolve through the OS resolver on macOS, where
# host/dig return NXDOMAIN and getent does not exist.
# The fixture reproduces real dscacheutil output for a multi-homed host: two
# blank-line-separated records, IPv6 first, and loopback ahead of the routable
# address — the shape that makes a naive `head -1` return 127.0.0.1.
@test "resolve_hostname falls back to the OS resolver for .local names" {
    local mock_dir
    mock_dir=$(_make_resolver_mocks 'cat <<EOF
name: printer.local
ipv6_address: ::1
ipv6_address: fe80:1::1
ipv6_address: 2001:db8::1

name: printer.local
ip_address: 127.0.0.1
ip_address: 169.254.3.4
ip_address: 192.0.2.10
ip_address: 192.0.2.11
EOF')

    _source_fn resolve_hostname_via_os resolve_hostname
    PATH="$mock_dir:$PATH" run resolve_hostname "printer.local" system
    [ "$status" -eq 0 ]
    [ "$output" = "192.0.2.10" ]
}

# Test: an mDNS node advertising only IPv6 still counts as resolvable
@test "resolve_hostname returns an IPv6 address when that is all the name has" {
    local mock_dir
    mock_dir=$(_make_resolver_mocks 'cat <<EOF
name: v6only.local
ipv6_address: ::1
ipv6_address: fe80:1::1
ipv6_address: 2001:db8::1
EOF')

    _source_fn resolve_hostname_via_os resolve_hostname
    PATH="$mock_dir:$PATH" run resolve_hostname "v6only.local" system
    [ "$status" -eq 0 ]
    [ "$output" = "2001:db8::1" ]
}

# Test: a name whose every address is loopback (an /etc/hosts alias, say) is
# still reachable — the non-routable filter is a preference, not a rejection
@test "resolve_hostname keeps loopback when the name has nothing else" {
    local mock_dir
    mock_dir=$(_make_resolver_mocks 'cat <<EOF
name: localonly
ipv6_address: ::1

name: localonly
ip_address: 127.0.0.1
EOF')

    _source_fn resolve_hostname_via_os resolve_hostname
    PATH="$mock_dir:$PATH" run resolve_hostname "localonly" system
    [ "$status" -eq 0 ]
    [ "$output" = "127.0.0.1" ]
}

# Test: the Linux path. getent is the OS resolver there, and it is preferred
# over dscacheutil, which does not exist on Linux at all.
@test "resolve_hostname resolves via getent on Linux-shaped systems" {
    local mock_dir
    mock_dir=$(_make_resolver_mocks "echo 'ip_address: 198.51.100.9'" 'cat <<EOF
127.0.0.1 printer.local
192.0.2.10 printer.local
2001:db8::1 printer.local
EOF')

    _source_fn resolve_hostname_via_os resolve_hostname
    PATH="$mock_dir:$PATH" run resolve_hostname "printer.local" system
    [ "$status" -eq 0 ]
    [ "$output" = "192.0.2.10" ]
}

# Test: dns mode never reaches the OS resolver, not even when no DNS tool is
# installed and the alternative is no answer at all. For the caller that picks
# the credential, no answer IS the safe answer — so there is no name spelling
# (case, trailing dot, or otherwise) that can route around the tier.
@test "resolve_hostname never uses the OS resolver in dns mode" {
    local mock_dir
    mock_dir=$(_make_resolver_mocks "touch '$TEST_CONFIG_DIR/os_resolver_was_called'
echo 'ip_address: 100.64.0.1'" "touch '$TEST_CONFIG_DIR/os_resolver_was_called'
echo '100.64.0.1 spoofed'")
    rm -f "$mock_dir/host" "$mock_dir/dig"

    # PATH is replaced, not prepended, so the real host/dig cannot be found
    local bin_dir="$TEST_CONFIG_DIR/coreutils"
    mkdir -p "$bin_dir"
    for cmd in awk grep head printf cat sed cut touch; do
        local cmd_path
        cmd_path=$(command -v "$cmd") && ln -sf "$cmd_path" "$bin_dir/$cmd"
    done

    _source_fn resolve_hostname_via_os resolve_hostname

    # Positive control: the OS resolver mock answers when it is reached
    PATH="$mock_dir:$bin_dir" run resolve_hostname "printer.local" system
    [ "$status" -eq 0 ]
    [ "$output" = "100.64.0.1" ]
    [ -e "$TEST_CONFIG_DIR/os_resolver_was_called" ]
    rm -f "$TEST_CONFIG_DIR/os_resolver_was_called"

    local name
    for name in printer.local printer.LOCAL printer.local. printer.LOCAL. nas.example.com; do
        PATH="$mock_dir:$bin_dir" run resolve_hostname "$name"
        [ "$status" -eq 1 ]
        [ ! -e "$TEST_CONFIG_DIR/os_resolver_was_called" ]
    done
}

# Test: the OS resolver is a fallback, not a preference — a name unicast DNS
# can answer must never reach it
@test "resolve_hostname prefers DNS and does not consult the OS resolver" {
    local mock_dir
    mock_dir=$(_make_resolver_mocks "touch '$TEST_CONFIG_DIR/dscacheutil_was_called'
echo 'ip_address: 198.51.100.9'")
    printf '#!/bin/bash\necho "dns-host has address 192.0.2.20"\n' > "$mock_dir/host"
    chmod +x "$mock_dir/host"
    _assert_mocks_live "$mock_dir"

    _source_fn resolve_hostname_via_os resolve_hostname

    # Positive control: the OS resolver mock does answer when it is reached
    PATH="$mock_dir:$PATH" run resolve_hostname_via_os "dns-host"
    [ "$output" = "198.51.100.9" ]
    rm -f "$TEST_CONFIG_DIR/dscacheutil_was_called"

    PATH="$mock_dir:$PATH" run resolve_hostname "dns-host" system
    [ "$status" -eq 0 ]
    [ "$output" = "192.0.2.20" ]
    [ ! -e "$TEST_CONFIG_DIR/dscacheutil_was_called" ]
}

# Test: the default (trust-bearing) mode never accepts an mDNS answer, so a
# spoofed .local reply cannot reach the Tailscale home-network decision
@test "resolve_hostname ignores the OS resolver unless asked for it" {
    local mock_dir
    mock_dir=$(_make_resolver_mocks "touch '$TEST_CONFIG_DIR/dscacheutil_was_called'
echo 'ip_address: 100.64.0.1'")
    _assert_mocks_live "$mock_dir"

    _source_fn resolve_hostname_via_os resolve_hostname

    # Positive control: the same mocks DO yield the spoofed answer in system
    # mode, so the assertion below is about the tier, not about a dead fixture
    PATH="$mock_dir:$PATH" run resolve_hostname "spoofed.local" system
    [ "$status" -eq 0 ]
    [ "$output" = "100.64.0.1" ]
    [ -e "$TEST_CONFIG_DIR/dscacheutil_was_called" ]
    rm -f "$TEST_CONFIG_DIR/dscacheutil_was_called"

    PATH="$mock_dir:$PATH" run resolve_hostname "spoofed.local"
    [ "$status" -eq 1 ]
    [ ! -e "$TEST_CONFIG_DIR/dscacheutil_was_called" ]
}

# Test: resolver failure across every tool is reported as failure
@test "resolve_hostname returns 1 when no tool resolves the name" {
    local mock_dir
    mock_dir=$(_make_resolver_mocks '')
    _assert_mocks_live "$mock_dir"

    _source_fn resolve_hostname_via_os resolve_hostname
    PATH="$mock_dir:$PATH" run resolve_hostname "nowhere.invalid" system
    [ "$status" -eq 1 ]

    # The helper reports failure in its own right, not only by returning ""
    PATH="$mock_dir:$PATH" run resolve_hostname_via_os "nowhere.invalid"
    [ "$status" -eq 1 ]
}

# ============================================================
# check_ssh_config Tests
# ============================================================

# Test: check_ssh_config returns 0 for known host in SSH config
@test "check_ssh_config returns 0 when SSH config exists for hostname" {
    _source_fn trim_whitespace _list_ssh_hosts_from_file list_ssh_hosts check_ssh_config
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    printf 'Host test-known-host\n    HostName example.com\n    User testuser\n' \
        > "$HOME/.ssh/config"

    check_ssh_config "test-known-host" 2>/dev/null
    [ "$?" -eq 0 ]
}

# Test: check_ssh_config returns 1 for host missing from SSH config
@test "check_ssh_config returns 1 when hostname is missing from SSH config" {
    _source_fn trim_whitespace _list_ssh_hosts_from_file list_ssh_hosts \
        resolve_hostname check_ssh_config
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    printf 'Host configured-host\n    HostName example.com\n' > "$HOME/.ssh/config"

    # Force DNS lookup to fail so the test is deterministic
    resolve_hostname() { return 1; }

    ret=0; check_ssh_config "nonexistent-host-xyz" 2>/dev/null || ret=$?
    [ "$ret" -eq 1 ]
}

# Test: check_ssh_config outputs warning message on failure
@test "check_ssh_config outputs warning when host not found" {
    _source_fn trim_whitespace _list_ssh_hosts_from_file list_ssh_hosts \
        resolve_hostname check_ssh_config
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    printf 'Host configured-host\n    HostName example.com\n' > "$HOME/.ssh/config"

    resolve_hostname() { return 1; }

    run check_ssh_config "missing-host" 2>&1
    [ "$status" -eq 1 ]
    _assert_output_has "Warning"
    _assert_output_has "missing-host"
}

# Test: check_ssh_config accepts IP literal even without SSH config entry
@test "check_ssh_config returns 0 for IPv4 literal not in SSH config" {
    _source_fn trim_whitespace _list_ssh_hosts_from_file list_ssh_hosts \
        resolve_hostname log_debug check_ssh_config
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    printf 'Host configured-host\n    HostName example.com\n' > "$HOME/.ssh/config"

    check_ssh_config "127.0.0.1" 2>/dev/null
    [ "$?" -eq 0 ]
}

# Test: check_ssh_config falls back to DNS resolution for unconfigured hosts
@test "check_ssh_config returns 0 when hostname resolves via DNS" {
    _source_fn trim_whitespace _list_ssh_hosts_from_file list_ssh_hosts \
        resolve_hostname log_debug check_ssh_config
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"

    # Stub the resolver so the test does not depend on the host's DNS state
    resolve_hostname() { echo "192.0.2.1"; return 0; }

    check_ssh_config "ad-hoc-host" 2>/dev/null
    [ "$?" -eq 0 ]
}

# Test: a host that exists only in a config named with -F is configured, even
# though ~/.ssh/config has never heard of it. check_ssh_config runs before the
# Tailscale check, so rejecting it here ends the run before anything else looks.
@test "check_ssh_config accepts a host defined only in a -F config" {
    _source_fn trim_whitespace _list_ssh_hosts_from_file list_ssh_hosts \
        log_debug resolve_hostname_via_os resolve_hostname check_ssh_config
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"

    printf 'Host custom-only\n    HostName example.com\n' \
        > "$TEST_CONFIG_DIR/custom_config"

    # Nothing may resolve, so the -F block is the only thing that can pass it
    local mock_dir
    mock_dir=$(_make_resolver_mocks '')

    PATH="$mock_dir:$PATH" run check_ssh_config "custom-only" \
        -F "$TEST_CONFIG_DIR/custom_config"
    [ "$status" -eq 0 ]
}

# Test: the same host with a user@ prefix, which ssh -G strips
@test "check_ssh_config accepts a user@ host defined only in a -F config" {
    _source_fn trim_whitespace _list_ssh_hosts_from_file list_ssh_hosts \
        log_debug resolve_hostname_via_os resolve_hostname check_ssh_config
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"

    printf 'Host custom-only\n    HostName example.com\n' \
        > "$TEST_CONFIG_DIR/custom_config"

    local mock_dir
    mock_dir=$(_make_resolver_mocks '')

    PATH="$mock_dir:$PATH" run check_ssh_config "me@custom-only" \
        -F "$TEST_CONFIG_DIR/custom_config"
    [ "$status" -eq 0 ]
}

# Test: a -F config that does not mention the host still leaves it unknown —
# consulting ssh must not turn the check into an unconditional yes
@test "check_ssh_config still refuses a host absent from the -F config" {
    _source_fn trim_whitespace _list_ssh_hosts_from_file list_ssh_hosts \
        log_debug resolve_hostname_via_os resolve_hostname check_ssh_config
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"

    printf 'Host other-host\n    HostName example.com\n' \
        > "$TEST_CONFIG_DIR/custom_config"

    local mock_dir
    mock_dir=$(_make_resolver_mocks '')

    PATH="$mock_dir:$PATH" run check_ssh_config "custom-only" \
        -F "$TEST_CONFIG_DIR/custom_config"
    [ "$status" -eq 1 ]
    _assert_output_has "not found"
}

# Test: the security-key path must not let the caller's -F replace the
# temporary config. ssh takes the LAST -F, so leaving theirs in place would
# discard IdentitiesOnly/IdentityAgent and let an on-disk key be offered on an
# external network — the exact thing the security key exists to prevent.
@test "security key path drops the caller's -F and keeps its own config" {
    printf 'Host custom-only\n    HostName example.com\n    Port 2222\n    User custuser\n' \
        > "$TEST_CONFIG_DIR/custom_config"
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"
    touch "$SECURITY_KEY_PATH"

    run env HOME="$TEST_CONFIG_DIR" NO_COLOR=1 \
        SECURITY_KEY_PATH="$SECURITY_KEY_PATH" \
        "$SMART_SSH" --dry-run --security-key custom-only \
        -F "$TEST_CONFIG_DIR/custom_config"
    [ "$status" -eq 0 ]
    # Exactly one -F, and it is not the caller's
    [ "$(echo "$output" | grep -c -- '-F ')" -eq 1 ]
    _refute_output_has "-F $TEST_CONFIG_DIR/custom_config"
    # The caller's config still reached the connection, through ssh -G
    _assert_output_has "hostname example.com"
    _assert_output_has "port 2222"
    _assert_output_has "user custuser"
    # and the restrictions survived
    _assert_output_has "IdentitiesOnly yes"
    _assert_output_has "IdentityAgent none"
    _assert_output_has "IdentityFile $SECURITY_KEY_PATH"
}

# Test: options other than -F must survive. Stripping is meant to remove one
# thing; dropping the caller's -p or -v with it would be a silent regression
# that the -F assertions above cannot see.
@test "security key path keeps the caller's other options" {
    printf 'Host custom-only\n    HostName example.com\n' \
        > "$TEST_CONFIG_DIR/custom_config"
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"
    touch "$SECURITY_KEY_PATH"

    run env HOME="$TEST_CONFIG_DIR" NO_COLOR=1 \
        SECURITY_KEY_PATH="$SECURITY_KEY_PATH" \
        "$SMART_SSH" --dry-run --security-key custom-only \
        -F "$TEST_CONFIG_DIR/custom_config" -v -L 8080:localhost:80
    [ "$status" -eq 0 ]
    _assert_output_matches 'Would execute:.* -v .*-L 8080:localhost:80'
}

# Test: directives beyond HostName/User/Port must reach the temporary config.
# The previous allowlist copied a handful and silently dropped the rest, so a
# host needing ProxyCommand could not be reached at all from an external
# network, and host-key verification quietly changed for the others.
@test "security key path preserves connection and host-key directives" {
    printf 'Host rich\n    HostName example.com\n    Port 2222\n    User custuser\n    ProxyCommand /bin/nc %%h %%p\n    HostKeyAlias rich-alias\n    UserKnownHostsFile /dev/null\n    StrictHostKeyChecking no\n    RemoteForward 9000 localhost:9000\n    DynamicForward 1080\n    LocalForward 8080 localhost:80\n' \
        > "$TEST_CONFIG_DIR/rich_config"
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"
    touch "$SECURITY_KEY_PATH"

    run env HOME="$TEST_CONFIG_DIR" NO_COLOR=1 \
        SECURITY_KEY_PATH="$SECURITY_KEY_PATH" \
        "$SMART_SSH" --dry-run --security-key rich \
        -F "$TEST_CONFIG_DIR/rich_config"
    [ "$status" -eq 0 ]

    _assert_output_has "proxycommand /bin/nc %h %p"
    _assert_output_has "hostkeyalias rich-alias"
    _assert_output_has "userknownhostsfile /dev/null"
    _assert_output_has "stricthostkeychecking false"
    _assert_output_has "remoteforward 9000"
    _assert_output_has "dynamicforward 1080"
    _assert_output_has "localforward 8080"
    # and the security key still owns authentication
    _assert_output_has "IdentityFile $SECURITY_KEY_PATH"
    _assert_output_has "IdentitiesOnly yes"
    _assert_output_has "IdentityAgent none"
}

# Test: the generated config has to be a config ssh accepts. `ssh -G` prints a
# `host` line that is not a setting — indented or not it opens a new Host
# block — so copying its output wholesale must exclude it.
@test "security key path writes a config ssh can parse" {
    printf 'Host rich\n    HostName example.com\n    Port 2222\n    ProxyCommand /bin/nc %%h %%p\n' \
        > "$TEST_CONFIG_DIR/rich_config"
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"
    touch "$SECURITY_KEY_PATH"

    run env HOME="$TEST_CONFIG_DIR" NO_COLOR=1 \
        SECURITY_KEY_PATH="$SECURITY_KEY_PATH" \
        "$SMART_SSH" --dry-run --security-key rich \
        -F "$TEST_CONFIG_DIR/rich_config"
    [ "$status" -eq 0 ]

    # Recover the printed config and feed it back to ssh
    echo "$output" | sed -n '/Temporary SSH config:/,$p' | tail -n +2 | sed 's/^  //' \
        > "$TEST_CONFIG_DIR/generated.cfg"
    [ -s "$TEST_CONFIG_DIR/generated.cfg" ]
    run ssh -F "$TEST_CONFIG_DIR/generated.cfg" -G rich
    [ "$status" -eq 0 ]
    _assert_output_has "hostname example.com"
    _assert_output_has "port 2222"
    _assert_output_has "identityfile $SECURITY_KEY_PATH"
    # A stray `host` line would have started a new block and orphaned the rest
    _refute_output_has "hostname rich"
}

# Test: a HostName pointing at another Host alias. The stanza is assembled from
# two `ssh -G` runs, and ssh keeps the FIRST value of a setting, so the alias's
# own User/Port must precede the requested name's defaults. This is also the
# case where copying `ssh -G`'s `host` line would do damage: the two runs
# report different names, and the second would open a new Host block mid-stanza
# and orphan everything after it.
@test "security key path resolves a HostName alias without losing its settings" {
    printf 'Host front\n    HostName backend\n\nHost backend\n    HostName real.example.com\n    Port 2222\n    User backuser\n' \
        > "$TEST_CONFIG_DIR/alias_config"
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"
    touch "$SECURITY_KEY_PATH"

    run env HOME="$TEST_CONFIG_DIR" NO_COLOR=1 \
        SECURITY_KEY_PATH="$SECURITY_KEY_PATH" \
        "$SMART_SSH" --dry-run --security-key front \
        -F "$TEST_CONFIG_DIR/alias_config"
    [ "$status" -eq 0 ]

    # Feed the generated config back to ssh and ask what it would do
    echo "$output" | sed -n '/Temporary SSH config:/,$p' | tail -n +2 | sed 's/^  //' \
        > "$TEST_CONFIG_DIR/generated.cfg"
    run ssh -F "$TEST_CONFIG_DIR/generated.cfg" -G front
    [ "$status" -eq 0 ]
    _assert_output_has "hostname real.example.com"
    _assert_output_has "port 2222"
    _assert_output_has "user backuser"
}

# Test: the alias contributes its connection identity and nothing more. Copying
# it wholesale would place its DEFAULTS ahead of the requested host's explicit
# settings — ssh keeps the first value — so `StrictHostKeyChecking no` on the
# requested host would silently become the alias's default `ask`.
@test "security key path keeps the requested host's settings over alias defaults" {
    printf 'Host front
    HostName backend
    StrictHostKeyChecking no
    ProxyCommand /bin/nc %%h %%p

Host backend
    HostName real.example.com
    Port 2222
    User backuser
' \
        > "$TEST_CONFIG_DIR/alias_config"
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"
    touch "$SECURITY_KEY_PATH"

    run env HOME="$TEST_CONFIG_DIR" NO_COLOR=1 \
        SECURITY_KEY_PATH="$SECURITY_KEY_PATH" \
        "$SMART_SSH" --dry-run --security-key front \
        -F "$TEST_CONFIG_DIR/alias_config"
    [ "$status" -eq 0 ]

    echo "$output" | sed -n '/Temporary SSH config:/,$p' | tail -n +2 | sed 's/^  //' \
        > "$TEST_CONFIG_DIR/generated.cfg"
    run ssh -F "$TEST_CONFIG_DIR/generated.cfg" -G front
    [ "$status" -eq 0 ]
    # from the alias
    _assert_output_has "hostname real.example.com"
    _assert_output_has "port 2222"
    _assert_output_has "user backuser"
    # from the host that was actually asked for
    _assert_output_has "stricthostkeychecking false"
    _assert_output_has "proxycommand /bin/nc %h %p"
}

# Test: a key the user configured must not survive into the security-key
# stanza. Copied settings are written before the security key's own
# IdentityFile, and ssh tries identities in the order listed — so a leaked one
# would be offered first, which is the whole thing the security key prevents.
@test "security key path drops a configured IdentityFile" {
    printf 'Host withkey\n    HostName example.com\n    IdentityFile /nonexistent/user_ondisk_key\n' \
        > "$TEST_CONFIG_DIR/key_config"
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"
    touch "$SECURITY_KEY_PATH"

    run env HOME="$TEST_CONFIG_DIR" NO_COLOR=1 \
        SECURITY_KEY_PATH="$SECURITY_KEY_PATH" \
        "$SMART_SSH" --dry-run --security-key withkey \
        -F "$TEST_CONFIG_DIR/key_config"
    [ "$status" -eq 0 ]
    _refute_output_has "/nonexistent/user_ondisk_key"
    _assert_output_has "IdentityFile $SECURITY_KEY_PATH"
}

# Test: the OIDC path copies the same way
@test "OIDC path preserves connection and host-key directives" {
    command -v jq >/dev/null 2>&1 || skip "jq not available"
    command -v curl >/dev/null 2>&1 || skip "curl not available"

    printf 'Host rich\n    HostName example.com\n    Port 2222\n    ProxyCommand /bin/nc %%h %%p\n    HostKeyAlias rich-alias\n' \
        > "$TEST_CONFIG_DIR/rich_config"
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"

    local cert_dir="$TEST_CONFIG_DIR/oidc-certs"
    mkdir -p "$cert_dir"
    ssh-keygen -q -t ed25519 -N '' -f "$cert_dir/id_oidc" </dev/null
    ssh-keygen -q -s "$cert_dir/id_oidc" -I test -n testuser \
        -V +1h "$cert_dir/id_oidc.pub" </dev/null

    run env HOME="$TEST_CONFIG_DIR" NO_COLOR=1 \
        OIDC_ENABLED=true OIDC_CERT_DIR="$cert_dir" \
        OIDC_ISSUER=https://issuer.invalid OIDC_CLIENT_ID=test \
        OIDC_CA_URL=https://ca.invalid \
        "$SMART_SSH" --dry-run --oidc rich -F "$TEST_CONFIG_DIR/rich_config"
    [ "$status" -eq 0 ]

    _assert_output_has "proxycommand /bin/nc %h %p"
    _assert_output_has "hostkeyalias rich-alias"
    _assert_output_has "CertificateFile $cert_dir/id_oidc-cert.pub"
    _assert_output_has "IdentitiesOnly yes"
}

# Test: a ProxyJump that exists only in the caller's config. The proxy stanza is
# built from a second `ssh -G`, which needs the same config files or the jump
# host lands in the temporary config unresolved.
@test "security key path resolves a ProxyJump from the caller's config" {
    printf 'Host custom-only\n    HostName example.com\n    ProxyJump bastion\n\nHost bastion\n    HostName bastion.example.com\n    User jumper\n' \
        > "$TEST_CONFIG_DIR/custom_config"
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"
    touch "$SECURITY_KEY_PATH"

    run env HOME="$TEST_CONFIG_DIR" NO_COLOR=1 \
        SECURITY_KEY_PATH="$SECURITY_KEY_PATH" \
        "$SMART_SSH" --dry-run --security-key custom-only \
        -F "$TEST_CONFIG_DIR/custom_config"
    [ "$status" -eq 0 ]
    _assert_output_has "Host bastion"
    _assert_output_has "hostname bastion.example.com"
    _assert_output_has "user jumper"
}

# Test: the attached form. `-Fpath` is one argv entry, so a stripper that only
# recognises a separate `-F path` leaves it on the command line, where ssh
# still honours it as the last -F.
@test "security key path drops an attached -Fpath too" {
    printf 'Host custom-only\n    HostName example.com\n    Port 2222\n' \
        > "$TEST_CONFIG_DIR/custom_config"
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"
    touch "$SECURITY_KEY_PATH"

    run env HOME="$TEST_CONFIG_DIR" NO_COLOR=1 \
        SECURITY_KEY_PATH="$SECURITY_KEY_PATH" \
        "$SMART_SSH" --dry-run --security-key custom-only \
        "-F$TEST_CONFIG_DIR/custom_config"
    [ "$status" -eq 0 ]
    _refute_output_has "-F$TEST_CONFIG_DIR/custom_config"
    # and the caller's config still reached the temporary one
    _assert_output_has "hostname example.com"
    _assert_output_has "port 2222"
    _assert_output_has "IdentitiesOnly yes"
}

# Test: the same for the OIDC path, which builds its own temporary config too
@test "OIDC path drops the caller's -F and keeps its own config" {
    command -v jq >/dev/null 2>&1 || skip "jq not available"
    command -v curl >/dev/null 2>&1 || skip "curl not available"

    printf 'Host custom-only\n    HostName example.com\n    Port 2222\n' \
        > "$TEST_CONFIG_DIR/custom_config"
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"

    # A cached certificate the implementation will actually find: it looks for
    # id_oidc and id_oidc-cert.pub, and checks that the certificate's public
    # key matches the private key. Any other name leaves the run failing in the
    # device flow, long before the config-building code this test is about.
    local cert_dir="$TEST_CONFIG_DIR/oidc-certs"
    mkdir -p "$cert_dir"
    ssh-keygen -q -t ed25519 -N '' -f "$cert_dir/id_oidc" </dev/null
    ssh-keygen -q -s "$cert_dir/id_oidc" -I test -n testuser \
        -V +1h "$cert_dir/id_oidc.pub" </dev/null
    [ -f "$cert_dir/id_oidc-cert.pub" ]

    run env HOME="$TEST_CONFIG_DIR" NO_COLOR=1 \
        OIDC_ENABLED=true OIDC_CERT_DIR="$cert_dir" \
        OIDC_ISSUER=https://issuer.invalid OIDC_CLIENT_ID=test \
        OIDC_CA_URL=https://ca.invalid \
        "$SMART_SSH" --dry-run --oidc custom-only \
        -F "$TEST_CONFIG_DIR/custom_config"

    [ "$status" -eq 0 ]
    _assert_output_has "Would execute:"
    # Exactly one -F, and it is not the caller's
    [ "$(echo "$output" | grep -c -- '-F ')" -eq 1 ]
    _refute_output_has "-F $TEST_CONFIG_DIR/custom_config"
    # The caller's config reached the temporary one
    _assert_output_has "hostname example.com"
    _assert_output_has "port 2222"
    # and the OIDC identity restrictions survived
    _assert_output_has "IdentityFile $cert_dir/id_oidc"
    _assert_output_has "CertificateFile $cert_dir/id_oidc-cert.pub"
    _assert_output_has "IdentitiesOnly yes"
    _assert_output_has "IdentityAgent none"
}

# Test: end to end, the shape from the report
@test "smart-ssh connects to a host defined only in a -F config" {
    printf 'Host custom-only\n    HostName example.com\n' \
        > "$TEST_CONFIG_DIR/custom_config"
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"

    # Force the away path so the result does not depend on the network the
    # suite happens to run on
    touch "$SECURITY_KEY_PATH"
    run env HOME="$TEST_CONFIG_DIR" NO_COLOR=1 TAILSCALE_AS_HOME=false \
        SECURITY_KEY_PATH="$SECURITY_KEY_PATH" \
        "$SMART_SSH" --dry-run --security-key custom-only \
        -F "$TEST_CONFIG_DIR/custom_config"
    [ "$status" -eq 0 ]
    _refute_output_has "not found"
    _assert_output_has "Would execute:"
}

# Test: the reported bug at the level the user saw it — an mDNS-only host is
# accepted with no warning. Runs the real resolver, not a stub, so a
# regression in how check_ssh_config calls it is caught here.
@test "check_ssh_config accepts an mDNS-only host without warning" {
    _source_fn trim_whitespace _list_ssh_hosts_from_file list_ssh_hosts \
        log_debug resolve_hostname_via_os resolve_hostname check_ssh_config
    export HOME="$TEST_CONFIG_DIR"
    mkdir -p "$HOME/.ssh"
    : > "$HOME/.ssh/config"

    local mock_dir
    mock_dir=$(_make_resolver_mocks 'cat <<EOF
name: printer.local
ip_address: 192.0.2.10
EOF')

    PATH="$mock_dir:$PATH" run check_ssh_config "printer.local" 2>&1
    [ "$status" -eq 0 ]
    _refute_output_has "not found"
}
