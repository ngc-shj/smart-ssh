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
- ⚙️ **Configuration file**: XDG-compliant config file support with flexible priority system
- 🔧 **Tab completion**: Bash and Zsh completion for hostnames and options
- 🧪 **Testing**: Comprehensive test suite with bats
- 🔀 **SSH option pass-through**: Forward any SSH options (-v, -p, -L, etc.) to the underlying ssh command

## Security Model

- **Home networks**: Convenient access with regular public key authentication from trusted IP ranges
- **External networks**: Enhanced security with mandatory security key (YubiKey, etc.) authentication from untrusted networks
- **Server-side enforcement**: Actual security is enforced server-side based on source IP

## Installation

### Option 1: Quick Install (Recommended)

```bash
# Download and install to /usr/local/bin
curl -fsSL https://raw.githubusercontent.com/ngc-shj/smart-ssh/main/smart-ssh | sudo tee /usr/local/bin/smart-ssh > /dev/null
sudo chmod +x /usr/local/bin/smart-ssh

# Verify installation
smart-ssh --help
```

### Option 2: Manual Install

```bash
# Clone the repository
git clone https://github.com/ngc-shj/smart-ssh.git
cd smart-ssh

# Install the script
sudo cp smart-ssh /usr/local/bin/
sudo chmod +x /usr/local/bin/smart-ssh

# Install tab completions (optional)
# For Bash
sudo cp completions/smart-ssh.bash /etc/bash_completion.d/smart-ssh

# For Zsh (Homebrew users)
cp completions/_smart-ssh $(brew --prefix)/share/zsh/site-functions/_smart-ssh

# Verify installation
smart-ssh --help
```

### Option 3: User-local Install (No sudo required)

```bash
# Create local bin directory if it doesn't exist
mkdir -p ~/.local/bin

# Download and install
curl -fsSL https://raw.githubusercontent.com/ngc-shj/smart-ssh/main/smart-ssh -o ~/.local/bin/smart-ssh
chmod +x ~/.local/bin/smart-ssh

# Add to PATH if not already (add to ~/.bashrc or ~/.zshrc)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc  # or ~/.zshrc
source ~/.bashrc  # or source ~/.zshrc

# Verify installation
smart-ssh --help
```

## Configuration

smart-ssh supports three levels of configuration with the following priority:
**Environment variable > Configuration file > Default values**

### 1. Configuration File (Recommended)

Create a configuration file to persist your settings:

```bash
# Initialize default configuration file
smart-ssh --init-config

# Edit the configuration file
vi ~/.config/smart-ssh/config
```

Configuration file format (`~/.config/smart-ssh/config`):

```bash
# Home networks (comma-separated CIDR ranges)
HOME_NETWORK=192.168.1.0/24,10.0.0.0/24

# Security key path
SECURITY_KEY_PATH=~/.ssh/id_ed25519_sk

# Log level (debug, info, warn, error)
LOG_LEVEL=info
```

### 2. Environment Variables

Override settings temporarily using environment variables:

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

### 3. SSH Configuration

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

### 4. Generate SSH Keys

```bash
# Regular key for home use
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519

# Security key for away use (requires hardware key)
ssh-keygen -t ed25519-sk -f ~/.ssh/id_ed25519_sk

# Copy public keys to your servers
ssh-copy-id -i ~/.ssh/id_ed25519.pub production
ssh-copy-id -i ~/.ssh/id_ed25519_sk.pub production
```

### 5. Server-side Configuration (Strongly Recommended)

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
# First-time setup: Create configuration file
smart-ssh --init-config

# Connect to a server (automatically detects home/away)
smart-ssh production

# Pass SSH options (verbose mode)
smart-ssh production -v

# Use custom SSH port
smart-ssh production -p 2222

# Port forwarding with SSH options
smart-ssh production -L 8080:localhost:80

# Multiple SSH options
smart-ssh production -v -p 2222 -L 8080:localhost:80

# Use -- to clearly separate smart-ssh and SSH options
smart-ssh --dry-run -- production -v -p 2222

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

# Debug mode (show configuration and network info)
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

## Tab Completion

smart-ssh supports tab completion for bash and zsh shells.

### Bash Completion

```bash
# Install system-wide
sudo cp completions/smart-ssh.bash /etc/bash_completion.d/smart-ssh

# Or install for current user
mkdir -p ~/.local/share/bash-completion/completions
cp completions/smart-ssh.bash ~/.local/share/bash-completion/completions/smart-ssh

# Or source directly in ~/.bashrc
echo "source $(pwd)/completions/smart-ssh.bash" >> ~/.bashrc
source ~/.bashrc
```

### Zsh Completion

```bash
# For Homebrew users (recommended)
cp completions/_smart-ssh $(brew --prefix)/share/zsh/site-functions/_smart-ssh

# Or install to system directory
sudo cp completions/_smart-ssh /usr/local/share/zsh/site-functions/_smart-ssh

# Or add to your custom completion directory
mkdir -p ~/.zsh/completions
cp completions/_smart-ssh ~/.zsh/completions/
echo 'fpath=(~/.zsh/completions $fpath)' >> ~/.zshrc
echo 'autoload -Uz compinit && compinit' >> ~/.zshrc
source ~/.zshrc
```

**Features**:

- Complete hostnames from `~/.ssh/config` (including `Include` directives)
- Complete all command-line options
- Works with combined options (e.g., `-s hostname`)
- Context-aware completion: smart-ssh options before hostname, SSH options after

## Testing

smart-ssh includes a comprehensive test suite using [bats](https://github.com/bats-core/bats-core).

### Install bats

```bash
# macOS
brew install bats-core

# Linux (from source)
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

### Run Tests

```bash
# Run all tests
bats tests/test_smart_ssh.bats

# Run with verbose output
bats -t tests/test_smart_ssh.bats

# Run specific test
bats -f "validate IP" tests/test_smart_ssh.bats
```

**Test Coverage**:

- Configuration file creation and parsing
- IP address and CIDR validation
- Environment variable priority
- Command-line option handling
- Dry-run mode
- Debug mode
- Help and usage output

## Requirements

- SSH client with security key support (OpenSSH 8.2+)
- Hardware security key (YubiKey, etc.) for away connections
- Optional: bats-core for running tests

## Troubleshooting

### Network Detection Issues

**Problem**: smart-ssh cannot detect my IP address

**Solutions**:

1. Check your network connection:
   ```bash
   # macOS
   ifconfig | grep "inet "

   # Linux
   ip addr show

   # WSL2
   powershell.exe -Command "Get-NetIPAddress -AddressFamily IPv4"
   ```

2. Use debug mode to see what's happening:
   ```bash
   smart-ssh --debug
   ```

3. Manually specify your authentication method when prompted

**Problem**: Home network not detected even though I'm at home

**Solutions**:

1. Verify your current IP address is in the configured CIDR range:
   ```bash
   smart-ssh --debug
   # Check "Current IP" vs "HOME_NETWORK"
   ```

2. Update your HOME_NETWORK configuration:
   ```bash
   # Edit config file
   vi ~/.config/smart-ssh/config

   # Or use environment variable
   export HOME_NETWORK="192.168.1.0/24,10.0.0.0/8"
   ```

### Security Key Issues

**Problem**: "Security key file not found"

**Solutions**:

1. Generate a security key:
   ```bash
   ssh-keygen -t ed25519-sk -f ~/.ssh/id_ed25519_sk
   ```

2. Verify the key path:
   ```bash
   ls -l ~/.ssh/id_ed25519_sk*
   ```

3. Update SECURITY_KEY_PATH if needed:
   ```bash
   # In config file
   SECURITY_KEY_PATH=~/.ssh/id_ecdsa_sk

   # Or environment variable
   export SECURITY_KEY_PATH=~/.ssh/id_ecdsa_sk
   ```

**Problem**: "Please touch your YubiKey" but nothing happens

**Solutions**:

1. Ensure your security key is plugged in
2. Try unplugging and replugging the key
3. Check USB port permissions (Linux):
   ```bash
   sudo chmod a+rw /dev/usb/*
   ```
4. Verify the key works with ssh directly:
   ```bash
   ssh -i ~/.ssh/id_ed25519_sk hostname
   ```

### SSH Configuration Issues

**Problem**: "SSH configuration for 'hostname' not found"

**Solutions**:

1. Check your SSH config file exists:
   ```bash
   ls -l ~/.ssh/config
   ```

2. Verify the host entry exists:
   ```bash
   grep "^Host " ~/.ssh/config
   ```

3. Create a host entry:
   ```ssh-config
   Host production
       HostName prod.example.com
       User myuser
       IdentityFile ~/.ssh/id_ed25519
   ```

### Configuration File Issues

**Problem**: Configuration file not being read

**Solutions**:

1. Verify file location:
   ```bash
   ls -l ~/.config/smart-ssh/config
   ```

2. Check file syntax (no spaces around `=`):
   ```bash
   # Correct
   HOME_NETWORK=192.168.1.0/24

   # Incorrect
   HOME_NETWORK = 192.168.1.0/24
   ```

3. Recreate config file:
   ```bash
   smart-ssh --init-config
   ```

### Invalid CIDR Format Errors

**Problem**: "Error: Invalid CIDR format"

**Solutions**:

1. Use proper CIDR notation:
   ```bash
   # Correct
   HOME_NETWORK=192.168.1.0/24

   # Incorrect
   HOME_NETWORK=192.168.1
   HOME_NETWORK=192.168.1.0
   ```

2. Check mask bits are 0-32:
   ```bash
   # Valid
   10.0.0.0/8
   192.168.0.0/16
   192.168.1.0/24

   # Invalid
   192.168.1.0/33
   ```

### Dry-Run Mode

Use dry-run mode to test without connecting:
```bash
smart-ssh --dry-run production
```

This shows exactly what command would be executed.

### Enable Debug Logging

Set LOG_LEVEL to debug for verbose output:
```bash
# In config file
LOG_LEVEL=debug

# Or environment variable
LOG_LEVEL=debug smart-ssh production
```

### Still Having Issues?

1. Run debug mode and review all settings:
   ```bash
   smart-ssh --debug
   ```

2. Test with environment variable override:
   ```bash
   HOME_NETWORK="192.168.1.0/24" smart-ssh --dry-run production
   ```

3. Report issues at: <https://github.com/ngc-shj/smart-ssh/issues>

## Author

Created by NOGUCHI Shoji ([@ngc-shj](https://github.com/ngc-shj))

## License

MIT License - see [LICENSE](LICENSE) for details.
