function corscan
    argparse -n corscan 'o/origin=' 'auto' 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: corscan <target> [options]"
        echo "  -o <origin>   Custom origin to test (default: https://evil.com)"
        echo "  --auto        Non-interactive output"
        echo "Tests CORS misconfigurations."
        return
    end

    if test (count $argv) -lt 1
        echo "Error: target URL required"
        return 1
    end

    set target $argv[1]
    if not string match -qr '^https?://' "$target"
        set target "https://$target"
    end

    echo (set_color cyan)"==> CORSCAN: $target"(set_color normal)

    set evil "https://evil.com"
    if set -q _flag_origin; set evil $_flag_origin; end

    set findings

    function __test_origin -a origin label
        set headers (curl -sI -H "Origin: $origin" --max-time 10 "$target" 2>/dev/null)
        set acao (echo "$headers" | grep -oiP '^access-control-allow-origin:.*' | string replace -r '^[^:]+:\s*' '' | string trim)
        set acac (echo "$headers" | grep -oiP '^access-control-allow-credentials:.*' | string replace -r '^[^:]+:\s*' '' | string trim)
        if test -n "$acao"
            echo "  $label: $acao"
            if test -n "$acac"
                echo "         Credentials: $acac"
            end
            echo ""
            set -a findings "$label: ACAO=$acao ACAC=$acac"
        end
    end

    __test_origin "$evil" "Arbitrary origin ($evil)"
    __test_origin "null" "Null origin"
    __test_origin "$target" "Self origin (reflection)"

    # Check for wildcard
    set resp (curl -sI -H "Origin: $evil" --max-time 10 "$target" 2>/dev/null)
    set acao (echo "$resp" | grep -oiP '^access-control-allow-origin:\s*\*' | string trim)
    if test -n "$acao"
        echo (set_color red)"  [VULN] Wildcard ACAO with credentials possible"(set_color normal)
        set -a findings "WILDCARD_ORIGIN"
    end

    if test (count $findings) -eq 0
        echo (set_color green)"  No CORS misconfigurations detected"(set_color normal)
    else
        echo (set_color yellow)"  $(count $findings) CORS configuration(s) found:"(set_color normal)
        for f in $findings
            echo "    $f"
        end
        echo ""
        if not set -q _flag_auto
            echo -n "Launch attack on this target? [y/N] "
            read -l ans
            if test "$ans" = "y" -o "$ans" = "Y"
                attack "$target"
            end
        end
    end
end
