# Code Review: oidc-device-flow (Second Cycle)

Date: 2026-03-14
Review rounds: 3

## Round 1 Findings

### Functionality

- F1 [Critical] HTTP 4xx codes (non-400) not handled in oidc_poll_token — 401/403/404 fall through to JSON parsing instead of returning error → RESOLVED: added 4xx (non-400) check after 5xx check
- F2 [Critical] `curl_exit=$?` after `rm -f` captures rm's exit code, not curl's (both oidc_poll_token and oidc_get_certificate) → RESOLVED: moved rm -f after curl_exit capture
- F3 [Major] Certificate type detection pattern `[[ "$cert" != ssh-* ]]` is too broad — could match non-cert keys → RESOLVED: changed to regex `-cert-` pattern with validation
- F4 [Major] Missing error check for printf to body_file in oidc_get_certificate → RESOLVED: added || error handler with cleanup

### Security

- S1 [Major] mktemp without umask 077 in ssh_from_away() — temp config file created with default umask → RESOLVED: added umask 077
- S2 [Major] Missing permission validation on existing ~/.ssh directory in ensure_oidc_cert_dir() → RESOLVED: added stat-based permission warning

### Testing

- T1 [Critical] Missing test for empty OIDC_CA_URL in validate_oidc_urls → RESOLVED: added test
- T2 [Critical] Missing test for http:// OIDC_CA_URL in validate_oidc_urls → RESOLVED: added test
- T3 [Major] oidc_discover, oidc_device_authorize, oidc_poll_token, oidc_get_certificate, ensure_oidc_cert_dir have zero test coverage → PARTIALLY RESOLVED: added ensure_oidc_cert_dir tests (create + symlink rejection). Network-dependent functions (discover, authorize, poll, get_cert) require curl mocking — deferred to separate task
- T4 [Major] oidc_check_cached_cert has insufficient edge case testing → RESOLVED: added cert-only-no-key test case
- T5 [Minor] ssh_with_oidc integration test coverage missing → NOT FIXED: requires full OIDC mock infrastructure
- T6 [Minor] OIDC_CERT_LIFETIME validation missing → NOT FIXED: CA server validates; over-validation

## Round 2 Findings

### Round 2 Functionality

- F1 [Major] poll_data_file mktemp/write error handling missing in oidc_poll_token → RESOLVED: added || error handlers for both mktemp and write

### Round 2 Security

- S1 [Minor] OIDC_CERT_DIR existing dir permission check missing → RESOLVED: added stat-based warning
- S2 [Minor] `strings` command non-POSIX dependency → RESOLVED: replaced with `tr -dc '[:print:]'`
- S3 [Minor] poll_data_file write error handling → Same as F1, RESOLVED

### Round 2 Testing

- T1 [Minor] Duplicate test (cert-only same as key-absent) → RESOLVED: replaced with ~/.ssh symlink and dir creation tests
- T2 [Minor] ~/.ssh symlink path untested → RESOLVED: added test
- T3 [Minor] ~/.ssh creation not verified in dir test → RESOLVED: added assertion

## Round 3 Findings

No findings. All Round 2 fixes verified as correct and complete.

## Resolution Status

### Round 1

| ID  | Severity | Problem                                | Action                                  | File:Line                 |
| --- | -------- | -------------------------------------- | --------------------------------------- | ------------------------- |
| F1  | Critical | HTTP 4xx (non-400) unhandled in poll   | Added 4xx check after 5xx check         | smart-ssh:845-850         |
| F2  | Critical | curl_exit=$? captures rm exit code     | Moved rm -f after curl_exit capture     | smart-ssh:820-821 941-942 |
| F3  | Major    | Cert type detection too broad          | Changed to -cert- regex with validation | smart-ssh:983-994         |
| F4  | Major    | printf to body_file unchecked          | Added error handler                     | smart-ssh:937-940         |
| S1  | Major    | mktemp without umask 077               | Added umask 077 subshell                | smart-ssh:1271            |
| S2  | Major    | No permission check on existing ~/.ssh | Added stat-based permission warning     | smart-ssh:1070-1077       |
| T1  | Critical | No test for empty OIDC_CA_URL          | Added test                              | tests/test_smart_ssh.bats |
| T2  | Critical | No test for http:// OIDC_CA_URL        | Added test                              | tests/test_smart_ssh.bats |
| T3  | Major    | ensure_oidc_cert_dir untested          | Added create + symlink tests            | tests/test_smart_ssh.bats |
| T4  | Major    | oidc_check_cached_cert edge cases      | Added cert-only test                    | tests/test_smart_ssh.bats |

### Round 2

| ID  | Severity | Problem                                | Action                                  | File:Line                 |
| --- | -------- | -------------------------------------- | --------------------------------------- | ------------------------- |
| F1  | Major    | poll_data_file error handling          | Added mktemp + write handlers           | smart-ssh:805-817         |
| S1  | Minor    | OIDC_CERT_DIR perms unchecked          | Added stat-based warning                | smart-ssh:1113-1119       |
| S2  | Minor    | strings non-POSIX                      | Replaced with tr -dc                    | smart-ssh:1002            |
| T1  | Minor    | Duplicate test                         | Replaced with symlink + dir test        | tests/test_smart_ssh.bats |
| T2  | Minor    | ~/.ssh symlink untested                | Added test                              | tests/test_smart_ssh.bats |
| T3  | Minor    | ~/.ssh creation not verified           | Added assertion                         | tests/test_smart_ssh.bats |
