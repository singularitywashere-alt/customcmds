function webscan
    argparse -n webscan 'w/wordlist=' 'l/limit=' 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: webscan <target> [-w <wordlist>] [-l <limit>]"
        echo ""
        echo "Options:"
        echo "  -w <file>    Custom wordlist (one path per line)"
        echo "  -l <limit>   Max paths to scan (default: 200)"
        echo ""
        echo "Examples:"
        echo "  webscan https://example.com"
        echo "  webscan https://example.com -w mypaths.txt"
        echo "  webscan https://example.com -l 500"
        return
    end

    if test (count $argv) -lt 1
        echo "Usage: webscan <target> [-w <wordlist>] [-l <limit>]"
        return 1
    end

    set target $argv[1]
    if not string match -qr '^https?://' "$target"
        set target "https://$target"
    end

    set limit 200
    if set -q _flag_limit
        set limit $_flag_limit
    end

    set base (echo "$target" | sed -E 's#(^https?://[^/]+).*#\1#')
    set domain (echo "$base" | sed -E 's#^https?://##; s#/.*##')

    echo (set_color cyan)"==> WEBSCAN: $target"(set_color normal)
    echo (set_color brblack)"    Target domain: $domain"(set_color normal)
    echo (set_color brblack)"    Limit: $limit paths"(set_color normal)

    if set -q _flag_wordlist
        if not test -f "$_flag_wordlist"
            echo (set_color red)"Error: wordlist '$_flag_wordlist' not found"(set_color normal) >&2
            return 1
        end
        echo (set_color brblack)"    Wordlist: $_flag_wordlist"(set_color normal)
        set raw (cat "$_flag_wordlist")
        set paths
        for line in $raw
            set line (string trim -- $line)
            if test -n "$line"
                set -a paths $line
            end
        end
    else
        set paths \
            "" "robots.txt" "sitemap.xml" "sitemap_index.xml" ".htaccess" \
            "admin" "login" "wp-admin" "administrator" "backend" \
            "api" "api/v1" "api/v2" "graphql" \
            ".env" "config" "config.php" "config.json" \
            "backup" "dump" "sql" "database" \
            ".git" ".git/config" ".svn" "DS_Store" \
            "crossdomain.xml" "security.txt" "humans.txt" \
            "server-status" "server-info" "phpinfo.php" \
            "test" "dev" "staging" "beta" \
            "uploads" "images" "assets" "static" \
            "js" "css" "fonts" \
            "README.md" "LICENSE" "CHANGELOG" \
            "package.json" "package-lock.json" \
            ".well-known/security.txt" ".well-known/" \
            "index.php" "index.html" "index" \
            "register" "signup" "signin" "forgot-password" \
            "search" "query" "ajax" "api/status" \
            "health" "healthcheck" "status" \
            "dashboard" "panel" "cpanel" "webmail" \
            "phpmyadmin" "pma" "mysql" \
            "xmlrpc.php" "wp-json" "wp-content" \
            "shell" "cmd" "exec" "console"
    end

    echo ""

    set pathfile (mktemp /tmp/webscan_paths.XXXXXX)
    set count 0
    for p in $paths
        set count (math $count + 1)
        if test $count -gt $limit
            break
        end
        echo "$p" >> $pathfile
    end
    set total $count

    echo (set_color brblack)"    Scanning $total paths... "(set_color normal)
    set resfile (mktemp /tmp/webscan_results.XXXXXX)

    # Parallel scan — synchronous, waits for all to finish
    cat $pathfile \
    | xargs -P 100 -I {} sh -c "
      curl -sS --connect-timeout 5 --max-time 8 \
        --location -w '%{http_code}|%{size_download}|%{url_effective}' \
        -o /dev/null \
        '$base/{}' 2>/dev/null \
      | sed 's/^/{}|/'
    " > $resfile

    # Read and display results
    set found 0
    while read -l line
        set parts (string split '|' -- $line)
        set page $parts[1]
        set code $parts[2]
        set size $parts[3]
        set final $parts[4]

        if test -z "$code" -o "$code" = "0"
            continue
        end

        set final_path (echo "$final" | sed -E "s#^$base/*##")
        set is_home 0
        if test -z "$final_path" -o "$final_path" = "/"
            set is_home 1
        end

        set label ""
        set color ""

        switch (math "$code / 100")
            case 2
                if test "$is_home" = 1
                    set label "HOME"
                    set color (set_color red)
                else
                    set label "VISIBLE"
                    set color (set_color green)
                end
            case 3
                if test "$is_home" = 1
                    set label "HOME"
                    set color (set_color red)
                else
                    set label "REDIRECT"
                    set color (set_color cyan)
                end
            case 4
                switch $code
                    case 403
                        set label "PROTECTED"
                        set color (set_color yellow)
                    case 401
                        set label "AUTH"
                        set color (set_color yellow)
                    case 429
                        set label "RATE LIMITED"
                        set color (set_color yellow)
                    case '*'
                        set label "MISSING"
                        set color (set_color red)
                end
            case 5
                set label "ERROR"
                set color (set_color red)
            case '*'
                set label "?"
                set color (set_color red)
        end

        if test "$label" != "MISSING" -a "$label" != "HOME"
            set found (math $found + 1)
            printf "  %s %-14s %s (%s, %s B)%s\n" \
                $color $label (set_color normal) \
                (set_color brblack)"$page"(set_color normal) \
                (set_color brblack)(string trim -- $size)(set_color normal) \
                (set_color normal)
        end
    end < $resfile

    rm -f $pathfile $resfile
    echo ""
    echo (set_color cyan)"==> Scan complete."(set_color normal)
    if test $found -gt 0
        set p; if test $found -ne 1; set p "s"; end
        echo (set_color green)"  Found $found accessible page$p."(set_color normal)
    else
        echo (set_color yellow)"  No accessible pages found."(set_color normal)
    end
end
