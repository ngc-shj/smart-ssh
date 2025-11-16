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
