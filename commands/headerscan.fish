function headerscan
    argparse -n headerscan 'auto' 'attack' 'v/verbose' 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: headerscan <target> [options]"
        echo "  --auto     Non-interactive, JSON output"
        echo "  --attack   Launch attack on target"
        echo "  -v         Verbose (show all headers)"
        echo "Scans security headers and rates them."
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

    set resp (curl -sI -L --max-time 10 "$target" 2>/dev/null)
    if test -z "$resp"
        echo (set_color red)"  Failed to reach target"(set_color normal)
        return 1
    end

    echo (set_color cyan)"==> HEADERSCAN: $target"(set_color normal)

    # Extract headers (case-insensitive)
    set hsts (echo "$resp" | grep -oiP '^strict-transport-security:.*' | string replace -r '^[^:]+:\s*' '' | string trim)
    set csp (echo "$resp" | grep -oiP '^content-security-policy:.*' | string replace -r '^[^:]+:\s*' '' | string trim)
    set xfo (echo "$resp" | grep -oiP '^x-frame-options:.*' | string replace -r '^[^:]+:\s*' '' | string trim)
    set xcto (echo "$resp" | grep -oiP '^x-content-type-options:.*' | string replace -r '^[^:]+:\s*' '' | string trim)
    set rp (echo "$resp" | grep -oiP '^referrer-policy:.*' | string replace -r '^[^:]+:\s*' '' | string trim)
    set pp (echo "$resp" | grep -oiP '^permissions-policy:.*' | string replace -r '^[^:]+:\s*' '' | string trim)
    set cors (echo "$resp" | grep -oiP '^access-control-allow-origin:.*' | string replace -r '^[^:]+:\s*' '' | string trim)
    set cookies (echo "$resp" | grep -oiP '^set-cookie:.*' | string replace -r '^[^:]+:\s*' '' | string trim)
    set server (echo "$resp" | grep -oiP '^server:.*' | string replace -r '^[^:]+:\s*' '' | string trim)
    set xp (echo "$resp" | grep -oiP '^x-xss-protection:.*' | string replace -r '^[^:]+:\s*' '' | string trim)

    set score 0
    set max 9

    function __check -a name value pass_msg fail_msg
        if test -n "$value"
            echo (set_color green)"  [+] $name: $value"(set_color normal)
            set -g score (math $score + 1)
        else
            echo (set_color red)"  [-] $name: $fail_msg"(set_color normal)
        end
    end

    __check "HSTS" "$hsts" "" "Missing — enable Strict-Transport-Security"
    __check "CSP" "$csp" "" "Missing — set Content-Security-Policy"
    __check "X-Frame-Options" "$xfo" "" "Missing — set X-Frame-Options (DENY or SAMEORIGIN)"
    __check "X-Content-Type-Options" "$xcto" "" "Missing — set X-Content-Type-Options: nosniff"
    __check "Referrer-Policy" "$rp" "" "Missing — set Referrer-Policy"
    __check "Permissions-Policy" "$pp" "" "Missing — set Permissions-Policy"
    __check "X-XSS-Protection" "$xp" "" "Deprecated but good to have"

    if test -n "$cors"
        if test "$cors" = "*"
            echo (set_color yellow)"  [!] CORS: Wildcard origin ($cors)"(set_color normal)
            set score (math $score + 0)
        else
            echo (set_color green)"  [+] CORS: $cors"(set_color normal)
            set score (math $score + 1)
        end
    else
        echo (set_color green)"  [+] CORS: Not set (default deny)"(set_color normal)
        set score (math $score + 1)
    end

    if test -n "$cookies"
        set c 0
        for ck in $cookies
            set c (math $c + 1)
            set has_secure 0; set has_httponly 0; set has_samesite 0
            if string match -qir 'secure' "$ck"; set has_secure 1; end
            if string match -qir 'httponly' "$ck"; set has_httponly 1; end
            if string match -qir 'samesite' "$ck"; set has_samesite 1; end
            set missing ""
            if test "$has_secure" -eq 0; set missing "$missing Secure"; end
            if test "$has_httponly" -eq 0; set missing "$missing HttpOnly"; end
            if test "$has_samesite" -eq 0; set missing "$missing SameSite"; end
            if test -n "$missing"
                echo (set_color yellow)"  [!] Cookie #$c missing:$missing"(set_color normal)
            else
                echo (set_color green)"  [+] Cookie #$c: Secure + HttpOnly + SameSite"(set_color normal)
            end
        end
    end

    if test -n "$server"
        echo (set_color yellow)"  [!] Server header leaks: $server"(set_color normal)
    end

    echo ""
    set pct (math "round($score * 100 / $max)")
    if test $pct -ge 80
        set color (set_color green)
    else if test $pct -ge 50
        set color (set_color yellow)
    else
        set color (set_color red)
    end
    echo "  Security score: $color$score/$max ($pct%)"(set_color normal)

    if set -q _flag_auto
        echo $resp | grep -oiP '^(?:strict-transport-security|content-security-policy|x-frame-options|x-content-type-options|referrer-policy|permissions-policy|access-control-allow-origin|server):'
    end

    if set -q _flag_attack
        attack "$target"
    end
end
