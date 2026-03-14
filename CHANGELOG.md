# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
