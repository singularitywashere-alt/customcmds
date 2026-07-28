function chatctl
    argparse -n chatctl 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: chatctl <command> [args]"
        echo ""
        echo "  on           Enable encryption"
        echo "  off          Disable encryption"
        echo "  status       Show encryption status"
        echo "  key <pw>     Set shared passphrase"
        echo "  encrypt <m>  Encrypt a message"
        echo "  decrypt <m>  Decrypt a message"
        echo "  send <m>     Send (encrypt if ON, plain if OFF)"
        echo "  watch        Watch clipboard for encrypted messages"
        echo ""
        echo "All you and your friend need is the same passphrase."
        echo "  chatctl key mysecret123"
        echo "  chatctl on"
        echo "  chatctl encrypt \"hello\""
        echo "  # paste result into Discord"
        echo "  # friend copies from Discord and runs:"
        echo "  chatctl decrypt \"<paste here>\""
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
