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
    set domain (string replace -r '^https?://' '' -- "$domain")
    set domain (string replace -r '/.*$' '' -- "$domain")

    set resp (curl -sL --max-time 10 "https://rdap.org/domain/$domain" 2>/dev/null)

    if test -z "$resp"
        echo (set_color red)"Error: WHOIS API unreachable"(set_color normal)
        return 1
    end

    set error (echo "$resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('errorCode', ''))
except:
    print('parse_error')
" 2>/dev/null)

    if test -n "$error" -a "$error" != "parse_error"
        set registered 0
        set status_msg "AVAILABLE"
        set status_color (set_color green)
    else if test "$error" = "parse_error"
        echo (set_color red)"Error: failed to parse WHOIS response"(set_color normal)
        return 1
    else
        set registered 1
        set status_msg "REGISTERED"
        set status_color (set_color red)
    end

    if test "$registered" = 1
        set parsed (echo "$resp" | python3 -c "
import sys, json
d = json.load(sys.stdin)
reg = exp = ns = ''
if 'events' in d:
    for e in d['events']:
        a = e.get('eventAction', '')
        dt = e.get('eventDate', '')
        if a == 'registration' and not reg: reg = dt[:10]
        if a == 'expiration' and not exp: exp = dt[:10]
if 'nameservers' in d:
    ns_list = [n['ldhName'].rstrip('.') for n in d['nameservers']]
    ns = ', '.join(ns_list[:4])
    if len(ns_list) > 4: ns += ' ...'
print(f'{reg}|{exp}|{ns}')
" 2>/dev/null)

        set parts (string split '|' -- $parsed)
        set created $parts[1]
        set expiry $parts[2]
        set nameservers $parts[3]
    else
        set created ""
        set expiry ""
        set nameservers ""
    end

    if set -q _flag_short
        if test "$registered" = 1
            if test -n "$expiry"
                echo "$status_color$status_msg"(set_color normal)"  $domain  expires $expiry"
            else
                echo "$status_color$status_msg"(set_color normal)"  $domain"
            end
        else
            echo "$status_color$status_msg"(set_color normal)"  $domain"
        end
        return
    end

    echo (set_color cyan)"==> WHOIS: $domain"(set_color normal)
    echo "  Status:    $status_color$status_msg"(set_color normal)

    if test "$registered" = 1
        if test -n "$created";  echo "  Created:   $created";  end
        if test -n "$expiry";   echo "  Expires:   $expiry";   end
        if test -n "$nameservers"; echo "  NS:        $nameservers"; end
    end
end
