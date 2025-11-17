# Bash completion for smart-ssh
# Install: Copy to /etc/bash_completion.d/ or source from ~/.bashrc
# Usage: source completions/smart-ssh.bash

# Get SSH hosts from config, respecting Include directives
_smart_ssh_get_hosts() {
    local config_file="${1:-$HOME/.ssh/config}"
    local hosts=""

    # Use ssh's native config parser to handle Include directives
    # ssh -G lists all configuration for a dummy host, including expanded config
    if command -v ssh >/dev/null 2>&1; then
        # Extract Host entries from the actual config file and included files
        # Parse the main config and any included configs
        hosts=$(awk '
            /^Include / {
                # Expand ~ to HOME directory
                include_path = $2
                gsub(/^~/, ENVIRON["HOME"], include_path)
                # Handle glob patterns
                cmd = "ls -1 " include_path " 2>/dev/null"
                while ((cmd | getline file) > 0) {
                    while ((getline line < file) > 0) {
                        if (line ~ /^Host /) {
                            split(line, parts)
                            for (i = 2; i <= length(parts); i++) {
                                print parts[i]
                            }
                        }
                    }
                    close(file)
                }
                close(cmd)
            }
            /^Host / {
                for (i = 2; i <= NF; i++) {
                    print $i
                }
            }
        ' "$config_file" 2>/dev/null | grep -v "[*?!]" | sort -u)
    fi

    echo "$hosts"
}

_smart_ssh_completion() {
    local cur prev opts hosts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Smart-ssh specific options
    local smart_ssh_opts="--security-key -s --dry-run -n --init-config --debug -d --help -h --"

    # Common SSH options for pass-through
    local ssh_opts="-v -p -L -R -D -i -o -F -J -W -N -T -f -q -V -4 -6"

    # Check if we've seen -- separator
    local seen_separator=0
    local hostname_idx=-1
    for ((i=1; i<COMP_CWORD; i++)); do
        if [[ "${COMP_WORDS[i]}" == "--" ]]; then
            seen_separator=1
        fi
        # First non-option argument is hostname
        if [[ "${COMP_WORDS[i]}" != -* ]] && [[ $hostname_idx -eq -1 ]]; then
            hostname_idx=$i
        fi
    done

    # If we've seen --, only complete SSH options or hostnames
    if [[ $seen_separator -eq 1 ]]; then
        if [[ ${cur} == -* ]]; then
            COMPREPLY=( $(compgen -W "${ssh_opts}" -- ${cur}) )
            return 0
        fi
        # After --, complete hostnames if no hostname yet
        if [[ $hostname_idx -eq -1 ]] || [[ $hostname_idx -ge $COMP_CWORD ]]; then
            if [[ -f ~/.ssh/config ]]; then
                hosts=$(_smart_ssh_get_hosts)
                COMPREPLY=( $(compgen -W "${hosts}" -- ${cur}) )
            fi
        fi
        return 0
    fi

    # Handle smart-ssh options
    case "${prev}" in
        --security-key|-s|--dry-run|-n)
            # These can be followed by hostname
            if [[ -f ~/.ssh/config ]]; then
                hosts=$(_smart_ssh_get_hosts)
                COMPREPLY=( $(compgen -W "${hosts}" -- ${cur}) )
            fi
            return 0
            ;;
        --init-config|--debug|-d|--help|-h)
            # These don't take arguments
            return 0
            ;;
        -i|-F)
            # SSH options that take file paths - complete files
            COMPREPLY=( $(compgen -f -- ${cur}) )
            return 0
            ;;
        -p|-L|-R|-D|-o|-J|-W)
            # SSH options that take other arguments - don't complete
            return 0
            ;;
    esac

    # If current word starts with -, complete with smart-ssh or SSH options
    if [[ ${cur} == -* ]]; then
        # If hostname already provided, suggest SSH options
        if [[ $hostname_idx -ne -1 ]] && [[ $hostname_idx -lt $COMP_CWORD ]]; then
            COMPREPLY=( $(compgen -W "${ssh_opts}" -- ${cur}) )
        else
            # Otherwise suggest smart-ssh options
            COMPREPLY=( $(compgen -W "${smart_ssh_opts}" -- ${cur}) )
        fi
        return 0
    fi

    # Complete hostnames from SSH config
    if [[ -f ~/.ssh/config ]]; then
        hosts=$(_smart_ssh_get_hosts)
        COMPREPLY=( $(compgen -W "${hosts}" -- ${cur}) )
    fi

    return 0
}

# Register the completion function
complete -F _smart_ssh_completion smart-ssh
