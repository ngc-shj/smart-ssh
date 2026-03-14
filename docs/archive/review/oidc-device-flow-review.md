# Plan Review: oidc-device-flow

Date: 2026-03-14
Review round: 3

## Changes from Previous Round

Round 2 fixes applied to address all Round 1 + Round 2 findings:

- Fixed `prefer` mode fallback: only exit 2 (network/CA) allows fallback
- Fixed `auto` mode: no fallback (sk key doesn't exist, fallback is pointless)
- Origin validation: full origin (scheme://host:port) comparison
- `slow_down` timeout: treated as exit 3 (no fallback, Forced Downgrade prevention)
- `mktemp`: `umask 077 && mktemp` in subshell (TOCTOU elimination)
- Token passing: `printf | curl -H @-` via stdin (no cmdline exposure)
- Poll interval: client-side minimum 5 seconds enforced
- curl: `--fail --max-time 30 --connect-timeout 10` on all requests
- `validate_oidc_urls()`: called inside `ssh_with_oidc()` head (works with --oidc + OIDC_ENABLED=false)
- `ssh_with_oidc()`: full internal flow documented with pseudocode
- `--debug`: ID token not displayed (length only), CLIENT_ID masked
- Testing: added oidc_get_certificate() tests, curl existence check, exit code verification per function, poll timeout boundary tests, fallback matrix tests

## Round 1 Findings (all resolved)

- F1-F6, S1-S7, T1-T5: All addressed in Round 1 update

## Round 2 Findings (all resolved in this update)

### Functionality

- N1 [Major] prefer fallback mismatch → RESOLVED: exit 2 only
- N2 [Major] auto fallback to nonexistent sk key → RESOLVED: no fallback in auto
- N3 [Minor] validate_oidc_urls timing → RESOLVED: called in ssh_with_oidc head
- N4 [Minor] ssh_with_oidc internal flow → RESOLVED: pseudocode added

### Security

- S1-rev [Major] Origin scheme+port → RESOLVED: full origin comparison
- S3-rev [Major] slow_down forced downgrade → RESOLVED: timeout = exit 3
- S4-rev [Major] TOCTOU mktemp → RESOLVED: umask 077 subshell
- S5-rev [Major] curl -H token exposure → RESOLVED: printf | curl -H @-
- N1 [Major] Poll interval minimum → RESOLVED: 5s minimum enforced
- N2 [Major] curl timeouts → RESOLVED: --max-time 30 --connect-timeout 10
- S6-rev [Minor] Symlink check → Noted in plan (cert dir creation)
- N3 [Minor] ~ under sudo → Inherits existing SECURITY_KEY_PATH behavior
- N4 [Minor] --debug ID token → RESOLVED: length only, no content

### Testing

- N1 [Major] Poll timeout boundaries → RESOLVED: _OVERRIDE=0 test added
- N2 [Major] Exit code distinction → RESOLVED: per-function exit code verification
- N3 [Major] ssh-keygen cross-platform → RESOLVED: CI matrix + mock
- N4 [Minor] oidc_get_certificate tests → RESOLVED: added to strategy
- N5 [Minor] curl existence test → RESOLVED: added
- N6 [Minor] Debug mask targets → RESOLVED: specific targets listed

## Round 3 Findings (all resolved)

### Functionality

- F1 [Major] trap RETURN doesn't fire on SIGINT/SIGTERM → RESOLVED: trap 'rm -f' RETURN INT TERM
- F2 [Minor] expired_token error message indistinguishable → Noted: log_error will include specific cause
- F3 [Minor] slow_down interval calculation base unclear → RESOLVED: current_interval += 5 clarified

### Security

- S1 [Major] printf | curl bash builtin dependency → RESOLVED: plan explicitly notes #!/bin/bash guarantee
- S2 [Minor] Cached cert file permissions → RESOLVED: umask 077 for file creation
- S3 [Minor] curl --fail + response body validation → RESOLVED: PEM existence check added

### Testing

- T1 [Major] cmdline verification cross-platform → RESOLVED: bash builtin printf makes test unnecessary
- T2 [Minor] oidc_discover malformed JSON test → RESOLVED: added to test strategy
- T3 [Minor] Timeout boundary off-by-one → Noted: implementation detail
