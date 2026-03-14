# Code Review: oidc-device-flow

## Second Cycle

Date: 2026-03-14
Review rounds: 3

### Round 1 Findings

#### Functionality

- F1 [Critical] HTTP 4xx codes (non-400) not handled in oidc_poll_token — 401/403/404 fall through to JSON parsing instead of returning error → RESOLVED: added 4xx (non-400) check after 5xx check
- F2 [Critical] `curl_exit=$?` after `rm -f` captures rm's exit code, not curl's (both oidc_poll_token and oidc_get_certificate) → RESOLVED: moved rm -f after curl_exit capture
- F3 [Major] Certificate type detection pattern `[[ "$cert" != ssh-* ]]` is too broad — could match non-cert keys → RESOLVED: changed to regex `-cert-` pattern with validation
- F4 [Major] Missing error check for printf to body_file in oidc_get_certificate → RESOLVED: added || error handler with cleanup

#### Security

- S1 [Major] mktemp without umask 077 in ssh_from_away() — temp config file created with default umask → RESOLVED: added umask 077
- S2 [Major] Missing permission validation on existing ~/.ssh directory in ensure_oidc_cert_dir() → RESOLVED: added stat-based permission warning

#### Testing

- T1 [Critical] Missing test for empty OIDC_CA_URL in validate_oidc_urls → RESOLVED: added test
- T2 [Critical] Missing test for http:// OIDC_CA_URL in validate_oidc_urls → RESOLVED: added test
- T3 [Major] oidc_discover, oidc_device_authorize, oidc_poll_token, oidc_get_certificate, ensure_oidc_cert_dir have zero test coverage → PARTIALLY RESOLVED: added ensure_oidc_cert_dir tests (create + symlink rejection). Network-dependent functions (discover, authorize, poll, get_cert) require curl mocking — deferred to separate task
- T4 [Major] oidc_check_cached_cert has insufficient edge case testing → RESOLVED: added cert-only-no-key test case
- T5 [Minor] ssh_with_oidc integration test coverage missing → NOT FIXED: requires full OIDC mock infrastructure
- T6 [Minor] OIDC_CERT_LIFETIME validation missing → NOT FIXED: CA server validates; over-validation

### Round 2 Findings

#### Round 2 Functionality

- F1 [Major] poll_data_file mktemp/write error handling missing in oidc_poll_token → RESOLVED: added || error handlers for both mktemp and write

#### Round 2 Security

- S1 [Minor] OIDC_CERT_DIR existing dir permission check missing → RESOLVED: added stat-based warning
- S2 [Minor] `strings` command non-POSIX dependency → RESOLVED: replaced with `tr -dc '[:print:]'`
- S3 [Minor] poll_data_file write error handling → Same as F1, RESOLVED

#### Round 2 Testing

- T1 [Minor] Duplicate test (cert-only same as key-absent) → RESOLVED: replaced with ~/.ssh symlink and dir creation tests
- T2 [Minor] ~/.ssh symlink path untested → RESOLVED: added test
- T3 [Minor] ~/.ssh creation not verified in dir test → RESOLVED: added assertion

### Round 3 Findings

No findings. All Round 2 fixes verified as correct and complete.

### Resolution Status (Second Cycle)

#### Round 1

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

#### Round 2

| ID  | Severity | Problem                                | Action                                  | File:Line                 |
| --- | -------- | -------------------------------------- | --------------------------------------- | ------------------------- |
| F1  | Major    | poll_data_file error handling          | Added mktemp + write handlers           | smart-ssh:805-817         |
| S1  | Minor    | OIDC_CERT_DIR perms unchecked          | Added stat-based warning                | smart-ssh:1113-1119       |
| S2  | Minor    | strings non-POSIX                      | Replaced with tr -dc                    | smart-ssh:1002            |
| T1  | Minor    | Duplicate test                         | Replaced with symlink + dir test        | tests/test_smart_ssh.bats |
| T2  | Minor    | ~/.ssh symlink untested                | Added test                              | tests/test_smart_ssh.bats |
| T3  | Minor    | ~/.ssh creation not verified           | Added assertion                         | tests/test_smart_ssh.bats |

---

## Third Cycle (Post-simplification)

Date: 2026-03-14
Review rounds: 1

### Round 1 Findings

#### Functionality

- F1 [Major] POST body fields (device_code, client_id, client_secret) not URL-encoded in oidc_poll_token — breaks providers with special chars in opaque tokens → RESOLVED: added jq -Rr @uri encoding for each field
- F2 [Minor] ensure_secure_dir silently returns 0 when path is a regular file (not directory, not symlink) — compensating dead-code guard in ensure_oidc_cert_dir → RESOLVED: added else clause to ensure_secure_dir; removed dead code from ensure_oidc_cert_dir
- F3 [Minor] _OIDC_POLL_INTERVAL_OVERRIDE bypasses slow_down interval enforcement when set → RESOLVED: added documentation comment (test-only variable)

#### Security

- S1 [Minor] Same as F1 (URL encoding) → RESOLVED
- S2 [Minor] mktemp + rm -f + ssh-keygen TOCTOU window in oidc_get_certificate → RESOLVED: replaced with mktemp -d + fixed filename
- S3 [Minor] sed-based cert validity extraction breaks on "forever" validity → RESOLVED: added forever case check before date parsing
- S4 [Minor] Certificate format validation pattern too lenient → RESOLVED: added post-save ssh-keygen -L validation

#### Testing

- T1 [Major] --oidc integration test lacks OIDC_CERT_DIR isolation — false positive when cached cert exists → RESOLVED: added OIDC_CERT_DIR="$TEST_CONFIG_DIR/empty-oidc-certs"
- T2 [Major] Zero test coverage for oidc_discover, oidc_device_authorize, oidc_poll_token, oidc_get_certificate → NOT FIXED: requires curl mocking infrastructure — deferred to separate task
- T3 [Minor] oidc_check_cached_cert has no positive-path (return 0) test → NOT FIXED: requires generating real SSH certificates in test — deferred
- T4 [Minor] ensure_secure_dir "warn on wrong perms" branch untested → NOT FIXED: minor, deferred

### Resolution Status (Third Cycle)

| ID   | Severity | Problem                                  | Action                                             | File:Line                 |
| ---- | -------- | ---------------------------------------- | -------------------------------------------------- | ------------------------- |
| F1   | Major    | POST body fields not URL-encoded         | Added jq -Rr @uri encoding                        | smart-ssh:812-816         |
| F2   | Minor    | ensure_secure_dir accepts regular files  | Added else clause; removed dead code               | smart-ssh:1091-1094       |
| F3   | Minor    | _OIDC_POLL_INTERVAL_OVERRIDE undocumented| Added comment noting test-only usage               | smart-ssh:825-826         |
| S2   | Minor    | mktemp TOCTOU in oidc_get_certificate    | Replaced with mktemp -d + fixed filename           | smart-ssh:930-937         |
| S3   | Minor    | "forever" cert validity unhandled        | Added forever check before date parsing            | smart-ssh:1054-1058       |
| S4   | Minor    | Cert format validation too lenient       | Added post-save ssh-keygen -L validation           | smart-ssh:1032-1036       |
| T1   | Major    | --oidc test OIDC_CERT_DIR not isolated   | Added OIDC_CERT_DIR isolation to test env          | tests/test_smart_ssh.bats |
| T2   | Major    | Core OIDC functions untested             | Deferred: requires curl mocking infrastructure     | —                         |
| T3   | Minor    | oidc_check_cached_cert positive path     | Deferred: requires real SSH cert generation        | —                         |
| T4   | Minor    | ensure_secure_dir warn branch untested   | Deferred: minor                                    | —                         |

### Round 2 Findings

All Round 1 fixes verified as correct and complete by three expert agents.

New Minor findings:
- S5 [Minor] poll_data_file (containing client_secret) not cleaned on INT/TERM signal → RESOLVED: added `trap '_cleanup_poll' INT TERM`
- F4 [Minor] oidc_device_authorize does not send OIDC_CLIENT_SECRET (design constraint undocumented) → RESOLVED: added design rationale comment (RFC 8628 §3.1 makes it optional)

No Critical or Major findings. Review loop terminated.
