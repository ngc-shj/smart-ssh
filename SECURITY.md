# Security Policy

## Supported Versions

Only the latest release on the `main` branch receives security updates.

| Version | Supported |
| ------- | --------- |
| latest (main) | Yes |
| older releases | No |

## Scope

smart-ssh is a client-side UX tool that wraps the `ssh` command to simplify connection management. It does not implement cryptographic primitives, authentication protocols, or network security controls. All actual security enforcement (authentication, encryption, access control) is handled by the SSH daemon and infrastructure on the server side.

Vulnerabilities in scope include issues such as:

- Unintended exposure of credentials or private key paths through logs or temporary files
- Shell injection via crafted hostnames or config values
- Insecure handling of the SSH config file or temporary config files

Out-of-scope issues include weaknesses in the underlying `ssh` binary, OpenSSH, or server-side configuration.

## Reporting a Vulnerability

Please report security vulnerabilities privately via **GitHub Security Advisories**:

1. Navigate to [https://github.com/ngc-shj/smart-ssh/security/advisories/new](https://github.com/ngc-shj/smart-ssh/security/advisories/new)
2. Fill in a description of the issue, steps to reproduce, and potential impact
3. Submit the advisory — it will remain private until resolved

Do not open a public GitHub issue for security vulnerabilities.

## Response Timeline

| Milestone | Target |
| --------- | ------ |
| Acknowledgment | Within 48 hours of report |
| Initial assessment | Within 7 days of report |
| Fix or mitigation | Best effort, communicated via the advisory |

After a fix is released, a public disclosure will be coordinated with the reporter.
