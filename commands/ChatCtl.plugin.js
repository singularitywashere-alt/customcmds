/**
 * @name ChatCtl
 * @description Auto-encrypt/decrypt Discord messages — anti chat control
 * @version 1.0.0
 * @author singularity
 * @website https://github.com/singularitywashere-alt/customcmds
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const CONFIG_PATH = path.join(require('os').homedir(), '.chatctl', 'config.json');

let config = {};
let observer = null;
let cssAdded = false;
let unpatchSend = null;

function loadConfig() {
    try {
        config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf-8'));
    } catch(e) {
        config = {};
    }
}

function getPassword() {
    return config.password || '';
}

// ─── CRYPTO (compatible with chatctl Python v2) ───

function deriveKey(password, salt) {
    return crypto.pbkdf2Sync(password, salt, 200000, 32, 'sha256');
}

function encrypt(plaintext, password) {
    const salt = crypto.randomBytes(16);
    const key = deriveKey(password, salt);
    const iv = crypto.randomBytes(16);
    const pt = Buffer.from(plaintext, 'utf-8');

    let keystream = Buffer.alloc(0);
    let counter = 0n;
    while (keystream.length < pt.length) {
        const buf = Buffer.alloc(8);
        buf.writeBigUInt64BE(counter++);
        const h = crypto.createHmac('sha256', key).update(iv).update(buf).digest();
        keystream = Buffer.concat([keystream, h]);
    }

    const ct = Buffer.alloc(pt.length);
    for (let i = 0; i < pt.length; i++) ct[i] = pt[i] ^ keystream[i];

    const sig = crypto.createHmac('sha256', key).update(salt).update(iv).update(ct).digest();
    return Buffer.concat([salt, iv, ct, sig]).toString('base64');
}

function decrypt(encoded, password) {
    const raw = Buffer.from(encoded, 'base64');
    if (raw.length < 64) throw new Error('too short');
    const salt = raw.subarray(0, 16);
    const iv = raw.subarray(16, 32);
    const sig = raw.subarray(-32);
    const ct = raw.subarray(32, -32);
    const key = deriveKey(password, salt);

    const expected = crypto.createHmac('sha256', key).update(salt).update(iv).update(ct).digest();
    if (!sig.equals(expected)) throw new Error('bad hmac');

    let keystream = Buffer.alloc(0);
    let counter = 0n;
    while (keystream.length < ct.length) {
        const buf = Buffer.alloc(8);
        buf.writeBigUInt64BE(counter++);
        const h = crypto.createHmac('sha256', key).update(iv).update(buf).digest();
        keystream = Buffer.concat([keystream, h]);
    }

    const pt = Buffer.alloc(ct.length);
    for (let i = 0; i < ct.length; i++) pt[i] = ct[i] ^ keystream[i];
    return pt.toString('utf-8');
}

function tryDecrypt(text, password) {
    if (!password || !text) return null;
    const m = text.match(/^([a-zA-Z0-9]{6,16})\/\/(.+)$/);
    if (!m) return null;
    try {
        return decrypt(m[2], password);
    } catch(e) {
        return null;
    }
}

function formatEncrypted(plaintext, password) {
    const prefix = crypto.randomBytes(5).toString('hex').slice(0, 10);
    return prefix + '///' + encrypt(plaintext, password);
}

// ─── PLUGIN ───

module.exports = class ChatCtl {
    getName() { return 'ChatCtl'; }
    getDescription() { return 'Auto-encrypt outgoing / decrypt incoming messages with [ENCRYPTED]/[UNENCRYPTED] labels'; }
    getVersion() { return '1.0'; }
    getAuthor() { return 'singularity'; }

    start() {
        loadConfig();

        if (!getPassword()) {
            BdApi.showToast('ChatCtl: No key set. Run "chatctl key <passphrase>" in terminal.', { type: 'warning' });
            return;
        }

        // Patch message sending to auto-encrypt
        this._patchSend();

        // Watch DOM for new messages (decrypt + label)
        this._startObserver();

        // Inject CSS
        if (!cssAdded) {
            BdApi.injectCSS('chatctl-css', `
                .chatctl-encrypted .chatctl-badge {
                    display: inline-block;
                    font-size: 10px;
                    font-weight: 700;
                    padding: 1px 6px;
                    border-radius: 3px;
                    margin-right: 6px;
                    text-transform: uppercase;
                    vertical-align: middle;
                    letter-spacing: 0.5px;
                }
                .chatctl-encrypted .chatctl-badge {
                    color: #43b581;
                    background: rgba(67, 181, 129, 0.15);
                }
                .chatctl-unencrypted .chatctl-badge {
                    color: #f04747;
                    background: rgba(240, 71, 71, 0.15);
                }
                .chatctl-encrypted .chatctl-text {
                    color: #43b581;
                }
                .chatctl-unencrypted .chatctl-text {
                    color: #f04747;
                }
            `);
            cssAdded = true;
        }

        BdApi.showToast('ChatCtl active — messages auto-encrypted', { type: 'info' });
    }

    stop() {
        if (unpatchSend) { unpatchSend(); unpatchSend = null; }
        if (observer) { observer.disconnect(); observer = null; }
        if (cssAdded) {
            BdApi.clearCSS('chatctl-css');
            cssAdded = false;
        }
    }

    onSwitch() {
        // Discord switched channels — our observer needs to pick up existing messages
        setTimeout(() => this._processExisting(), 1000);
    }

    _patchSend() {
        try {
            const MessageActions = BdApi.findModuleByProps('sendMessage', 'sendBotMessage');
            if (!MessageActions) {
                console.warn('[ChatCtl] Could not find MessageActions module');
                return;
            }

            const pw = getPassword;
            unpatchSend = BdApi.monkeyPatch(MessageActions, 'sendMessage', {
                before: (data) => {
                    if (!pw()) return;
                    const args = data.methodArguments;
                    const channelId = args[0];
                    const message = args[1];
                    if (message && message.content && typeof message.content === 'string') {
                        if (!message.content.match(/^[a-zA-Z0-9]{6,16}\/\//)) {
                            message.content = formatEncrypted(message.content, pw());
                        }
                    }
                }
            });
        } catch(e) {
            console.error('[ChatCtl] Patch failed:', e);
        }
    }

    _startObserver() {
        observer = new MutationObserver((mutations) => {
            for (const m of mutations) {
                for (const node of m.addedNodes) {
                    if (node.nodeType === 1) {
                        this._processNode(node);
                    }
                }
            }
        });
        observer.observe(document.body, { childList: true, subtree: true });
        // Process existing messages after a short delay
        setTimeout(() => this._processExisting(), 2000);
    }

    _processNode(node) {
        // Find message content elements
        const contentEls = node.matches
            ? (node.matches('[class*="messageContent"]') ? [node] : node.querySelectorAll('[class*="messageContent"]'))
            : node.querySelectorAll ? node.querySelectorAll('[class*="messageContent"]') : [];

        for (const el of contentEls) {
            if (el.chatctlProcessed) continue;
            el.chatctlProcessed = true;

            const text = el.textContent.trim();
            if (!text) continue;

            const pw = getPassword();
            if (!pw) {
                this._setLabel(el, text, false);
                continue;
            }

            const decrypted = tryDecrypt(text, pw);
            if (decrypted !== null) {
                // Message IS encrypted → show decrypted
                el.innerHTML = `<span class="chatctl-encrypted"><span class="chatctl-badge">ENCRYPTED</span><span class="chatctl-text">${this._escapeHtml(decrypted)}</span></span>`;

                // Mark the parent message container
                let parent = el.parentElement;
                while (parent) {
                    if (parent.matches && parent.matches('[class*="message"]')) {
                        parent.style.borderLeft = '2px solid #43b581';
                        break;
                    }
                    parent = parent.parentElement;
                }
            } else {
                // Not encrypted → show with [UNENCRYPTED] label
                // But don't label our own messages (they'll look like regular messages)
                // Actually, let's label ALL unencrypted messages
                this._setLabel(el, text, false);
            }
        }
    }

    _setLabel(el, text, isEncrypted) {
        if (!text) return;
        const badge = isEncrypted ? 'ENCRYPTED' : 'UNENCRYPTED';
        const cls = isEncrypted ? 'chatctl-encrypted' : 'chatctl-unencrypted';
        el.innerHTML = `<span class="${cls}"><span class="chatctl-badge">${badge}</span><span class="chatctl-text">${this._escapeHtml(text)}</span></span>`;
    }

    _escapeHtml(text) {
        return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    _processExisting() {
        const els = document.querySelectorAll('[class*="messageContent"]');
        for (const el of els) {
            this._processNode(el);
        }
    }

    _patchReceive() {
        // Try to also patch the Gateway event handler to decrypt before rendering
        // This is more reliable than DOM manipulation
        try {
            const dispatcher = BdApi.findModuleByProps('dispatch', 'subscribe');
            if (!dispatcher) return;

            const _dispatch = dispatcher.dispatch;
            const self = this;
            dispatcher.dispatch = function(event) {
                if (event && event.type === 'MESSAGE_CREATE' && event.message) {
                    const msg = event.message;
                    const pw = getPassword();
                    if (pw && msg.content) {
                        const decrypted = tryDecrypt(msg.content, pw);
                        if (decrypted !== null) {
                            // Store original for later use
                            msg._chatctlOriginal = msg.content;
                            msg.content = decrypted;
                            msg._chatctlDecrypted = true;
                        } else {
                            msg._chatctlDecrypted = false;
                        }
                    }
                }
                return _dispatch.apply(this, arguments);
            };
        } catch(e) {
            console.warn('[ChatCtl] Dispatcher patch failed, falling back to DOM', e);
        }
    }

    // observerBased start
    _start() {
        this._patchSend();
        this._patchReceive();
        this._startObserver();
    }

    getSettingsPanel() {
        const panel = document.createElement('div');
        panel.style.padding = '16px';
        panel.innerHTML = `
            <h3>ChatCtl</h3>
            <p>Key: <strong>${getPassword() ? 'set' : 'NOT SET'}</strong></p>
            <p style="color:#888;font-size:12px">Set key in terminal: chatctl key &lt;passphrase&gt;</p>
            <p style="color:#888;font-size:12px">This plugin reads ~/.chatctl/config.json</p>
        `;
        return panel;
    }
};
