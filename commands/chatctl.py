#!/usr/bin/env python3
"""chatctl — Anti chat control encryption tool (cross-platform Python)"""
import sys, os, json, base64, hashlib, secrets, subprocess, time, re, struct, signal, shlex, atexit, shutil

CONFIG_DIR = os.path.expanduser("~/.chatctl")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")
STATE_FILE = os.path.join(CONFIG_DIR, "state.json")
PID_FILE = os.path.join(CONFIG_DIR, "daemon.pid")
LOG_FILE = os.path.join(CONFIG_DIR, "daemon.log")

def ensure_dir():
    os.makedirs(CONFIG_DIR, exist_ok=True)

def load_config():
    ensure_dir()
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            return json.load(f)
    return {}

def save_config(cfg):
    ensure_dir()
    with open(CONFIG_FILE, 'w') as f:
        json.dump(cfg, f)

def load_state():
    ensure_dir()
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            return json.load(f)
    return {"encryption": False}

def save_state(st):
    ensure_dir()
    with open(STATE_FILE, 'w') as f:
        json.dump(st, f)

def log(msg):
    with open(LOG_FILE, 'a') as f:
        f.write(f"{time.strftime('%H:%M:%S')} {msg}\n")

def notify(title, text):
    try:
        subprocess.run(['notify-send', title, text[:200]], check=False,
                       timeout=2)
    except: pass

# ─── CRYPTO ───
def derive_key(password: str, salt: bytes) -> bytes:
    return hashlib.pbkdf2_hmac('sha256', password.encode(), salt, 200000, 32)

def encrypt(plaintext: str, password: str) -> str:
    salt = os.urandom(16)
    key = derive_key(password, salt)
    iv = os.urandom(16)
    pt = plaintext.encode('utf-8')
    ks = b""
    ctr = 0
    while len(ks) < len(pt):
        ks += hashlib.sha256(key + iv + struct.pack('>Q', ctr)).digest()
        ctr += 1
    ct = bytes(a ^ b for a, b in zip(pt, ks[:len(pt)]))
    hmac = hashlib.sha256(salt + iv + ct + key).digest()
    return base64.b64encode(salt + iv + ct + hmac).decode()

def decrypt(encoded: str, password: str) -> str:
    raw = base64.b64decode(encoded)
    salt, iv, rest = raw[:16], raw[16:32], raw[32:]
    hmac_sig, ct = rest[-32:], rest[:-32]
    key = derive_key(password, salt)
    expected = hashlib.sha256(salt + iv + ct + key).digest()
    if hmac_sig != expected:
        raise ValueError("bad decrypt")
    ks = b""
    ctr = 0
    while len(ks) < len(ct):
        ks += hashlib.sha256(key + iv + struct.pack('>Q', ctr)).digest()
        ctr += 1
    return bytes(a ^ b for a, b in zip(ct, ks[:len(ct)])).decode('utf-8')

def random_prefix(length=10):
    return secrets.token_hex(length // 2 + 1)[:length]

ENC_PATTERN = re.compile(r'^([a-zA-Z0-9]{6,16})///')

def format_encrypted(plaintext: str, password: str) -> str:
    prefix = random_prefix(10)
    ct = encrypt(plaintext, password)
    return f"{prefix}///{ct}"

def try_decrypt(text: str, password: str):
    m = ENC_PATTERN.match(text)
    if not m:
        return None
    payload = text[m.end():]
    if not payload:
        return None
    try:
        return decrypt(payload, password)
    except:
        return None

# ─── CLIPBOARD ───
def clip_copy(text):
    try:
        if sys.platform == 'darwin':
            subprocess.run(['pbcopy'], input=text.encode(), check=False)
        elif sys.platform == 'win32' or sys.platform == 'cygwin':
            subprocess.run(['clip'], input=text.encode(), check=False)
        else:
            for c in ['xclip -selection clipboard', 'xsel -ib', 'wl-copy', 'termux-clipboard-set']:
                try:
                    subprocess.run(shlex.split(c), input=text.encode(), check=False)
                    return
                except: pass
    except: pass

def clip_paste():
    try:
        if sys.platform == 'darwin':
            return subprocess.run(['pbpaste'], capture_output=True, check=False).stdout.decode('utf-8', errors='replace')
        elif sys.platform == 'win32' or sys.platform == 'cygwin':
            return subprocess.run(['powershell', '-Command', 'Get-Clipboard'], capture_output=True, check=False).stdout.decode('utf-8', errors='replace').strip()
        else:
            for c in ['xclip -selection clipboard -o', 'xsel -ob', 'wl-paste', 'termux-clipboard-get']:
                try:
                    r = subprocess.run(shlex.split(c), capture_output=True, check=False)
                    if r.returncode == 0:
                        return r.stdout.decode('utf-8', errors='replace').strip()
                except: pass
    except: pass
    return ""

# ─── DAEMON ───
def daemon_loop(pw):
    last_raw = ""
    oneshot = {}

    log("Daemon started")
    notify("ChatCtl", "Daemon running — auto-encrypt/decrypt active")

    while True:
        try:
            text = clip_paste()
            if text and text != last_raw:
                last_raw = text
                st = load_state()

                # Case 1: Text is encrypted → decrypt (always, regardless of state)
                pt = try_decrypt(text, pw)
                if pt is not None:
                    clip_copy(pt)
                    log(f"Decrypted ({len(text)}b -> {len(pt)}b)")
                    notify("ChatCtl", f"Decrypted: {pt[:100]}")
                    last_raw = pt
                    continue

                # Case 2: Encryption ON and text NOT encrypted → encrypt for sending
                if st.get('encryption'):
                    # Don't re-encrypt if the clipboard was just set by us
                    # (prevent loop: we encrypt, clipboard changes, we see encrypted text, we decrypt...)
                    # Actually the decrypt case above handles that first
                    enc = format_encrypted(text, pw)
                    clip_copy(enc)
                    log(f"Encrypted ({len(text)}b -> {len(enc)}b)")
                    notify("ChatCtl", f"Encrypted ({len(text)} chars)")
                    last_raw = enc

            time.sleep(0.3)
        except KeyboardInterrupt:
            log("Daemon stopped")
            break
        except:
            time.sleep(1)

def cmd_daemon(args):
    pw = load_config().get('password', '')
    if not pw:
        print("  \033[31mNo key set. Run: chatctl key <passphrase>\033[0m")
        return

    # Check if already running
    if os.path.exists(PID_FILE):
        with open(PID_FILE) as f:
            old_pid = f.read().strip()
        try:
            os.kill(int(old_pid), 0)
            print(f"  \033[33mDaemon already running (PID {old_pid})\033[0m")
            print("  Run 'chatctl stop' to stop it")
            return
        except:
            os.remove(PID_FILE)

    pid = os.fork()
    if pid > 0:
        with open(PID_FILE, 'w') as f:
            f.write(str(pid))
        print(f"  \033[32mDaemon started (PID {pid})\033[0m")
        print("  Clipboard auto-processing active.")
        print("  Encryption ON  -> copy text = auto-encrypted in clipboard")
        print("  Encryption OFF -> only decrypts detected encrypted messages")
        print("  Run 'chatctl stop' to stop")
        return

    # Child: daemonize
    os.setsid()
    sys.stdin = open(os.devnull)
    sys.stdout = open(os.devnull, 'w')
    sys.stderr = open(os.devnull, 'w')
    daemon_loop(pw)

def cmd_stop(args):
    if not os.path.exists(PID_FILE):
        print("  \033[33mDaemon not running\033[0m")
        return
    with open(PID_FILE) as f:
        pid = f.read().strip()
    try:
        os.kill(int(pid), signal.SIGTERM)
        os.remove(PID_FILE)
        print(f"  \033[32mDaemon stopped (PID {pid})\033[0m")
    except:
        os.remove(PID_FILE)
        print("  \033[33mDaemon was not running (stale PID removed)\033[0m")

# ─── COMMANDS ───
def cmd_status():
    cfg = load_config()
    st = load_state()
    pw = cfg.get('password', '')
    c = "\033[32mON\033[0m" if st.get('encryption') else "\033[31mOFF\033[0m"
    running = False
    if os.path.exists(PID_FILE):
        with open(PID_FILE) as f:
            try: os.kill(int(f.read().strip()), 0); running = True
            except: pass
    d = "\033[32mrunning\033[0m" if running else "\033[31mstopped\033[0m"
    print(f"  Encryption: {c}")
    print(f"  Daemon:     {d}")
    print(f"  Key set:    {'\033[32mYes\033[0m' if pw else '\033[33mNo\033[0m'}")

def cmd_on():
    st = load_state()
    st['encryption'] = True
    save_state(st)
    print("  \033[32mEncryption ON\033[0m  — copy any text to auto-encrypt it")

def cmd_off():
    st = load_state()
    st['encryption'] = False
    save_state(st)
    print("  \033[31mEncryption OFF\033[0m — copy encrypted text to auto-decrypt only")

def cmd_key(args):
    if not args:
        print("  Usage: chatctl key <passphrase>")
        return
    pw = ' '.join(args)
    cfg = load_config()
    cfg['password'] = pw
    save_config(cfg)
    print(f"  \033[32mKey set\033[0m ({len(pw)} chars)")

def cmd_encrypt(args):
    pw = load_config().get('password', '')
    if not pw or not args:
        print("  Usage: chatctl encrypt <message>")
        return
    msg = ' '.join(args)
    result = format_encrypted(msg, pw)
    clip_copy(result)
    print(f"  \033[32m[ENCRYPTED]\033[0m {result}")
    print("  \033[90m(copied to clipboard)\033[0m")

def cmd_decrypt(args):
    pw = load_config().get('password', '')
    if not pw:
        print("  \033[31mNo key set. Run: chatctl key <passphrase>\033[0m")
        return
    msg = ' '.join(args) if args else clip_paste()
    if not msg:
        print("  Usage: chatctl decrypt <message>")
        return
    pt = try_decrypt(msg, pw)
    if pt is not None:
        print(f"  \033[32m[ENCRYPTED]\033[0m {pt}")
        clip_copy(pt)
    else:
        print(f"  \033[33m[UNENCRYPTED]\033[0m {msg}")

def cmd_watch(args):
    """Foreground watch mode (for debugging)"""
    pw = load_config().get('password', '')
    if not pw:
        print("  \033[31mNo key set. Run: chatctl key <passphrase>\033[0m")
        return
    print("  \033[90mClipboard watcher (Ctrl+C to stop)\033[0m")
    print("  \033[90mEncryption ON  -> copy = auto-encrypt | OFF -> decrypt only\033[0m")
    last = ""
    while True:
        try:
            text = clip_paste()
            if text and text != last:
                last = text
                st = load_state()
                pt = try_decrypt(text, pw)
                if pt is not None:
                    print(f"  \033[32m[ENCRYPTED]\033[0m {pt}")
                    clip_copy(pt)
                elif st.get('encryption'):
                    enc = format_encrypted(text, pw)
                    print(f"  \033[32m[ENCRYPTED]\033[0m {enc}")
                    clip_copy(enc)
            time.sleep(0.3)
        except KeyboardInterrupt:
            break
        except: pass

PLUGIN_SRC = os.path.join(CONFIG_DIR, "ChatCtl.plugin.js")

BD_DIRS = [
    os.path.expanduser("~/.config/BetterDiscord/plugins"),
    os.path.expanduser("~/.config/Vencord/plugins"),
    os.path.expanduser("~/.config/vencord/plugins"),
    os.path.expanduser("~/.config/Vencord/userplugins"),
    os.path.expanduser("~/.config/BetterDiscord/userplugins"),
]

def cmd_plugin(args):
    if not args or args[0] in ('-h', '--help'):
        print("Usage: chatctl plugin <install|uninstall>")
        return
    sub = args[0]

    if sub == 'install':
        if not os.path.exists(PLUGIN_SRC):
            # Try to find the plugin near the script
            script_dir = os.path.dirname(os.path.abspath(__file__))
            alt = os.path.join(script_dir, "ChatCtl.plugin.js")
            if os.path.exists(alt):
                shutil.copy2(alt, PLUGIN_SRC)
            else:
                print("  \033[31mPlugin file not found. Run --full-install or check ~/.chatctl/\033[0m")
                return

        installed = False
        for d in BD_DIRS:
            os.makedirs(d, exist_ok=True)
            dst = os.path.join(d, "ChatCtl.plugin.js")
            shutil.copy2(PLUGIN_SRC, dst)
            print(f"  \033[32mInstalled to:\033[0m {dst}")
            installed = True

        if not installed:
            print("  \033[33mNo BetterDiscord/Vencord plugin directory found.\033[0m")
            print("  \033[33mCreate one manually or copy the file:\033[0m")
            print(f"  \033[90m  cp {PLUGIN_SRC} <plugin-dir>/ChatCtl.plugin.js\033[0m")
        else:
            print("  \033[32mPlugin installed! Restart Discord (Ctrl+R) or enable in BD settings.\033[0m")

    elif sub == 'uninstall':
        removed = False
        for d in BD_DIRS:
            dst = os.path.join(d, "ChatCtl.plugin.js")
            if os.path.exists(dst):
                os.remove(dst)
                print(f"  \033[31mRemoved:\033[0m {dst}")
                removed = True
        if not removed:
            print("  \033[33mPlugin not found in any plugin directory\033[0m")
    else:
        print(f"  \033[31mUnknown subcommand: {sub}\033[0m")

# ─── MAIN ───
def main():
    if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
        print("Usage: chatctl <command> [args]")
        print()
        print("  on              Enable encryption")
        print("  off             Disable encryption")
        print("  status          Show status (encryption + daemon)")
        print("  key <pw>        Set shared passphrase")
        print("  daemon          Start background daemon (auto-clipboard)")
        print("  stop            Stop the daemon")
        print("  encrypt <m>     Encrypt a message")
        print("  decrypt <m>     Decrypt a message")
        print("  watch           Foreground clipboard watcher (debug)")
        print("  plugin install  Install BetterDiscord plugin")
        print("  plugin uninstall  Remove BetterDiscord plugin")
        print()
        print("Quick start:")
        print("  chatctl key \"mysecret\"           # set key (same for friend)")
        print("  chatctl plugin install            # install BetterDiscord plugin")
        print("  # Now Discord auto-encrypts/decrypts messages!")
        print("  # [ENCRYPTED] labels on encrypted messages")
        print("  # [UNENCRYPTED] labels on plaintext messages")
        return

    cmd = sys.argv[1]
    args = sys.argv[2:]

    cmds = {
        'on': lambda a: cmd_on(),
        'off': lambda a: cmd_off(),
        'status': lambda a: cmd_status(),
        'key': cmd_key,
        'encrypt': cmd_encrypt,
        'decrypt': cmd_decrypt,
        'watch': lambda a: cmd_watch(a),
        'daemon': lambda a: cmd_daemon(a),
        'stop': lambda a: cmd_stop(a),
        'plugin': cmd_plugin,
    }

    if cmd in cmds:
        cmds[cmd](args)
    else:
        print(f"  \033[31mUnknown command: {cmd}\033[0m")
        print("  Run 'chatctl' for help")

if __name__ == '__main__':
    main()
