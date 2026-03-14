# Coding Deviation Log: oidc-device-flow
Created: 2026-03-14

## Deviations from Plan

### D-01: `oidc_get_certificate()` generates an ephemeral key pair internally
- **Plan description**: The function is described as "ID token → CA に送信 → SSH証明書取得" with cached cert/key filenames `id_oidc-cert.pub` and `id_oidc`. The plan does not mention key generation as part of this function's responsibility.
- **Actual implementation**: The function generates a new ephemeral `ed25519` key pair via `ssh-keygen` into a temp file, sends the public key to the CA alongside the ID token, receives a signed certificate, then copies the ephemeral private key to the cache directory. The key generation step is an undocumented responsibility of this function.
- **Reason**: A CA certificate-signing workflow requires a public key to sign. The plan implicitly assumes a key exists, but the implementation makes key provisioning self-contained within `oidc_get_certificate()`.
- **Impact scope**: The function contract is broader than documented. Tests for `oidc_get_certificate()` must mock `ssh-keygen` in addition to `curl`. The cert and key files are always regenerated on each new certificate fetch (existing key is never reused).

### D-02: CA endpoint path is hardcoded to step-ca's `/1.0/ssh/sign`
- **Plan description**: "CA実装に依存しない汎用API方式" (CA-implementation-agnostic generic API mode). No specific URL path is mentioned.
- **Actual implementation**: The endpoint is constructed as `${OIDC_CA_URL%/}/1.0/ssh/sign`, which is the path specific to step-ca's API. There is no configuration key to override this suffix.
- **Reason**: The initial implementation targets step-ca as the reference CA. The plan's "汎用" claim was aspirational rather than prescriptive for the initial release.
- **Impact scope**: Users running a CA other than step-ca cannot use OIDC mode without patching the script. A future `OIDC_CA_ENDPOINT` config key would resolve this.

### D-03: `debug_info()` shows `(never shown)` for ID token instead of token length
- **Plan description**: "`--debug` 出力: ID token は表示しない（長さのみ表示）"
- **Actual implementation**: The debug output line is `echo "  ID token: (never shown)"`. The token length is never displayed.
- **Reason**: At the time `debug_info()` runs (before any connection attempt), `_OIDC_ID_TOKEN` is always empty. Displaying a length of 0 would be misleading. The implementation opts for a static message instead.
- **Impact scope**: Slightly less diagnostic value than planned, but safer. The plan's wording "長さのみ表示" was intended as an assurance that the token value is masked, not a strict UX requirement.

### D-04: `--oidc` does not override home network detection
- **Plan description**: "CLIオプション: ネットワーク判定・`OIDC_AUTH_MODE` 設定を両方オーバーライド"
- **Actual implementation**: `FORCE_OIDC=true` is set when `--oidc` is parsed, but `should_use_oidc()` (which checks `FORCE_OIDC`) is only called inside the `away` branch of `main()`. If the current network is detected as home, `ssh_from_home()` is called regardless of `--oidc`.
- **Reason**: The plan's architecture diagram explicitly places OIDC only in the away branch. The CLIオプション section's "ネットワーク判定オーバーライド" wording is contradicted by the architecture diagram. The implementation follows the architecture diagram.
- **Impact scope**: A user running `--oidc` from home will silently connect via regular public key auth. This may be surprising. If the intent was to force OIDC even at home, an explicit check for `FORCE_OIDC` before the home/away branch is needed.

### D-05: `FORCE_OIDC` has no default value initialization
- **Plan description**: The plan states `FORCE_OIDC=true` is "内部的に設定" when `--oidc` is used, implying it has a falsy default otherwise.
- **Actual implementation**: `FORCE_OIDC` is never initialized to `false` at the global scope. `should_use_oidc()` checks `[ "$FORCE_OIDC" = true ]`, which works correctly when unset (unset != "true"), but is inconsistent with how other flags like `force_security_key` and `dry_run` are initialized as `false` inside `main()`.
- **Reason**: Likely an oversight. The check `[ "$FORCE_OIDC" = true ]` is safe in bash for unset variables, so there is no functional bug.
- **Impact scope**: Minor code consistency issue. Could cause confusion if `FORCE_OIDC` is exported from the environment by a user.

### D-06: `oidc_poll_token()` sleep uses `_OIDC_POLL_INTERVAL_OVERRIDE` regardless of `slow_down` adjustment
- **Plan description**: "`slow_down` 時は `current_interval += 5`（最小5秒適用済みの値に加算）。テスト用に `_OIDC_POLL_INTERVAL_OVERRIDE` と `_OIDC_POLL_TIMEOUT_OVERRIDE` 環境変数でオーバーライド可能"
- **Actual implementation**: `slow_down` correctly increments `current_interval` by 5. However, the actual `sleep` call uses `local sleep_time="${_OIDC_POLL_INTERVAL_OVERRIDE:-$current_interval}"`, meaning when `_OIDC_POLL_INTERVAL_OVERRIDE` is set (e.g., in tests), the incremented `current_interval` from `slow_down` is bypassed entirely.
- **Reason**: The override mechanism prioritizes test controllability over faithfully simulating `slow_down` behaviour in tests.
- **Impact scope**: Tests using `_OIDC_POLL_INTERVAL_OVERRIDE` cannot verify that `slow_down` actually increases the sleep duration. The production path (no override) is unaffected.

### D-07: `ensure_oidc_cert_dir()` checks symlink on `OIDC_CERT_DIR` after creation, not before
- **Plan description**: "既存パスがシンボリックリンクでないことを `-L` で確認" — the description implies a pre-creation check on the existing path.
- **Actual implementation**: The symlink check on `OIDC_CERT_DIR` (`[ -L "$OIDC_CERT_DIR" ]`) is placed after the `mkdir` block (which only runs when `! -e`). If the directory already exists as a symlink, the `! -e` guard is false (symlinks pass `-e`), so `mkdir` is skipped and the symlink check below catches it. This is functionally correct but the ordering is: attempt-mkdir-if-absent → check-symlink → check-is-dir.
- **Reason**: The ordering reflects bash's natural flow. The result is identical to checking before creation because creation is skipped when the path exists.
- **Impact scope**: No functional difference. The symlink attack surface is closed correctly.

### D-08: `oidc_device_authorize()` uses return code 2 for malformed JSON, plan did not specify
- **Plan description**: The plan lists exit codes for `ssh_with_oidc()` (0/1/2/3) but does not explicitly specify the return code of `oidc_device_authorize()` for JSON parse failures.
- **Actual implementation**: Returns 2 (network/CA error class) for both network failures and malformed JSON responses from the device authorization endpoint.
- **Reason**: Malformed JSON from the authorization server is treated as a server-side error, consistent with how `oidc_discover()` handles the same condition.
- **Impact scope**: Consistent error classification. No unexpected fallback behavior since `ssh_with_oidc()` propagates `return 2` correctly.
