# smart-ssh

A local network-based SSH connection tool that automatically chooses between regular public key authentication (from home networks) and security key authentication (from external networks).

## Features

- 🏠 **Home detection**: Uses regular SSH keys when connected to trusted home networks
- 🔐 **Away mode**: Requires security key (FIDO2/WebAuthn) authentication from external networks
- 🌐 **Cross-platform**: Works on Linux, macOS, and WSL2
- ⚙️ **SSH config aware**: Properly handles `Include` directives and complex SSH configurations
- 📦 **Multiple servers**: Support for multiple servers with consistent naming patterns
- 🛡️ **IP-based detection**: Network-based detection for reliable home/away identification
- 🎨 **Color output**: Enhanced visibility with color-coded messages (respects `NO_COLOR`)
- 🧪 **Dry-run mode**: Preview authentication method without connecting
- ✅ **Input validation**: Robust error handling for IP addresses and CIDR formats

## Security Model

- **Home networks**: Convenient access with regular public key authentication from trusted IP ranges
- **External networks**: Enhanced security with mandatory security key (YubiKey, etc.) authentication from untrusted networks
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
Host production
    HostName production.example.com
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

# Copy public keys to your servers
ssh-copy-id -i ~/.ssh/id_ed25519.pub production
ssh-copy-id -i ~/.ssh/id_ed25519_sk.pub production
```

### 4. Server-side Configuration (Strongly Recommended)

For true security, configure your server to enforce authentication methods and key algorithms based on source IP:

```bash
# /etc/ssh/sshd_config.d/99-smart-ssh.conf

# Smart-SSH Security Key Configuration
# Match blocks are processed top-to-bottom, first match wins

# Trusted networks: Regular public key + security key algorithms
Match Address 192.168.1.0/24,10.0.0.0/8,127.0.0.1,::1
    PubkeyAcceptedAlgorithms ssh-ed25519,ecdsa-sha2-nistp256,sk-ssh-ed25519@openssh.com,sk-ecdsa-sha2-nistp256@openssh.com
    PubkeyAuthOptions none
    AuthenticationMethods publickey

# All other addresses: Security key algorithms ONLY
Match all
    PubkeyAcceptedAlgorithms sk-ssh-ed25519@openssh.com,sk-ecdsa-sha2-nistp256@openssh.com
    PubkeyAuthOptions touch-required
    AuthenticationMethods publickey
```

Apply the configuration:
```bash
sudo sshd -t  # Test configuration
sudo systemctl reload sshd  # Apply changes
```

**Important**: Update the IP addresses to match your actual home network and ISP ranges. Use `curl -4 ifconfig.co` to check your public IP and research the CIDR range.

## Usage

```bash
# Connect to a server (automatically detects home/away)
smart-ssh production

# Force security key authentication regardless of network
smart-ssh --security-key bastion
smart-ssh -s web-server

# Dry-run mode (preview what would be executed without connecting)
smart-ssh --dry-run production
smart-ssh -n staging

# Use different security key temporarily
SECURITY_KEY_PATH=~/.ssh/id_ecdsa_sk smart-ssh --security-key dev-server

# Override home networks temporarily
HOME_NETWORK="192.168.1.0/24,10.0.0.0/8" smart-ssh staging

# Disable color output
NO_COLOR=1 smart-ssh production

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
2. **At coffee shop (different IP range)**: Connects using security key (YubiKey touch required)
3. **Force security key**: Use `--security-key` option to always use security key
4. **Unknown network**: Prompts user to manually choose authentication method

### Real-world scenarios:
- `smart-ssh production` - Deploy to production server
- `smart-ssh dev-server` - Connect to development environment  
- `smart-ssh bastion` - Access jump host for internal network
- `smart-ssh web-server` - Manage web server

## Security Benefits

- **Convenience at home**: No need to touch security key for routine access from trusted networks
- **Strong security away**: Mandatory hardware authentication prevents key theft attacks from external networks
- **Algorithm enforcement**: Server-side algorithm restrictions prevent weak key attacks
- **Network-based detection**: IP-based detection is more reliable than other methods
- **Phishing resistance**: Security keys provide cryptographic proof of server identity
- **Physical presence**: Touch requirement ensures physical access to the key

## Requirements

- SSH client with security key support (OpenSSH 8.2+)
- Hardware security key (YubiKey, etc.) for away connections

## Author

Created by NOGUCHI Shoji ([@ngc-shj](https://github.com/ngc-shj))

## License

MIT License - see [LICENSE](LICENSE) for details.
