# Code Review: oidc-device-flow

Date: 2026-03-14
Review rounds: 1

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

## Resolution Status

### Round 1

| ID  | Severity | Problem                                  | Action                                  | File:Line                  |
| --- | -------- | ---------------------------------------- | --------------------------------------- | -------------------------- |
| F1  | Critical | HTTP 4xx (non-400) unhandled in poll     | Added 4xx check after 5xx check         | smart-ssh:845-850          |
| F2  | Critical | curl_exit=$? captures rm exit code       | Moved rm -f after curl_exit capture     | smart-ssh:820-821 941-942  |
| F3  | Major    | Cert type detection too broad            | Changed to -cert- regex with validation | smart-ssh:983-994          |
| F4  | Major    | printf to body_file unchecked            | Added error handler                     | smart-ssh:937-940          |
| S1  | Major    | mktemp without umask 077                 | Added umask 077 subshell                | smart-ssh:1271             |
| S2  | Major    | No permission check on existing ~/.ssh   | Added stat-based permission warning     | smart-ssh:1070-1077        |
| T1  | Critical | No test for empty OIDC_CA_URL            | Added test                              | tests/test_smart_ssh.bats  |
| T2  | Critical | No test for http:// OIDC_CA_URL          | Added test                              | tests/test_smart_ssh.bats  |
| T3  | Major    | ensure_oidc_cert_dir untested            | Added create + symlink tests            | tests/test_smart_ssh.bats  |
| T4  | Major    | oidc_check_cached_cert edge cases        | Added cert-only test                    | tests/test_smart_ssh.bats  |
