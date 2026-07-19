function iplog
    argparse -n iplog 't/title=' 'p/port=' 'w/webhook=' 'u/user=' 'passwd=' 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: iplog <command> [options]"
        echo ""
        echo "Commands:"
        echo "  start       Start the tracking server"
        echo "  stop        Stop the server"
        echo "  status      Check if server is running"
        echo "  link <name> Generate a unique tracking link"
        echo "  log         Show recent visits"
        echo "  purge       Clear all logs"
        echo ""
        echo "Options (start):"
        echo "  -t <title>    Page title (default: 'Singularity Codes')"
        echo "  -p <port>     Port (default: 8080)"
        echo "  -w <url>      Discord webhook for notifications"
        echo "  -u <user>     Username for admin dashboard (default: admin)"
        echo "  --passwd <pw> Password for admin dashboard"
        echo ""
        echo "Examples:"
        echo "  iplog start -p 80 -w https://discord.com/api/webhooks/..."
        echo "  iplog link alice"
        echo "  iplog log"
        return
    end

    if test (count $argv) -lt 1
        echo "Usage: iplog <command> [options]"
        return 1
    end

    set cmd $argv[1]
    set argv $argv[2..-1]

    switch $cmd
        case start
            __iplog_start
        case stop
            __iplog_stop
        case status
            __iplog_status
        case link
            __iplog_link $argv
        case log
            __iplog_log
        case purge
            __iplog_purge
        case '*'
            echo (set_color red)"Unknown command: $cmd"(set_color normal)
            return 1
    end
end

function __iplog_start
    set dir $HOME/.iplog
    mkdir -p $dir

    set port 8080
    if set -q _flag_port; set port $_flag_port; end

    set title "Singularity Codes"
    if set -q _flag_title; set title $_flag_title; end

    set webhook ""
    if set -q _flag_webhook; set webhook $_flag_webhook; end

    set admin_user "admin"
    if set -q _flag_user; set admin_user $_flag_user; end

    set admin_pass "iplog123"
    if set -q _flag_passwd; set admin_pass $_flag_passwd; end

    # Save config
    echo "port=$port" > $dir/config
    echo "title=$title" >> $dir/config
    echo "admin_user=$admin_user" >> $dir/config
    echo "admin_pass=$admin_pass" >> $dir/config
    echo "webhook=$webhook" >> $dir/config

    # Create data dir
    mkdir -p $dir/data
    touch $dir/data/visits.log
    touch $dir/data/refs.txt

    # Write landing page
    cat > $dir/index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$title</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
  background:#0a0a0f;color:#e0e0e0;min-height:100vh;display:flex;
  flex-direction:column;align-items:center;justify-content:center}
.container{text-align:center;padding:2rem}
h1{font-size:3.5rem;font-weight:800;background:linear-gradient(135deg,#667eea,#764ba2);
  -webkit-background-clip:text;-webkit-text-fill-color:transparent;margin-bottom:1rem}
p{color:#888;font-size:1.1rem;max-width:500px;line-height:1.6}
.footer{margin-top:3rem;color:#333;font-size:.85rem}
.loading{display:inline-block;width:20px;height:20px;border:2px solid #333;
  border-top-color:#667eea;border-radius:50%;animation:spin .8s linear infinite;margin-top:2rem}
@keyframes spin{to{transform:rotate(360deg)}}
</style>
</head>
<body>
<div class="container">
  <div class="loading"></div>
  <h1>$title</h1>
  <p>Loading...</p>
  <div class="footer">&copy; $(date +%Y) $title</div>
</div>
<script>
(async()=>{
  try{await fetch('/api/visit'+location.pathname,{method:'POST'})}catch(e){}
  // track additional info
  try{await fetch('/api/info',{method:'POST',
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({
      lang:navigator.language,platform:navigator.platform,
      ref:document.referrer,url:location.href
    })})}catch(e){}
})();
</script>
</body>
</html>
EOF

    # Write server
    cat > $dir/server.py << 'PYEOF'
import http.server, json, os, sys, signal, base64, hashlib, urllib.request, time
from datetime import datetime

DIR = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(DIR, 'data')

cfg = {}
with open(os.path.join(DIR, 'config')) as f:
    for line in f:
        line = line.strip()
        if '=' in line:
            k, v = line.split('=', 1)
            cfg[k] = v

PORT = int(cfg.get('port', 8080))
TITLE = cfg.get('title', 'Site')
ADMIN_USER = cfg.get('admin_user', 'admin')
ADMIN_PASS = cfg.get('admin_pass', 'iplog123')
WEBHOOK = cfg.get('webhook', '')

def log_visit(ip, ref=''):
    ts = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')
    entry = f'{ts}|{ip}|{ref}'
    with open(os.path.join(DATA, 'visits.log'), 'a') as f:
        f.write(entry + '\n')
    if WEBHOOK:
        try:
            payload = json.dumps({
                'content': None,
                'embeds': [{
                    'title': 'New Visit',
                    'color': 0x667eea,
                    'fields': [
                        {'name': 'IP', 'value': ip, 'inline': True},
                        {'name': 'Ref', 'value': ref or '(none)', 'inline': True},
                        {'name': 'Time', 'value': ts, 'inline': False}
                    ]
                }]
            }).encode()
            req = urllib.request.Request(WEBHOOK, data=payload,
                headers={'Content-Type': 'application/json'})
            urllib.request.urlopen(req, timeout=5)
        except:
            pass

def auth_ok(headers):
    auth = headers.get('Authorization', '')
    if auth.startswith('Basic '):
        try:
            decoded = base64.b64decode(auth[6:]).decode()
            u, p = decoded.split(':', 1)
            return u == ADMIN_USER and p == ADMIN_PASS
        except:
            pass
    return False

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        ip = self.client_address[0]
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            with open(os.path.join(DIR, 'index.html')) as f:
                self.wfile.write(f.read().encode())
            log_visit(ip, '/')
        elif self.path.startswith('/r/'):
            ref = self.path[3:]
            log_visit(ip, ref)
            self.send_response(302)
            self.send_header('Location', '/')
            self.end_headers()
        elif self.path == '/api/log':
            if not auth_ok(self.headers):
                self.send_response(401)
                self.send_header('WWW-Authenticate', 'Basic realm="admin"')
                self.end_headers()
                return
            visits = []
            logfile = os.path.join(DATA, 'visits.log')
            if os.path.exists(logfile):
                with open(logfile) as f:
                    for line in f:
                        line = line.strip()
                        if line:
                            parts = line.split('|')
                            visits.append({
                                'time': parts[0] if len(parts) > 0 else '',
                                'ip': parts[1] if len(parts) > 1 else '',
                                'ref': parts[2] if len(parts) > 2 else ''
                            })
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps(visits[-100:]).encode())
        elif self.path == '/admin':
            if not auth_ok(self.headers):
                self.send_response(401)
                self.send_header('WWW-Authenticate', 'Basic realm="admin"')
                self.end_headers()
                self.wfile.write(b'<html><body><h1>Unauthorized</h1></body></html>')
                return
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            html = '''<!DOCTYPE html>
<html><head><title>IPLog Dashboard</title>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:monospace;background:#0a0a0f;color:#e0e0e0;padding:2rem}
h1{color:#667eea;margin-bottom:1rem}
table{width:100%;border-collapse:collapse;font-size:.85rem}
th{text-align:left;padding:.5rem;border-bottom:1px solid #333;color:#888}
td{padding:.5rem;border-bottom:1px solid #1a1a1a}
tr:hover{background:#111}
.ip{color:#667eea}
.ref{color:#764ba2}
.time{color:#555}
.count{color:#888;margin-bottom:1rem}
button{padding:.3rem .8rem;background:#333;color:#e0e0e0;border:1px solid #444;cursor:pointer;margin-right:.5rem}
button:hover{background:#444}
a{color:#667eea;text-decoration:none}
</style>
</head><body>
<h1>IPLog Dashboard</h1>
<div class="count" id="count">Loading...</div>
<button onclick="refresh()">Refresh</button>
<button onclick="clearLogs()">Clear</button>
<a href="/api/log" style="margin-left:.5rem">[JSON]</a>
<table><thead><tr><th>Time</th><th>IP</th><th>Reference</th></tr></thead>
<tbody id="visits"></tbody></table>
<script>
async function refresh(){try{
  let r=await fetch('/api/log');let d=await r.json();
  let h=document.getElementById('visits');h.innerHTML='';
  document.getElementById('count').textContent=d.length+' visit'+(d.length!=1?'s':'');
  for(let v of d.reverse()){let tr=document.createElement('tr');
    tr.innerHTML='<td class="time">'+v.time+'</td><td class="ip">'+v.ip+'</td><td class="ref">'+v.ref+'</td>';
    h.appendChild(tr)}
}catch(e){document.getElementById('count').textContent='Error loading'}}
async function clearLogs(){if(confirm('Clear all logs?')){await fetch('/api/clear',{method:'POST'});refresh()}}
refresh();setInterval(refresh,5000)
</script></body></html>'''
            self.wfile.write(html.encode())
        elif self.path == '/pixel.png' or self.path == '/track':
            log_visit(ip, self.headers.get('Referer', ''))
            # 1x1 transparent PNG
            self.send_response(200)
            self.send_header('Content-Type', 'image/png')
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(bytes.fromhex(
                '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489'
                '0000000b4944415408d763600000000200010ae05c85000000004945e44ae426082'))
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        ip = self.client_address[0]
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length) if length else b''

        if self.path == '/api/visit':
            ref = self.headers.get('X-Referer', self.path)
            log_visit(ip, ref)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'ok')
        elif self.path == '/api/info':
            log_visit(ip, 'js-page')
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'ok')
        elif self.path == '/api/clear':
            if auth_ok(self.headers):
                open(os.path.join(DATA, 'visits.log'), 'w').close()
                self.send_response(200)
            else:
                self.send_response(401)
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *a): pass

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
        self.end_headers()

print(f'\n  {"="*40}')
print(f'  IPLOG server running')
print(f'  {"="*40}')
print(f'  Site:        http://0.0.0.0:{PORT}')
print(f'  Dashboard:   http://0.0.0.0:{PORT}/admin')
print(f'  Login:       {ADMIN_USER} / {ADMIN_PASS}')
print(f'  Tracking:    http://0.0.0.0:{PORT}/r/<name>')
print(f'  Webhook:     {"enabled" if WEBHOOK else "disabled"}')
print(f'  Log:         {DATA}/visits.log')
print(f'  {"="*40}\n')

httpd = http.server.HTTPServer(('0.0.0.0', PORT), Handler)
httpd.serve_forever()
PYEOF

    # Save PID
    nohup python3 $dir/server.py > $dir/server.log 2>&1 &
    echo $! > $dir/pid
    sleep 1

    set pid (cat $dir/pid)
    if kill -0 $pid 2>/dev/null
        echo (set_color green)"  Server started on port $port (PID $pid)"(set_color normal)
        echo (set_color cyan)"  Dashboard: http://localhost:$port/admin"(set_color normal)
        echo (set_color cyan)"  Login:     $admin_user / $admin_pass"(set_color normal)
        echo ""
        echo (set_color brblack)"  Tracking links:"(set_color normal)
        echo (set_color brblack)"    http://localhost:$port/r/alice"(set_color normal)
        echo (set_color brblack)"    http://localhost:$port/r/bob"(set_color normal)
        if test -n "$webhook"
            echo (set_color green)"  Discord webhook notifications enabled"(set_color normal)
        end
    else
        echo (set_color red)"  Failed to start server"(set_color normal)
        cat $dir/server.log
    end
end

function __iplog_stop
    set dir $HOME/.iplog
    if not test -f $dir/pid
        echo (set_color yellow)"  Server not running"(set_color normal)
        return
    end
    set pid (cat $dir/pid)
    kill $pid 2>/dev/null
    rm -f $dir/pid
    echo (set_color green)"  Server stopped"(set_color normal)
end

function __iplog_status
    set dir $HOME/.iplog
    if test -f $dir/pid
        set pid (cat $dir/pid)
        if kill -0 $pid 2>/dev/null
            echo (set_color green)"  Server is running (PID $pid)"(set_color normal)
            if test -f $dir/config
                echo (set_color brblack)"    Config: $dir/config"(set_color normal)
            end
            return
        end
        rm -f $dir/pid
    end
    echo (set_color yellow)"  Server is not running"(set_color normal)
end

function __iplog_link
    if test (count $argv) -lt 1
        echo "Usage: iplog link <name>"
        return 1
    end
    set name $argv[1]
    set dir $HOME/.iplog
    if not test -f $dir/config
        echo (set_color yellow)"  Server not started yet. Run 'iplog start' first."(set_color normal)
        return
    end
    # Read port from config
    set port 8080
    if test -f $dir/config
        set port (grep '^port=' $dir/config 2>/dev/null | string split '=' -f 2)
    end
    echo $name >> $dir/data/refs.txt
    sort -u $dir/data/refs.txt -o $dir/data/refs.txt
    echo (set_color cyan)"  Tracking link for '$name':"(set_color normal)
    echo (set_color green)"    http://localhost:$port/r/$name"(set_color normal)
    echo (set_color brblack)"    (replace localhost with your domain when deployed)"(set_color normal)
end

function __iplog_log
    set dir $HOME/.iplog
    set logfile $dir/data/visits.log
    if not test -f $logfile
        echo (set_color yellow)"  No visits yet"(set_color normal)
        return
    end
    set total (wc -l < $logfile 2>/dev/null | string trim)
    echo (set_color cyan)"  Recent visits (last 20 of $total):"(set_color normal)
    echo "  "(set_color brblack)"Time                IP              Ref"(set_color normal)
    tail -20 $logfile | while read -l line
        set parts (string split '|' -- $line)
        set ts $parts[1]
        set ip $parts[2]
        set ref $parts[3]
        if test -z "$ref"; set ref "-"; end
        printf "  %s %-18s %-15s %s\n" (set_color brblack) $ts $ip $ref (set_color normal)
    end
end

function __iplog_purge
    set dir $HOME/.iplog
    > $dir/data/visits.log
    > $dir/data/refs.txt
    echo (set_color green)"  Logs cleared"(set_color normal)
end
