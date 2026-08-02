# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Tailscale host detection now asks the local daemon and nothing else. The CGNAT
  range / MagicDNS suffix / DNS-resolution heuristics are removed: each is
  supplied or forgeable by the network the security key exists to defend
  against, so acting on one used the on-disk key exactly where it must not be
  used. When the daemon cannot be asked, the connection is treated as external.
- A confirmed Tailscale connection is pinned to the address the daemon vouched
  for (`-o HostName=... -o HostKeyAlias=...`) instead of letting ssh resolve the
  name again through the system resolver. Detection evaluates the SSH options
  the connection will use, so a command-line `-o HostName=` is judged on its own
  target, and the pin precedes the caller's options so ssh honours it. A
  `HostKeyAlias` already set in the config is preserved.
- `jq` is now required for Tailscale host detection, which is on by default.
- A bare node label in `HostName` is no longer matched against the peer list;
  use the MagicDNS name or the tailnet address.

### Added

- `TAILSCALE_CLI_BUNDLE_PATH` (environment or config file) to locate the CLI
  when it is not on `PATH`, as with the macOS App Store build. It is executed
  only if root owns it.

### Fixed

- A host defined only in a config named with `-F` is no longer rejected with
  "SSH configuration not found" before the connection is attempted, and its
  `HostName` / `User` / `Port` / `ProxyJump` now reach the temporary config the
  security-key and OIDC paths build.
- A `-F` passed by the caller no longer replaces that temporary config. ssh
  honours the last `-F`, so on an external network the identity restrictions
  were being discarded and an ordinary on-disk key could be offered. The
  option is dropped from the final command — nothing is lost, since the
  temporary config is generated from `ssh -G` output that already merged it.
- The temporary config now carries every effective directive except the ones it
  exists to override. It previously copied a short allowlist, silently dropping
  `ProxyCommand`, `HostKeyAlias`, `UserKnownHostsFile`, `StrictHostKeyChecking`,
  `RemoteForward` and `DynamicForward` among others — changing how the host was
  verified, and leaving hosts that need `ProxyCommand` unreachable from an
  external network. When `HostName` names another `Host` alias, the alias
  supplies the destination, user and port, and the host that was asked for
  supplies everything else.
- Hosts resolvable only through the OS resolver — mDNS `.local` names and
  `/etc/hosts` entries on macOS, where `host`/`dig` answer NXDOMAIN and `getent`
  does not exist — no longer produce "SSH configuration for '...' not found".
- Address selection prefers a routable address over loopback, link-local, and
  APIPA, and falls back to IPv6 when a host advertises nothing else.

## [1.0.0] - 2026-03-15

### Added

- Tailscale host detection via `tailscale whois --json` CLI with CGNAT/MagicDNS fallback
- OIDC Device Flow authentication for SSH certificates (RFC 8628)
- Gateway MAC address detection for home network identification
- IP/CIDR-based home network detection (fallback)
- `--version` flag and VERSION variable (semver)
- `--dry-run` mode for previewing authentication method
- SSH option pass-through (`-v`, `-p`, `-L`, etc.)
- ProxyJump and HostName alias resolution in security key mode
- Input sanitization: hostname validation, verification_uri https check, OIDC_CERT_LIFETIME bounds
- Tab completion for Bash and Zsh
- XDG-compliant configuration file support
- GitHub Actions CI with ShellCheck and bats tests (Ubuntu + macOS)
- Makefile with release checksum generation
- SECURITY.md with vulnerability reporting policy
- Threat Model documentation in README
- OIDC Operational Guide in README
- Comprehensive test suite (51 bats tests)

### Security

- SSH hostname sanitization prevents injection via crafted ProxyJump/HostName values
- OIDC verification_uri validated for https:// scheme
- OIDC certificate lifetime bounded to 86400 seconds (24 hours)
- Temporary SSH config files created with restrictive permissions (umask 077)
- OIDC certificate directory protected against symlink attacks

[1.0.0]: https://github.com/ngc-shj/smart-ssh/releases/tag/v1.0.0
