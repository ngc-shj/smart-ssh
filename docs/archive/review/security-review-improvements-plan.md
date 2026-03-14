# Plan: security-review-improvements

## Objective

Address all issues raised in the external security review to bring smart-ssh from "individual use" quality to "organization-ready" quality. This includes switching Tailscale detection to use `tailscale whois`, adding CI/CD, security policy, threat model documentation, OIDC operational guidance, and improving install instructions.

## Requirements

### Functional Requirements

1. **Tailscale detection via `tailscale whois`**: Replace IP range/DNS-based detection with `tailscale whois` CLI for more accurate and authoritative Tailscale node identification. Fall back to current CGNAT/MagicDNS heuristic when `tailscale` CLI is unavailable, with a log warning that detection is degraded.
2. **CI/CD**: Add GitHub Actions workflow for running bats tests on push/PR.
3. **Release management**: Add version string to script, CHANGELOG.md, and Makefile with checksum + GPG signature generation.
4. **Improved install instructions**: Add version-pinned install with hash verification in README.
5. **Gateway MAC / IP detection**: Keep as-is. Document in Threat Model that these are UX convenience, not security boundaries.

### Non-Functional Requirements

6. **SECURITY.md**: Add vulnerability reporting policy and supported versions.
7. **Threat model documentation**: Explicitly document that home detection (all methods: Tailscale, Gateway MAC, IP) is UX convenience, NOT a security boundary. Add a dedicated Threat Model section to README.
8. **OIDC operational guide**: Document CA prerequisites, client secret handling (recommend public clients, warn against storing secrets in config), certificate revocation/lifetime/cache clearing, audit logging, and client device requirements.
9. **Clean up patches directories**: Both patches (patches-feature, patches-security) are already applied in HEAD. Remove the directories.

## Technical Approach

### 1. Tailscale `whois` Integration (smart-ssh)

- Modify `is_tailscale_host()` to first try `tailscale whois --json <resolved_host>`
- **Detection specification**: `tailscale whois --json` returns node info. We check:
  1. JSON is well-formed (jq parses successfully)
  2. `.Node.ID` field exists and is non-zero (confirms the host is a known Tailscale node)
  3. This is sufficient because `tailscale whois` queries the local daemon which only returns info for nodes in the same tailnet or explicitly shared nodes.
- Handle error cases: CLI not found, daemon not running, permission denied, malformed JSON
- If `tailscale` CLI is unavailable or daemon is not running, fall back to current CGNAT/MagicDNS heuristic with `log_warn` indicating degraded detection
- Update config comment to reflect the new detection method

### 2. Security Hardening: Input Sanitization

- **ProxyJump/HostName sanitization**: Before writing to temp SSH config, validate that `proxy_jump`, `target_hostname`, and `alias_hostname` match `^[a-zA-Z0-9._:%-]+$` (no newlines, spaces, or wildcards). Reject with error if invalid.
- **`verification_uri` validation**: In `oidc_device_authorize()`, verify that `_OIDC_VERIFICATION_URI` starts with `https://`. Reject non-https URIs.
- **`OIDC_CERT_LIFETIME` validation**: Verify it is a positive integer ≤ 86400 (24 hours). Apply validation at config load time.
- **Apply to both `ssh_from_away()` and `ssh_with_oidc()`**: Ensure alias resolution logic is consistent across both paths.

### 3. GitHub Actions CI (.github/workflows/ci.yml)

- Run on push to main and PRs
- Matrix: ubuntu-latest, macos-latest
- Install bats-core, run `bats tests/`
- Add ShellCheck linting step with explicit exclusion list (determined by pre-running ShellCheck locally)
- Add `make release` + checksum verification step

### 4. SECURITY.md

- Vulnerability reporting via GitHub Security Advisories (private)
- Supported versions table
- Security response timeline expectations (target: 48h acknowledgment, 7d initial assessment)

### 5. Threat Model Section (README.md, README.ja.md)

- New "Threat Model & Trust Boundaries" section
- Explicitly state: **all client-side detection (Tailscale, Gateway MAC, IP) = UX convenience, server-side enforcement = security**
- Document: `tailscale whois` relies on local daemon trust and does not provide security guarantees beyond local privilege separation
- Document Gateway MAC limitations: MAC spoofing is trivial in adversarial environments
- Document IP/CIDR limitations: any network can use the same IP range
- Document what is protected (server-side enforcement) and what is not (client-side detection)

### 6. OIDC Operational Guide (README.md, README.ja.md)

- CA-side prerequisites (step-ca setup, OIDC provisioner config)
- Client secret handling: **strongly recommend public clients (no secret)**; if secret is necessary, warn that config file storage is insecure and recommend environment variable with restricted file permissions
- Certificate lifetime, revocation, and cache management (`OIDC_CERT_LIFETIME`, `rm ~/.ssh/oidc-certs/*`)
- Audit logging guidance (CA-side logging)
- Client device requirements

### 7. Install Instructions Improvement (README.md, README.ja.md)

- Add version-tagged install using GitHub releases URL: `https://github.com/ngc-shj/smart-ssh/releases/download/v{VERSION}/smart-ssh`
- Add sha256sum verification step using `smart-ssh.sha256` checksum file
- Rename current HEAD install to "Development Install" with warning

### 8. Release Infrastructure

- Add `VERSION` variable in smart-ssh script (semver format: `MAJOR.MINOR.PATCH`)
- Add `--version` flag to smart-ssh (exit code: 0)
- Add Makefile with `release` target that generates `smart-ssh.sha256` checksum file
- Document GPG signing process in Makefile comments (actual signing is manual)
- **Version**: Start with `1.0.0` as first formal release
- **Release assets**: `smart-ssh` (script), `smart-ssh.sha256` (checksum), optionally `smart-ssh.sha256.asc` (GPG signature)

### 9. Test Infrastructure Improvement

- Improve `_source_fn` helper: replace `sed` with `awk`-based brace-depth counting to handle nested functions correctly
- Add `declare -f` sanity check assertion for extracted functions

## Implementation Steps

1. Run ShellCheck on existing script locally, determine exclusion list
2. Remove `patches-feature/` and `patches-security/` directories (already applied in HEAD)
3. Add VERSION variable (`1.0.0`) and `--version` flag (exit 0) to smart-ssh script
4. Add input sanitization: ProxyJump/HostName validation, verification_uri https check, OIDC_CERT_LIFETIME validation
5. Modify `is_tailscale_host()` to use `tailscale whois` with robust error handling and fallback
6. Update Tailscale-related config comments and debug output
7. Improve `_source_fn` test helper (awk-based brace counting)
8. Update tests: Tailscale whois mock + fallback, --version, ssh_from_away (ProxyJump/alias/LocalForward), sanitization
9. Create SECURITY.md
10. Add Threat Model section to README.md and README.ja.md
11. Expand OIDC documentation in README.md and README.ja.md (with client secret warnings)
12. Improve install instructions in README.md and README.ja.md
13. Create .github/workflows/ci.yml with ShellCheck + bats + release verification
14. Create Makefile with release/checksum targets
15. Run full test suite to verify all changes

## Testing Strategy

- Existing bats tests must continue to pass
- Improve `_source_fn` to handle nested functions; add `declare -f` sanity check
- Add `is_tailscale_host()` integration tests with mock `tailscale` CLI:
  - Mock `tailscale whois` returning valid JSON → detected
  - Mock `tailscale whois` returning error → fallback to CGNAT/MagicDNS
  - Mock `tailscale` CLI not found → fallback with warning
  - Mock daemon not running → fallback
  - Mock malformed JSON → fallback
  - CLI absent + CGNAT IP → return 0
  - CLI absent + non-CGNAT IP → return 1
- Add `--version` test (exit 0, output contains version string)
- Add `ssh_from_away()` dry-run tests:
  - ProxyJump host → temp config contains proxy host stanza
  - HostName alias → resolved FQDN in temp config
  - LocalForward → all fields preserved
- Add sanitization tests (invalid hostname characters rejected)
- ShellCheck must pass with documented exclusions
- Verify GitHub Actions workflow syntax with `actionlint` if available

## Considerations & Constraints

- `tailscale whois` requires both the CLI and running daemon; graceful degradation is essential
- The fallback heuristic is explicitly documented as degraded detection in threat model, not a security bypass (home detection is UX, not security boundary)
- **Gateway MAC / IP detection kept as-is**: These are UX convenience features, not security boundaries. Security is enforced server-side. Threat Model documents limitations (MAC spoofing, IP range collision).
- README changes are bilingual (EN + JA); both must be updated consistently
- OIDC client_secret: strongly recommend public clients; if secret is used, warn about config file storage risks
- Version numbering: start with 1.0.0 as first formal release
- GPG signing is documented as a process but not automated (requires maintainer's key)
- Windows/WSL2 CI testing is out of scope
