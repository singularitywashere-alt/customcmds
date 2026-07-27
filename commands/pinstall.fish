function pinstall
    argparse -n pinstall 'l/list' 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: pinstall <tool> [version]"
        echo "  -l     List available tools"
        echo ""
        echo "Examples:"
        echo "  pinstall ffuf"
        echo "  pinstall nuclei 3.2.0"
        return
    end

    if set -q _flag_list
        echo "Available tools:"
        echo "  ffuf       - Fast web fuzzer (Go)"
        echo "  gobuster   - Directory/file/DNS busting (Go)"
        echo "  httpx      - HTTP probe (Go)"
        echo "  nuclei     - Template-based scanner (Go)"
        echo "  subfinder  - Subdomain discovery (Go)"
        echo "  naabu      - Port scanner (Go)"
        echo "  amass      - Attack surface mapping (Go)"
        echo "  sqlmap     - SQL injection automation (Python)"
        echo "  nmap       - Port scanner (source, requires compile)"
        return
    end

    if test (count $argv) -lt 1
        echo "Error: specify a tool name or -l"
        return 1
    end

    set tool $argv[1]
    set version ""
    if test (count $argv) -ge 2; set version $argv[2]; end

    # GitHub info: repo, asset pattern, binary name
    switch $tool
        case ffuf
            set repo "ffuf/ffuf"
            set pattern "ffuf_*linux_amd64.tar.gz"
            set bin "ffuf"
        case gobuster
            set repo "OJ/gobuster"
            set pattern "gobuster_*linux_amd64.tar.gz"
            set bin "gobuster"
        case httpx
            set repo "projectdiscovery/httpx"
            set pattern "httpx_*linux_amd64.zip"
            set bin "httpx"
        case nuclei
            set repo "projectdiscovery/nuclei"
            set pattern "nuclei_*linux_amd64.zip"
            set bin "nuclei"
        case subfinder
            set repo "projectdiscovery/subfinder"
            set pattern "subfinder_*linux_amd64.zip"
            set bin "subfinder"
        case naabu
            set repo "projectdiscovery/naabu"
            set pattern "naabu_*linux_amd64.zip"
            set bin "naabu"
        case amass
            set repo "owasp-amass/amass"
            set pattern "amass_*linux_amd64.zip"
            set bin "amass"
        case sqlmap
            set repo "sqlmapproject/sqlmap"
            set pattern "sqlmap-*.tar.gz"
            set bin "sqlmap.py"
        case nmap
            echo (set_color yellow)"nmap has no static binary. Attempting source compile..."(set_color normal)
            set repo "nmap/nmap"
            set pattern ""
            set bin ""
        case '*'
            echo (set_color red)"Unknown tool: $tool"(set_color normal)
            echo "Run 'pinstall -l' for available tools"
            return 1
    end

    set install_dir "$HOME/.local/bin"
    mkdir -p $install_dir

    # Add to PATH if not already
    if not string match -q -- "*$install_dir*" "$PATH"
        set -U fish_user_paths $install_dir $fish_user_paths 2>/dev/null
        echo (set_color yellow)"  Added $install_dir to PATH (restart shell or run: exec fish)"(set_color normal)
    end

    if test "$tool" = "nmap"
        # Try to download and compile nmap
        if not command -v gcc >/dev/null 2>&1
            echo (set_color red)"  gcc not found — cannot compile nmap"(set_color normal)
            return 1
        end
        if test -z "$version"; set version "master"; end
        echo (set_color cyan)"  Downloading nmap source..."(set_color normal)
        curl -sL "https://github.com/nmap/nmap/archive/refs/heads/$version.tar.gz" -o /tmp/nmap-src.tar.gz
        if not test -f /tmp/nmap-src.tar.gz; echo (set_color red)"  Download failed"(set_color normal); return 1; end
        mkdir -p /tmp/nmap-build && tar xzf /tmp/nmap-src.tar.gz -C /tmp/nmap-build --strip-components=1
        echo (set_color cyan)"  Compiling nmap (this will take a while)..."(set_color normal)
        cd /tmp/nmap-build && ./configure --prefix=$install_dir/.. --without-zenmap > /dev/null 2>&1
        make -j4 > /dev/null 2>&1
        make install > /dev/null 2>&1
        if command -v nmap >/dev/null 2>&1; or test -f $install_dir/nmap
            echo (set_color green)"  nmap installed!"(set_color normal)
        else
            echo (set_color red)"  nmap compile failed"(set_color normal)
        end
        rm -rf /tmp/nmap-build /tmp/nmap-src.tar.gz
        return
    end

    if test "$tool" = "sqlmap"
        echo (set_color cyan)"  Downloading sqlmap..."(set_color normal)
        set dl_url "https://github.com/sqlmapproject/sqlmap/archive/refs/heads/master.tar.gz"
        curl -sL "$dl_url" -o /tmp/sqlmap.tar.gz
        if not test -f /tmp/sqlmap.tar.gz
            echo (set_color red)"  Download failed"(set_color normal)
            return 1
        end
        mkdir -p /tmp/sqlmap-extract
        tar xzf /tmp/sqlmap.tar.gz -C /tmp/sqlmap-extract --strip-components=1
        cp /tmp/sqlmap-extract/sqlmap.py $install_dir/sqlmap
        chmod +x $install_dir/sqlmap
        rm -rf /tmp/sqlmap.tar.gz /tmp/sqlmap-extract
        echo (set_color green)"  sqlmap installed to $install_dir/sqlmap"(set_color normal)
        return
    end

    # Go tools — get latest version from GitHub API if not specified
    if test -z "$version"
        set api_url "https://api.github.com/repos/$repo/releases/latest"
        set version (curl -sL "$api_url" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null)
        if test -z "$version"
            echo (set_color red)"  Could not fetch latest version"(set_color normal)
            return 1
        end
    end

    echo (set_color cyan)"  Downloading $tool $version..."(set_color normal)

    # Get release assets
    set api_url "https://api.github.com/repos/$repo/releases/tags/$version"
    set asset_url (curl -sL "$api_url" 2>/dev/null | python3 -c "
import sys, json, fnmatch
try:
    d = json.load(sys.stdin)
    for a in d.get('assets', []):
        name = a['name']
        if fnmatch.fnmatch(name, '$pattern'):
            print(a['browser_download_url'])
            break
except: pass
" 2>/dev/null)

    if test -z "$asset_url"
        # Try direct URL pattern as fallback
        set asset_url "https://github.com/$repo/releases/download/$version/$pattern"
        # Replace * with version-specific pattern
        set asset_url (echo "$asset_url" | sed "s/\*/$version/")
    end

    set tmpfile "/tmp/$tool-download"
    curl -sL "$asset_url" -o "$tmpfile" 2>/dev/null

    if not test -f "$tmpfile"; or test (stat -c%s "$tmpfile" 2>/dev/null) -lt 100
        echo (set_color red)"  Download failed"(set_color normal)
        rm -f "$tmpfile"
        return 1
    end

    set tmpdir "/tmp/$tool-install"
    mkdir -p $tmpdir

    if string match -q '*.zip' "$asset_url"
        command -v unzip >/dev/null 2>&1; and unzip -qo "$tmpfile" -d $tmpdir 2>/dev/null; or echo (set_color yellow)"  unzip not available"(set_color normal)
    else
        tar xzf "$tmpfile" -C $tmpdir 2>/dev/null
    end

    # Find the binary
    set installed 0
    for f in (find $tmpdir -name "$bin" -type f 2>/dev/null)
        cp "$f" "$install_dir/$bin"
        chmod +x "$install_dir/$bin"
        set installed 1
    end

    # If not found by exact name, try any binary
    if test $installed -eq 0
        for f in (find $tmpdir -type f -executable 2>/dev/null)
            cp "$f" "$install_dir/$tool"
            chmod +x "$install_dir/$tool"
            set installed 1
            break
        end
    end

    rm -f "$tmpfile"
    rm -rf $tmpdir

    if test $installed -eq 1
        echo (set_color green)"  $tool installed to $install_dir/$bin"(set_color normal)
        echo (set_color brblack)"  Run 'exec fish' to add to PATH or use full path: $install_dir/$bin"(set_color normal)
    else
        echo (set_color red)"  Failed to find binary in archive"(set_color normal)
        return 1
    end
end
