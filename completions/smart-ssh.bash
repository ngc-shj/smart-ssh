# Bash completion for smart-ssh
# Install: Copy to /etc/bash_completion.d/ or source from ~/.bashrc
# Usage: source completions/smart-ssh.bash

_smart_ssh_completion() {
    local cur prev opts hosts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Available options
    opts="--security-key -s --dry-run -n --init-config --debug -d --help -h"

    # If previous word is an option that doesn't take arguments
    case "${prev}" in
        --security-key|-s|--dry-run|-n|--init-config|--debug|-d|--help|-h)
            # For options that can be followed by hostname
            if [[ "${prev}" == "--security-key" ]] || [[ "${prev}" == "-s" ]] || \
               [[ "${prev}" == "--dry-run" ]] || [[ "${prev}" == "-n" ]]; then
                # Extract SSH hosts from config
                if [[ -f ~/.ssh/config ]]; then
                    hosts=$(grep "^Host " ~/.ssh/config 2>/dev/null | \
                           awk '{print $2}' | \
                           grep -v "[*?]" | \
                           sort -u)
                    COMPREPLY=( $(compgen -W "${hosts}" -- ${cur}) )
                fi
                return 0
            else
                # Options that don't take arguments, complete with nothing
                return 0
            fi
            ;;
    esac

    # If current word starts with -, complete with options
    if [[ ${cur} == -* ]] ; then
        COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        return 0
    fi

    # Extract SSH hosts from config file
    if [[ -f ~/.ssh/config ]]; then
        hosts=$(grep "^Host " ~/.ssh/config 2>/dev/null | \
               awk '{print $2}' | \
               grep -v "[*?]" | \
               sort -u)
        COMPREPLY=( $(compgen -W "${hosts}" -- ${cur}) )
    fi

    return 0
}

# Register the completion function
complete -F _smart_ssh_completion smart-ssh
