# Code Review: security-review-improvements

Date: 2026-03-15T00:00:00+09:00
Review rounds: 1

## Changes from Previous Round

Initial review

## Functionality Findings

### F1 [Minor] validate_ssh_hostname % character intent — Skipped (comment only)
### F2 [Minor] Multi-hop ProxyJump causes silent rejection — **Resolved**
- Action: Added explicit error message for comma-separated ProxyJump values
- Modified file: smart-ssh (validate_ssh_hostname)

### F3 [Minor] _source_fn brace counter string context — Skipped (known limitation)

## Security Findings

### S1 [Major] $hostname not validated before temp config write — **Resolved**
- Action: Added validate_ssh_hostname("$hostname") at top of ssh_from_away() and ssh_with_oidc()
- Modified file: smart-ssh

### S2 [Minor] ssh_with_oidc() missing alias resolution — Deferred (D3 in deviation log)
### S3 [Minor] validate_oidc_cert_lifetime logic clarity — **Resolved**
- Action: Split compound expression into sequential checks, removed 2>/dev/null suppression
- Modified file: smart-ssh (validate_oidc_cert_lifetime)

### S4 [Minor] jq parse failure diagnostic gap — **Resolved**
- Action: Added log_debug for jq parse failure path in is_tailscale_host()
- Modified file: smart-ssh

## Testing Findings

### T1 [Major] dry-run test overwrites real ~/.ssh/config — **Resolved**
- Action: Set HOME="$TEST_CONFIG_DIR" to isolate test from real user files
- Modified file: tests/test_smart_ssh.bats

### T2 [Minor] PATH restriction in mock tests — Skipped (intentional design)
### T3 [Minor] rm before assertion in mock tests — **Resolved**
- Action: Moved mock_dir under TEST_CONFIG_DIR for automatic teardown cleanup, removed explicit rm calls
- Modified file: tests/test_smart_ssh.bats

## Resolution Status

All Critical and Major findings resolved. 3 Minor findings skipped with rationale.
Tests: 51/51 passing. ShellCheck: clean (with documented exclusions).
