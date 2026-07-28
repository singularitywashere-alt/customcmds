function chatctl
    argparse -n chatctl 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: chatctl <command> [args]"
        echo ""
        echo "  on           Enable encryption (auto-encrypt on copy)"
        echo "  off          Disable encryption"
        echo "  status       Show encryption + daemon status"
        echo "  key <pw>     Set shared passphrase"
        echo "  daemon       Start background daemon (auto-clipboard)"
        echo "  stop         Stop the daemon"
        echo "  encrypt <m>  Encrypt a message manually"
        echo "  decrypt <m>  Decrypt a message manually"
        echo "  watch        Foreground clipboard watcher (debug)"
        echo ""
        echo "Quick start:"
        echo "  chatctl key mysecret123        # both you and friend set same key"
        echo "  chatctl on                     # enable encryption"
        echo "  chatctl daemon                 # start background processor"
        echo "  # Now copy text -> auto-encrypted in clipboard"
        echo "  # Copy encrypted text -> auto-decrypted in clipboard"
        return
    end

    if test (count $argv) -lt 1
        echo "Usage: chatctl <command> [args]"
        return 1
    end

    # Install Python script if missing
    set script "$HOME/.local/bin/chatctl"
    if not test -f $script
        set src "$HOME/.config/chatctl/chatctl"
        if test -f $src
            mkdir -p $HOME/.local/bin
            cp $src $script
            chmod +x $script
            set -U fish_user_paths $HOME/.local/bin $fish_user_paths 2>/dev/null
        end
    end

    if not test -f $script
        echo (set_color red)"chatctl not installed. Run: pinstall or reinstall"(set_color normal)
        return 1
    end

    python3 $script $argv
end
