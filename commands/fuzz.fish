function fuzz
    argparse -n fuzz 'w/wordlist=' 'e/extensions=' 'm/method=' 'd/data=' 'c/cookie=' \
        'hide-code=' 'show-code=' 'hide-size=' 't/threads=' 'auto' 'attack' 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: fuzz <target> [options]"
        echo "  -w <file>       Wordlist (one path per line)"
        echo "  -e <exts>       Extensions (comma-sep: .php,.asp)"
        echo "  -m <method>     HTTP method (default: GET)"
        echo "  -d <data>       POST body with FUZZ placeholder"
        echo "  -c <cookie>     Cookie header"
        echo "  --hide-code <c>  Hide status codes (comma: 404,403)"
        echo "  --show-code <c>  Only show these codes"
        echo "  --hide-size <n>  Hide responses of exact size"
        echo "  -t <n>          Threads (default: 50)"
        echo "  --auto          Machine-readable output"
        echo "  --attack        Attack on find"
        echo "Web path/content fuzzer."
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

    set method "GET"
    if set -q _flag_method; set method $_flag_method; end

    set threads 50
    if set -q _flag_threads; set threads $_flag_threads; end

    set target_base (echo "$target" | sed -E 's#/+$##')

    if set -q _flag_wordlist
        if not test -f "$_flag_wordlist"
            echo (set_color red)"Error: wordlist '$_flag_wordlist' not found"(set_color normal)
            return 1
        end
        set words (cat "$_flag_wordlist")
    else
        set words \
            admin login signup register api v1 v2 backup config \
            .git .env .htaccess robots.txt sitemap.xml \
            admin.php login.php config.php db.php index.php \
            test dev debug beta staging sandbox \
            upload downloads images img css js assets static \
            wp-admin wp-content wp-includes administrator \
            phpmyadmin pma adminer mysql sql database \
            api/users api/login api/docs swagger graphql \
            server-status server-info cgi-bin shell \
            xmlrpc.php crossdomain.xml .svn .DS_Store Thumbs.db
    end

    set extensions
    if set -q _flag_extensions
        set extensions (string split ',' -- $_flag_extensions)
    end

    set hide_codes
    if set -q _flag_hide_code
        set hide_codes (string split ',' -- $_flag_hide_code)
    end

    set show_codes
    if set -q _flag_show_code
        set show_codes (string split ',' -- $_flag_show_code)
    end

    set hide_size ""
    if set -q _flag_hide_size
        set hide_size $_flag_hide_size
    end

    set total 0
    for word in $words
        set total (math $total + 1)
        for ext in "" $extensions
            if test -n "$ext"; set total (math $total + 1); end
        end
    end

    echo (set_color cyan)"==> FUZZ: $target"(set_color normal)
    echo (set_color brblack)"    Words: $(count $words) | Threads: $threads | Total reqs: $total"(set_color normal)

    set tmpdir (mktemp -d /tmp/fuzz.XXXXXX)
    set wordfile $tmpdir/words.txt
    set resfile $tmpdir/results.txt

    # Build word list with extensions
    for word in $words
        echo "$word" >> $wordfile
        for ext in $extensions
            echo "$word$ext" >> $wordfile
        end
    end

    set req_count (wc -l < $wordfile | string trim)
    echo (set_color brblack)"    Fuzzing $req_count paths..."(set_color normal)

    # Build curl command based on method
    set curl_args "-sS -o /dev/null -w '%{http_code}|%{size_download}|%{url_effective}' --max-time 10"
    if set -q _flag_cookie; set curl_args "$curl_args -H 'Cookie: $_flag_cookie'"; end

    set data_flag ""
    if set -q _flag_data; set data_flag "-d '$_flag_data'"; end

    # Use xargs for parallel fuzzing (like webscan)
    cat $wordfile \
    | xargs -P $threads -I {} sh -c '
      url="'"$target_base"'/{}"
      result=$(curl -sS -o /dev/null -w "%{http_code}|%{size_download}|%{url_effective}" \
        --max-time 10 "'"$method"'" "'"$data_flag"'" "'"$target_base"'/{}" 2>/dev/null)
      printf "%s|%s\n" "{}" "$result"
    ' > $resfile

    set found 0
    while read -l line
        set parts (string split '|' -- $line)
        set word $parts[1]
        set code $parts[2]
        set size $parts[3]
        set final $parts[4]

        if test -z "$code" -o "$code" = "0"; continue; end

        # Filter by code
        if test (count $show_codes) -gt 0
            if not contains -- $code $show_codes; continue; end
        end
        if test (count $hide_codes) -gt 0
            if contains -- $code $hide_codes; continue; end
        end

        # Filter by size
        if test -n "$hide_size" -a "$size" = "$hide_size"; continue; end

        set found (math $found + 1)
        set color (set_color green)
        if test "$code" = "403"; set color (set_color yellow)
        else if test "$code" = "301" -o "$code" = "302"; set color (set_color cyan)
        else if test "$code" = "401"; set color (set_color yellow)
        else if test "$code" = "500"; set color (set_color red)
        end
        printf "  %s %s %s  [%s] (%s B)%s\n" $color $code (set_color normal) $word $size
    end < $resfile

    rm -rf $tmpdir

    echo ""
    if test $found -gt 0
        echo (set_color green)"  $found interesting response(s)"(set_color normal)
        if not set -q _flag_auto
            echo -n "Launch attack? [y/N] "
            read -l ans
            if test "$ans" = "y" -o "$ans" = "Y"
                attack "$target"
            end
        end
    else
        echo (set_color yellow)"  No interesting responses found"(set_color normal)
    end

    if set -q _flag_attack
        attack "$target"
    end
end
