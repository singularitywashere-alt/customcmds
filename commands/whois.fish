function whois
    argparse -n whois 's/short' 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: whois [-s] <domain>"
        echo ""
        echo "Options:"
        echo "  -s    Short summary (one line)"
        echo ""
        echo "Examples:"
        echo "  whois example.com"
        echo "  whois -s example.com"
        return
    end

    if test (count $argv) -lt 1
        echo "Usage: whois [-s] <domain>"
        return 1
    end

    set domain $argv[1]

    set raw (command whois "$domain" 2>/dev/null)

    if test -z "$raw"
        echo (set_color red)"Error: whois lookup failed or no output"(set_color normal)
        return 1
    end

    set lines (string split "\n" -- $raw)

    set status ""
    set registrar ""
    set created ""
    set expiry ""
    set nameservers ""
    set in_ns 0

    for line in $lines
        set line (string trim -- $line)

        if string match -rq '^No match for|^NOT FOUND|^No Data Found|^Domain not found|^Status:\s*available' "$line"
            set status "available"
        else if string match -rq '^Domain Name:' "$line"
            if test -z "$status"
                set status "registered"
            end
        else if string match -rq '^Registrar:' "$line"
            set registrar (string replace -r '^Registrar:\s*' '' -- "$line")
        else if string match -rq '^Creation Date:' "$line"
            set created (string replace -r '^Creation Date:\s*' '' -- "$line")
        else if string match -rq '^Registry Expiry Date:|^Expiration Date:|^Expiry Date:' "$line"
            set expiry (string replace -r '^[^:]+:\s*' '' -- "$line")
        else if string match -rq '^Name Server:' "$line"
            if test "$in_ns" = 0
                set nameservers (string replace -r '^Name Server:\s*' '' -- "$line")
                set in_ns 1
            else
                set nameservers "$nameservers, "(string replace -r '^Name Server:\s*' '' -- "$line")
            end
        end
    end

    if test -z "$status"
        set status "unknown"
    end

    if set -q _flag_short
        switch $status
            case "available"
                echo (set_color green)"AVAILABLE"(set_color normal)"  $domain"
            case "registered"
                if test -n "$expiry"
                    echo (set_color red)"REGISTERED"(set_color normal)"  $domain  expires $expiry"
                else
                    echo (set_color red)"REGISTERED"(set_color normal)"  $domain"
                end
            case '*'
                echo (set_color yellow)"UNKNOWN"(set_color normal)"  $domain"
        end
        return
    end

    echo (set_color cyan)"==> WHOIS: $domain"(set_color normal)

    switch $status
        case "available"
            echo (set_color green)"  Status:    AVAILABLE"(set_color normal)
        case "registered"
            echo (set_color red)"  Status:    REGISTERED"(set_color normal)
        case '*'
            echo (set_color yellow)"  Status:    UNKNOWN"(set_color normal)
    end

    if test -n "$registrar"
        echo "  Registrar: $registrar"
    end
    if test -n "$created"
        echo "  Created:   $created"
    end
    if test -n "$expiry"
        echo "  Expires:   $expiry"
    end
    if test -n "$nameservers"
        echo "  NS:        $nameservers"
    end
end
