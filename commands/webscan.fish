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

    set -g __ws_base (echo "$target" | sed -E 's#(^https?://[^/]+).*#\1#')
    set -g __ws_domain (echo "$__ws_base" | sed -E 's#^https?://##; s#/.*##')

    echo (set_color cyan)"==> WEBSCAN: $target"(set_color normal)
    echo (set_color brblack)"    Target domain: $__ws_domain"(set_color normal)
    echo (set_color brblack)"    Limit: $limit paths"(set_color normal)

    set -g __ws_discovered
    set -g __ws_checked
    set -g __ws_home_content

    # Fetch homepage content for redirect comparison
    set __ws_home_content (curl -sS --max-time 10 --location "$__ws_base/" 2>/dev/null)

    if set -q _flag_wordlist
        if not test -f "$_flag_wordlist"
            echo (set_color red)"Error: wordlist '$_flag_wordlist' not found"(set_color normal) >&2
            return 1
        end
        echo (set_color brblack)"    Wordlist: $_flag_wordlist"(set_color normal)
        set raw_lines (cat "$_flag_wordlist")
        set paths
        for line in $raw_lines
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

    function __ws_check -a page
        if contains -- "$page" $__ws_checked
            return
        end
        set -g __ws_checked $__ws_checked $page

        set url "$__ws_base/$page"

        # Get actual final URL after redirects
        set final_url (curl -sS -o /dev/null -w "%{url_effective}" --max-time 10 --location "$url" 2>/dev/null)
        set code (curl -sS -o /dev/null -w "%{http_code}" --max-time 10 --location "$url" 2>/dev/null)
        set size (curl -sS --max-time 10 --location "$url" 2>/dev/null | wc -c)
        set size (string trim -- $size)

        # Detect redirect to homepage (false positive)
        set redirected_home 0
        if test "$final_url" != "$url"
            set final_path (echo "$final_url" | sed -E "s#^$__ws_base/*##")
            if test -z "$final_path" -o "$final_path" = "/"
                set redirected_home 1
            end
        end

        # Detect redirect to same domain root
        set is_home 0
        if test "$final_url" = "$__ws_base/" -o "$final_url" = "$__ws_base"
            set is_home 1
        end

        # Determine status
        set status ""
        set color ""

        switch (math "$code / 100")
            case 2
                if test "$is_home" = 1
                    set status "REDIRECT HOME"
                    set color (set_color red)
                else
                    set status "VISIBLE"
                    set color (set_color green)
                end
            case 3
                if test "$redirected_home" = 1
                    set status "REDIRECT HOME"
                    set color (set_color red)
                else
                    set status "REDIRECT"
                    set color (set_color cyan)
                end
            case 4
                if test "$code" = "403"
                    set status "PROTECTED"
                    set color (set_color yellow)
                else if test "$code" = "401"
                    set status "AUTH REQUIRED"
                    set color (set_color yellow)
                else if test "$code" = "429"
                    set status "RATE LIMITED"
                    set color (set_color yellow)
                else
                    set status "NOT FOUND"
                    set color (set_color red)
                end
            case 5
                set status "SERVER ERROR"
                set color (set_color red)
            case '*'
                set status "UNKNOWN ($code)"
                set color (set_color red)
        end

        if test "$status" != "NOT FOUND" -a "$status" != "REDIRECT HOME"
            set -g __ws_discovered $__ws_discovered "$url"
        end

        if test "$status" != "NOT FOUND" -a "$status" != "REDIRECT HOME"
            printf "  %s %-16s %s (%s, %s bytes)%s\n" \
                $color $status (set_color normal) \
                (set_color brblack)"$page"(set_color normal) \
                (set_color brblack)"$size"(set_color normal)
        end
    end

    echo ""

    set total (count $paths)
    if test $total -gt $limit
        set total $limit
    end
    set count 0

    for path in $paths
        set count (math $count + 1)
        if test $count -gt $limit
            break
        end
        printf "\r  [%d/%d] Scanning... %-40s" $count $total "$path" >&2
        __ws_check "$path"
    end

    echo ""
    echo ""
    echo (set_color cyan)"==> Scan complete."(set_color normal)
    set found (count $__ws_discovered)

    if test $found -eq 0
        echo (set_color yellow)"  No accessible pages found."(set_color normal)
    else
        set p; if test $found -ne 1; set p "s"; end
        echo (set_color green)"  Found $found page$p:"(set_color normal)
        for u in $__ws_discovered
            echo "    "(set_color cyan)"$u"(set_color normal)
        end
    end

    functions -e __ws_check
    set -e __ws_base __ws_domain __ws_discovered __ws_checked __ws_home_content 2>/dev/null
end
