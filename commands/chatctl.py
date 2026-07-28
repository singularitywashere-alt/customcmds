#!/usr/bin/env python3
"""chatctl — Anti chat control encryption tool (cross-platform Python)"""
import sys, os, json, base64, hashlib, secrets, subprocess, time, re, struct, signal, shlex

CONFIG_DIR = os.path.expanduser("~/.chatctl")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")
STATE_FILE = os.path.join(CONFIG_DIR, "state.json")

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

# ─── CRYPTO (stdlib only: PBKDF2 + HMAC-SHA256 stream cipher) ───
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

# ─── MESSAGE FORMAT ───
ENC_PATTERN = re.compile(r'^([a-zA-Z0-9]{6,16})///')

def format_encrypted(plaintext: str, password: str) -> str:
    prefix = random_prefix(10)
    ct = encrypt(plaintext, password)
    return f"{prefix}///{ct}"

def try_decrypt(text: str, password: str):
    m = ENC_PATTERN.match(text)
    if not m:
        return None
    prefix = m.group(1)
    payload = text[m.end():]
    if not payload:
        return None
    try:
        pt = decrypt(payload, password)
        return pt
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

# ─── COMMANDS ───
def cmd_status():
    cfg = load_config()
    st = load_state()
    pw = cfg.get('password', '')
    c = "\033[32mON\033[0m" if st.get('encryption') else "\033[31mOFF\033[0m"
    print(f"  Encryption: {c}")
    print(f"  Key set:    {'\033[32mYes\033[0m' if pw else '\033[33mNo\033[0m'}")
    print(f"  Config:     {CONFIG_FILE}")

def cmd_on():
    st = load_state()
    st['encryption'] = True
    save_state(st)
    print("  \033[32mEncryption enabled\033[0m")

def cmd_off():
    st = load_state()
    st['encryption'] = False
    save_state(st)
    print("  \033[31mEncryption disabled\033[0m")

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
    if not pw:
        print("  \033[31mNo key set. Run: chatctl key <passphrase>\033[0m")
        return
    msg = ' '.join(args) if args else sys.stdin.read().strip()
    if not msg:
        print("  Usage: chatctl encrypt <message>")
        return
    result = format_encrypted(msg, pw)
    prefix = "\033[32m[ENCRYPTED]\033[0m"
    print(f"  {prefix} {result}")
    clip_copy(result)
    print("  \033[90m(copied to clipboard)\033[0m")

def cmd_decrypt(args):
    pw = load_config().get('password', '')
    if not pw:
        print("  \033[31mNo key set. Run: chatctl key <passphrase>\033[0m")
        return
    msg = ' '.join(args) if args else sys.stdin.read().strip()
    if not msg:
        msg = clip_paste()
    if not msg:
        print("  Usage: chatctl decrypt <message> (or pipe it)")
        return
    pt = try_decrypt(msg, pw)
    if pt is not None:
        # Extract original message (strip random_prefix///)
        print(f"  \033[32m[ENCRYPTED]\033[0m {pt}")
        clip_copy(pt)
        print("  \033[90m(decrypted text copied to clipboard)\033[0m")
    else:
        print(f"  \033[33m[UNENCRYPTED]\033[0m {msg}")

def cmd_send(args):
    pw = load_config().get('password', '')
    if not pw:
        print("  \033[31mNo key set. Run: chatctl key <passphrase>\033[0m")
        return
    msg = ' '.join(args) if args else ''
    if not msg:
        print("  Enter message (Ctrl+D to send):")
        msg = sys.stdin.read().strip()
    st = load_state()
    if st.get('encryption') and msg:
        result = format_encrypted(msg, pw)
        prefix = "\033[32m[ENCRYPTED]\033[0m"
        print(f"\n  {prefix} {result}")
        clip_copy(result)
        print("  \033[90m(copied — paste into Discord)\033[0m")
    else:
        print(f"  \033[33m[UNENCRYPTED]\033[0m {msg}")
        clip_copy(msg)

def cmd_watch():
    pw = load_config().get('password', '')
    if not pw:
        print("  \033[31mNo key set. Run: chatctl key <passphrase>\033[0m")
        return
    print("  \033[90mWatching clipboard for encrypted messages... (Ctrl+C to stop)\033[0m")
    last = ""
    while True:
        try:
            text = clip_paste()
            if text and text != last:
                last = text
                pt = try_decrypt(text, pw)
                if pt is not None:
                    print(f"  \033[32m[ENCRYPTED]\033[0m {pt}")
                    clip_copy(pt)
            time.sleep(1)
        except KeyboardInterrupt:
            print("\n  \033[90mStopped\033[0m")
            break
        except: pass

def cmd_process(args):
    """Process clipboard text for decryption (for pipe/automation)"""
    pw = load_config().get('password', '')
    if not pw:
        return
    text = clip_paste()
    if not text:
        text = sys.stdin.read().strip()
    if text:
        pt = try_decrypt(text, pw)
        if pt is not None:
            print(f"[ENCRYPTED] {pt}")
        else:
            print(f"[UNENCRYPTED] {text}")

# ─── MAIN ───
def main():
    if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
        print("Usage: chatctl <command> [args]")
        print("")
        print("  on           Enable encryption")
        print("  off          Disable encryption")
        print("  status       Show encryption status")
        print("  key <pw>     Set shared passphrase")
        print("  encrypt <m>  Encrypt a message")
        print("  decrypt <m>  Decrypt a message")
        print("  send <m>     Send (encrypt if ON, plain if OFF)")
        print("  watch        Watch clipboard for encrypted messages")
        print("  process      Decrypt clipboard or stdin (for piping)")
        return

    cmd = sys.argv[1]
    args = sys.argv[2:]

    # Some commands ignore args
    def noop(args): pass
    cmds = {
        'status': lambda a: cmd_status(),
        'on': lambda a: cmd_on(),
        'off': lambda a: cmd_off(),
        'key': cmd_key,
        'encrypt': cmd_encrypt,
        'decrypt': cmd_decrypt,
        'send': cmd_send,
        'watch': cmd_watch,
        'process': cmd_process,
    }

    if cmd in cmds:
        cmds[cmd](args)
    else:
        print(f"  \033[31mUnknown command: {cmd}\033[0m")
        print("  Run 'chatctl' for help")

if __name__ == '__main__':
    main()
