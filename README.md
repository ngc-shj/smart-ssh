# smart-ssh

A local network-based SSH connection tool that automatically chooses between regular public key authentication (from home networks) and security key authentication (from external networks).

## Features

- 🏠 **Home detection**: Uses regular SSH keys when connected to trusted home networks
- 🔐 **Away mode**: Requires security key (FIDO2/WebAuthn) authentication from external networks
- 🌐 **Cross-platform**: Works on Linux, macOS, and WSL2
- ⚙️ **SSH config aware**: Properly handles `Include` directives and complex SSH configurations
- 📦 **Multiple servers**: Support for multiple servers with consistent naming patterns

## Security Model

- **Home networks**: Convenient access with regular public key authentication
- **External networks**: Enhanced security with mandatory security key (YubiKey, etc.) authentication
- **Server-side enforcement**: Actual security is enforced server-side based on source IP

## Installation

```bash
# Download the script
curl -O https://raw.githubusercontent.com/ngc-shj/smart-ssh/main/smart-ssh
chmod +x smart-ssh

# Move to PATH
sudo mv smart-ssh /usr/local/bin/
```

## Configuration

### 1. Configure Home Networks and Security Key

Edit the script and update the configuration:

```bash
HOME_NETWORK="${HOME_NETWORK:-192.168.11.0/24}"  # Default, can be overridden by env var
SECURITY_KEY_PATH="${SECURITY_KEY_PATH:-$HOME/.ssh/id_ed25519_sk}"  # Default, can be overridden by env var
```

You can also override using environment variables:

```bash
# Single network
export HOME_NETWORK="192.168.1.0/24"

# Multiple networks (comma-separated)
export HOME_NETWORK="192.168.1.0/24,10.0.0.0/24,172.16.0.0/12"

# Different security key
export SECURITY_KEY_PATH="$HOME/.ssh/id_ecdsa_sk"

# Per-command override
HOME_NETWORK="192.168.1.0/24,10.0.0.0/8" smart-ssh hostname
```

### 2. SSH Configuration

Create SSH host configurations with a single entry per server:

```ssh-config
# ~/.ssh/config

# Server configuration (single entry)
Host vps-tk1
    HostName vps-tk1.example.com
    User myuser
    Port 22
    IdentityFile ~/.ssh/id_ed25519
    PreferredAuthentications publickey

# Other servers
Host production-server
    HostName prod.company.com
    User deploy
    IdentityFile ~/.ssh/id_ed25519
```

Note: Security key will be used automatically when connecting from external networks using the `-i` option.

### 3. Generate SSH Keys

```bash
# Regular key for home use
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519

# Security key for away use (requires hardware key)
ssh-keygen -t ed25519-sk -f ~/.ssh/id_ed25519_sk
```

### 4. Server-side Configuration (Recommended)

For true security, configure your server to enforce the authentication method based on source IP:

```bash
# /etc/ssh/sshd_config

# Default: Security key required
PubkeyAuthentication yes
PubkeyAuthOptions touch-required

# Home IP: Regular public key allowed
Match Address YOUR_HOME_IP
    PubkeyAuthOptions none
```

## Usage

```bash
# Connect to a server (automatically detects home/away)
smart-ssh hostname

# Force security key authentication regardless of network
smart-ssh --security-key hostname
smart-ssh -s hostname

# Use different security key temporarily
SECURITY_KEY_PATH=~/.ssh/id_ecdsa_sk smart-ssh --security-key hostname

# Override home networks temporarily  
HOME_NETWORK="192.168.1.0/24,10.0.0.0/8" smart-ssh hostname

# Debug mode
smart-ssh --debug

# Help
smart-ssh --help
```

## Platform Support

| Platform | IP Detection Method |
|----------|---------------------|
| WSL2     | PowerShell `Get-NetIPAddress` |
| Linux    | `ip route` or `ifconfig` |
| macOS    | `route get default` + `ifconfig` |

## Example Workflow

1. **At home (192.168.1.x)**: Connects using regular SSH key (no touch required)
2. **At coffee shop (public IP)**: Connects using security key (YubiKey touch required)
3. **Force security key**: Use `--security-key` option to always use security key
4. **Unknown network**: Prompts user to manually choose authentication method

## Security Benefits

- **Convenience at home**: No need to touch security key for routine access from trusted networks
- **Strong security away**: Mandatory hardware authentication prevents key theft attacks from external networks
- **Phishing resistance**: Security keys provide cryptographic proof of server identity
- **Physical presence**: Touch requirement ensures physical access to the key

## Requirements

- SSH client with security key support (OpenSSH 8.2+)
- Hardware security key (YubiKey, etc.) for away connections

## Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Author

Created by NOGUCHI Shoji ([@ngc-shj](https://github.com/ngc-shj))

## License

MIT License - see [LICENSE](LICENSE) for details.
