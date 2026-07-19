function webscan
    argparse -n webscan 'w/wordlist=' 'l/limit=' 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: webscan <target> [-w <wordlist>] [-l <limit>]"
        echo ""
        echo "Options:"
        echo "  -w <file>    Custom wordlist (one path per line)"
        echo "  -l <limit>   Max paths to scan (default: 500)"
        echo ""
        echo "Examples:"
        echo "  webscan https://example.com"
        echo "  webscan https://example.com -w mypaths.txt"
        echo "  webscan https://example.com -l 1000"
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

    set limit 500
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
            ".env" ".env.bak" ".env.local" ".env.prod" ".env.dev" \
            "admin" "admin/" "admin.php" "admin.html" "admin/index.php" \
            "login" "login.php" "login.html" "signin" "signin.php" \
            "register" "register.php" "signup" "signup.php" \
            "forgot-password" "reset-password" "forgot" \
            "logout" "logout.php" "logout.html" \
            "wp-admin" "wp-admin/" "wp-login.php" "wp-content" \
            "wp-content/" "wp-content/uploads" "wp-content/themes" \
            "wp-content/plugins" "wp-includes" "wp-json" "wp-json/" \
            "wp-json/wp/v2/users" "xmlrpc.php" "xmlrpc" \
            "administrator" "administrator/" "admincp" \
            "backend" "backend/" "api" "api/" "api/v1" "api/v2" "api/v3" \
            "api/users" "api/login" "api/auth" "api/status" "api/health" \
            "api/docs" "api/swagger" "api/openapi.json" \
            "graphql" "graphql/" "graphiql" \
            "config" "config.php" "config.json" "config.xml" "config.yaml" \
            "configuration" "settings" "settings.php" \
            "database" "db" "db/" "sql" "sql/" "mysql" \
            "backup" "backup/" "backups" "dump" "dumps" \
            ".git" ".git/" ".git/config" ".git/HEAD" \
            ".svn" ".svn/" "CVS" "CVS/" \
            "DS_Store" ".DS_Store" "Thumbs.db" \
            "crossdomain.xml" "clientaccesspolicy.xml" \
            "security.txt" ".well-known/security.txt" ".well-known/" \
            "humans.txt" "README.md" "LICENSE" "CHANGELOG" "CHANGELOG.md" \
            "package.json" "package-lock.json" "composer.json" \
            "yarn.lock" "Gemfile" "Gemfile.lock" \
            "server-status" "server-info" "server-status/" \
            "phpinfo.php" "info.php" "test.php" \
            "test" "dev" "staging" "beta" "alpha" "sandbox" \
            "uploads" "uploads/" "upload" "download" "downloads" \
            "images" "img" "assets" "assets/" "static" "static/" \
            "js" "js/" "css" "css/" "fonts" "fonts/" \
            "index" "index.php" "index.html" "index.htm" \
            "default" "default.php" "default.html" \
            "home" "home.php" "home.html" "main" "main.php" \
            "about" "about.php" "about.html" "contact" "contact.php" \
            "contact.html" "terms" "privacy" "cookies" \
            "help" "help.php" "faq" "faq.php" "support" \
            "search" "search.php" "query" "ajax" "ajax.php" \
            "health" "healthcheck" "health.php" "status" "status.php" \
            "dashboard" "dashboard/" "panel" "panel/" "cpanel" \
            "webmail" "webmail/" "mail" "email" "roundcube" \
            "phpmyadmin" "phpmyadmin/" "pma" "pma/" "mysql" "mysql/" \
            "adminer" "adminer.php" "pgmyadmin" \
            "shell" "shell.php" "cmd" "cmd.php" "exec" "exec.php" \
            "console" "console/" "terminal" "terminal/" \
            "ssh" "ssh/" "rdp" "rdp/" "vnc" "vnc/" \
            "proxy" "proxy/" "proxy.php" "socks" \
            "README" "CHANGELOG" "CONTRIBUTING" "CONTRIBUTING.md" \
            "docker" "docker/" "docker-compose.yml" "Dockerfile" \
            "Makefile" "Makefile.php" "Gruntfile.js" "gulpfile.js" \
            "webpack.config.js" "webpack" \
            ".npmrc" ".yarnrc" ".nvmrc" ".node-version" \
            ".gitignore" ".gitattributes" ".gitmodules" \
            ".editorconfig" ".eslintrc" ".prettierrc" \
            "nginx.conf" ".htpasswd" "httpd.conf" \
            "cgi-bin/" "cgi-bin/php" \
            "api/v1/users" "api/v1/products" "api/v1/orders" \
            "api/v2/users" "api/v2/products" \
            "graphql/console" "graphql/explorer"
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

    # Parallel scan — use printf instead of sed to avoid delimiter issues
    cat $pathfile \
    | xargs -P 100 -I {} sh -c '
      data=$(curl -sS --connect-timeout 5 --max-time 8 \
        --location -w "%{http_code}|%{size_download}|%{url_effective}" \
        -o /dev/null \
        '"$base"'/{} 2>/dev/null)
      printf "%s|%s\n" "{}" "$data"
    ' > $resfile

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
                        set color (set_color brblack)
                end
            case 5
                set label "ERROR"
                set color (set_color red)
            case '*'
                set label "?"
                set color (set_color red)
        end

        if test "$label" != "MISSING"
            set found (math $found + 1)
        end
        printf "  %s %-14s %s (%s, %s B)%s\n" \
            $color $label (set_color normal) \
            (set_color brblack)"$page"(set_color normal) \
            (set_color brblack)(string trim -- $size)(set_color normal) \
            (set_color normal)
    end < $resfile

    rm -f $pathfile $resfile
    echo ""
    echo (set_color cyan)"==> Scan complete."(set_color normal)
    if test $found -gt 0
        set p; if test $found -ne 1; set p "s"; end
        echo (set_color green)"  Found $found page$p."(set_color normal)
    else
        echo (set_color yellow)"  No pages found."(set_color normal)
    end
end
