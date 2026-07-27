function paramine
    argparse -n paramine 'w/wordlist=' 'm/method=' 'd/data=' 'c/cookie=' 'auto' 'attack' 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: paramine <target> [options]"
        echo "  -w <file>     Custom parameter wordlist"
        echo "  -m <method>   HTTP method (default: GET)"
        echo "  -d <data>     POST body"
        echo "  -c <cookie>   Cookie header"
        echo "  --auto        Machine-readable output"
        echo "  --attack      Attack target after scan"
        echo "Brute-forces parameter names."
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

    if set -q _flag_wordlist
        if not test -f "$_flag_wordlist"
            echo (set_color red)"Error: wordlist '$_flag_wordlist' not found"(set_color normal)
            return 1
        end
        set params (cat "$_flag_wordlist")
    else
        set params \
            id user admin page order search query term s sort \
            limit offset count start end date filter type status \
            action method do cmd exec run debug test mode \
            lang locale format view display template layout \
            token key api_key apikey secret pass password pwd \
            email mail name username uname login signup register \
            file path dir folder url link redirect return next \
            msg message text content body title name desc \
            category tag tags slug permalink \
            theme color style font size width height \
            callback jsonp _ csrf nonce state scope \
            access permission role group level \
            domain host port server site \
            version v ver lang locale \
            error success info warning \
            data payload raw preview \
            src source target destination \
            old new current previous next \
            video image img picture avatar icon \
            ref referer source utm_source utm_campaign \
            gclid fbclid dclid msclkid \
            _token _method _csrf_token authenticity_token \
            commit submit go continue confirm \
            op option func function command \
            day month year hour minute second \
            x y z lat lng lon zoom \
            provider network operator carrier \
            imei imsi udid device platform os \
            r uuid hash sig signature checksum
    end

    echo (set_color cyan)"==> PARAMINE: $target"(set_color normal)
    echo (set_color brblack)"    Testing $(count $params) parameters..."(set_color normal)

    # Get baseline response
    set base_resp (curl -sS -o /dev/null -w "%{http_code}|%{size_download}" --max-time 10 "$target" 2>/dev/null)
    set base_code (string split '|' -- $base_resp)[1]
    set base_size (string split '|' -- $base_resp)[2]

    set found_count 0
    set found_params

    for p in $params
        set test_url "$target?$p=1"
        set resp (curl -sS -o /dev/null -w "%{http_code}|%{size_download}" --max-time 10 "$test_url" 2>/dev/null)
        set code (string split '|' -- $resp)[1]
        set size (string split '|' -- $resp)[2]

        if test -z "$code"; continue; end

        # Different code or size = parameter affects response
        if test "$code" != "$base_code" -o "$size" != "$base_size"
            set found_count (math $found_count + 1)
            set -a found_params "$p (code=$code size=$size)"
            echo (set_color green)"  [FOUND] $p -> $code ($size B)"(set_color normal)
        end
    end

    echo ""
    if test $found_count -gt 0
        echo (set_color yellow)"  $found_count parameter(s) affect response:"(set_color normal)
        for fp in $found_params
            echo "    $fp"
        end
        if not set -q _flag_auto
            echo ""
            echo -n "Launch attack? [y/N] "
            read -l ans
            if test "$ans" = "y" -o "$ans" = "Y"
                attack "$target"
            end
        end
    else
        echo (set_color brblack)"  No parameters affected response"(set_color normal)
    end

    if set -q _flag_attack
        attack "$target"
    end
end
