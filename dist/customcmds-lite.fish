# --- Paths ---
set -g __CC_CONFIG_DIR "$HOME/.config/customcmds"
set -g __CC_MANIFEST "$__CC_CONFIG_DIR/manifest"
set -g __CC_FUNCS "$HOME/.config/fish/functions"

# --- Utilities ---

set -g __CC_REPO_SLUG "singularitywashere-alt/customcmds"

function __cc_init
    if not test -d "$__CC_CONFIG_DIR"
        mkdir -p "$__CC_CONFIG_DIR"
    end
    if not command -v curl >/dev/null
        echo (set_color red)"Error:"(set_color normal)" curl is required" >&2
        return 1
    end
    if not command -v python3 >/dev/null
        echo (set_color red)"Error:"(set_color normal)" python3 is required" >&2
        return 1
    end
end

function __cc_repo_slug
    echo "$__CC_REPO_SLUG"
end

function __cc_raw_base
    set -l slug (__cc_repo_slug) || return 1
    echo "https://raw.githubusercontent.com/$slug/main"
end

function __cc_fetch_raw -a url
    curl -sfL "$url" 2>/dev/null
end

function __cc_fetch_index
    if not set -q __CC_REFRESH; and test -f "$__CC_CONFIG_DIR/index.json"
        cat "$__CC_CONFIG_DIR/index.json"
        return 0
    end
    set -e __CC_REFRESH 2>/dev/null
    set -l b (__cc_raw_base) || return 1
    set -l resp (__cc_fetch_raw "$b/index.json")
    if test $status -eq 0 -a -n "$resp"
        echo "$resp" | python3 -c "import sys,json; json.load(sys.stdin)['commands']" 2>/dev/null
        and echo "$resp"
        and echo "$resp" > "$__CC_CONFIG_DIR/index.json"
    end
end

function __cc_fetch_cmd
    set -l b (__cc_raw_base) || return 1
    __cc_fetch_raw "$b/commands/$argv[1].fish"
end

# --- JSON helpers (index.json) ---

function __cc_idx_names
    python3 -c "
import sys, json
try:
    for n in json.load(sys.stdin).get('commands', {}):
        print(n)
except:
    pass
" 2>/dev/null
end

function __cc_idx_get -a name field
    python3 -c "
import sys, json
try:
    v = json.load(sys.stdin).get('commands', {}).get('$name', {}).get('$field', '')
    if v: print(v)
except:
    pass
" 2>/dev/null
end

function __cc_idx_has -a name
    python3 -c "
import sys, json
try:
    d = json.load(sys.stdin).get('commands', {})
    sys.exit(0 if '$name' in d else 1)
except:
    sys.exit(1)
" 2>/dev/null
end

# --- Manifest helpers (pipe-delimited: name|version|change) ---

function __cc_man_read
    if test -f "$__CC_MANIFEST"
        cat "$__CC_MANIFEST"
    end
end

function __cc_man_write
    if set -q argv[1]
        printf '%s\n' $argv > "$__CC_MANIFEST"
    else
        echo -n > "$__CC_MANIFEST"
    end
end

function __cc_man_add -a name ver change
    set -l hash (__cc_file_hash "$__CC_FUNCS/$name.fish")
    if test -z "$hash"; set hash "-"; end
    set -l lines
    set -l found 0
    for line in (__cc_man_read)
        set -l p (string split '|' -- $line)
        if test "$p[1]" = "$name"
            set line "$name|$ver|$change|$hash"
            set found 1
        end
        set -a lines $line
    end
    if test "$found" = 0
        set -a lines "$name|$ver|$change|$hash"
    end
    __cc_man_write $lines
end

function __cc_man_rm -a name
    set -l lines
    for line in (__cc_man_read)
        set -l p (string split '|' -- $line)
        if test "$p[1]" != "$name"
            set -a lines $line
        end
    end
    __cc_man_write $lines
end

function __cc_man_get -a name field
    switch $field
        case ver; set idx 2
        case change; set idx 3
        case hash; set idx 4
        case '*'; return 1
    end
    for line in (__cc_man_read)
        set -l p (string split '|' -- $line)
        if test "$p[1]" = "$name"
            echo $p[$idx]
            return 0
        end
    end
    return 1
end

function __cc_man_has -a name
    for line in (__cc_man_read)
        set -l p (string split '|' -- $line)
        if test "$p[1]" = "$name"
            return 0
        end
    end
    return 1
end

function __cc_man_names
    for line in (__cc_man_read)
        set -l p (string split '|' -- $line)
        echo $p[1]
    end
end

# --- File hash ---

function __cc_file_hash
    sha1sum "$argv[1]" 2>/dev/null | string trim | string split ' ' -f1
end

# --- Interactive selection ---

function __cc_pick -a prompt
    set -l items $argv[2..-1]
    set -l count (count $items)
    if test $count -eq 0
        return 1
    end
    for i in (seq $count)
        echo "$items[$i] [$i]" >&2
    end
    echo (set_color brblack)"  All [A]   None [N]"(set_color normal) >&2
    while true
        read -p "echo '$prompt'" choice
        if test -z "$choice"
            continue
        end
        if string match -qi 'A' -- $choice
            for i in (seq $count)
                echo $i
            end
            return 0
        else if string match -qi 'N' -- $choice
            return 1
        else
            set -l sel
            set -l ok 1
            for part in (string split ',' -- $choice)
                set -l n (string trim -- $part)
                if string match -qr '^\d+$' -- $n
                    if test $n -ge 1 -a $n -le $count
                        set -a sel $n
                    else
                        echo "Invalid: $n" >&2; set ok 0
                    end
                else
                    echo "Invalid: $part" >&2; set ok 0
                end
            end
            if test "$ok" = 1
                echo $sel
                return 0
            end
        end
        echo "" >&2
    end
end

# --- Status ---

function __cc_status
    __cc_init
    set -l all
    for f in "$__CC_FUNCS"/*.fish
        set -l n (basename "$f" .fish)
        if test "$n" != "customcmds"
            set -a all $n
        end
    end
    set -l total (count $all)
    set -l repo_cmds (__cc_man_names)
    set -l repo_n (count $repo_cmds)
    set -l custom_n (math "$total - $repo_n")
    if test $custom_n -lt 0; set custom_n 0; end

    echo (set_color cyan)"Status:"(set_color normal)" $total commands ($repo_n from repo, $custom_n custom)"

    set -l idx (__cc_fetch_index) 2>/dev/null
    if test -z "$idx"
        echo (set_color yellow)"Note:"(set_color normal)" unable to check for updates (repo index not found)"
        return 0
    end

    set -l outdated
    for cmd in $repo_cmds
        set -l lv (__cc_man_get $cmd ver)
        set -l rv (echo "$idx" | __cc_idx_get $cmd version)
        if test -n "$rv" -a -n "$lv" -a "$lv" != "$rv"
            set -a outdated $cmd
        end
    end

    set -l oc (count $outdated)
    if test $oc -gt 0
        set -l p; if test $oc -ne 1; set p "s"; end
        echo (set_color yellow)"Updates available for $oc command$p:"(set_color normal)
        for cmd in $outdated
            set -l lv (__cc_man_get $cmd ver)
            set -l rv (echo "$idx" | __cc_idx_get $cmd version)
            echo "  "(set_color cyan)$cmd(set_color normal)" ($lv -> $rv)"
        end
        echo (set_color brblack)"  -> run 'customcmds --updinf -t <name>' for details, 'customcmds --update' to update"(set_color normal)
    else if test $repo_n -gt 0
        echo (set_color green)"All repo commands are up to date."(set_color normal)
    end
end

# --- Import ---

function __cc_import
    __cc_init
    set -l idx (__cc_fetch_index)
    if test -z "$idx"
        echo (set_color red)"Error:"(set_color normal)" Could not fetch repo index." >&2
        return 1
    end

    set -l avail (echo "$idx" | __cc_idx_names)
    if test (count $avail) -eq 0
        echo (set_color yellow)"No commands available in the repo."(set_color normal)
        return 0
    end

    set -l todo
    for c in $avail
        if not test -f "$__CC_FUNCS/$c.fish"
            set -a todo $c
        end
    end

    if test (count $todo) -eq 0
        echo (set_color green)"All repo commands are already installed."(set_color normal)
        return 0
    end

    set -l pick_items
    for c in $todo
        set -a pick_items (set_color cyan)$c(set_color normal)
    end
    echo (set_color cyan)"Available commands:"(set_color normal) >&2
    set -l indices (__cc_pick "Select (e.g. 1, 3, 8): " $pick_items)
    if test $status -ne 0
        echo (set_color yellow)"Import cancelled."(set_color normal) >&2
        return 0
    end

    set -l sel
    for i in $indices
        set -a sel $todo[$i]
    end

    set -l ok 0
    for c in $sel
        echo -n "  "(set_color cyan)$c(set_color normal)"... "
        set -l content (__cc_fetch_cmd $c)
        if test -z "$content"
            echo (set_color red)"failed"(set_color normal) >&2
            continue
        end
        echo "$content" > "$__CC_FUNCS/$c.fish"
        set -l v (echo "$idx" | __cc_idx_get $c version)
        set -l ch (echo "$idx" | __cc_idx_get $c change)
        __cc_man_add $c "$v" "$ch"
        echo (set_color green)"done"(set_color normal)
        set ok (math $ok + 1)
    end

    set -l p; if test $ok -ne 1; set p "s"; end
    echo (set_color green)"Imported $ok command$p."(set_color normal)
end

# --- Update ---

function __cc_update
    __cc_init
    set -l idx (__cc_fetch_index)
    if test -z "$idx"
        echo (set_color red)"Error:"(set_color normal)" Could not fetch repo index." >&2
        return 1
    end

    set -l outdated
    for cmd in (__cc_man_names)
        set -l lv (__cc_man_get $cmd ver)
        set -l rv (echo "$idx" | __cc_idx_get $cmd version)
        if test -n "$rv" -a -n "$lv" -a "$lv" != "$rv"
            set -a outdated $cmd
        end
    end

    set -l oc (count $outdated)
    if test $oc -eq 0
        echo (set_color green)"All commands are up to date."(set_color normal)
        return 0
    end

    set -l p; if test $oc -ne 1; set p "s"; end
    echo (set_color yellow)"Outdated command$p ($oc):"(set_color normal) >&2

    set -l pick_items
    for c in $outdated
        set -l ch (echo "$idx" | __cc_idx_get $c change)
        set -a pick_items (set_color cyan)"$c - $ch"(set_color normal)
    end

    set -l indices (__cc_pick "Select (e.g. 1, 3, 8): " $pick_items)
    if test $status -ne 0
        echo (set_color yellow)"Update cancelled."(set_color normal) >&2
        return 0
    end

    set -l ok 0
    for i in $indices
        set -l c $outdated[$i]
        echo -n "  "(set_color cyan)$c(set_color normal)"... "
        set -l content (__cc_fetch_cmd $c)
        if test -z "$content"
            echo (set_color red)"failed"(set_color normal) >&2
            continue
        end
        echo "$content" > "$__CC_FUNCS/$c.fish"
        set -l nv (echo "$idx" | __cc_idx_get $c version)
        set -l nc (echo "$idx" | __cc_idx_get $c change)
        __cc_man_add $c $nv $nc
        echo (set_color green)"done"(set_color normal)
        set ok (math $ok + 1)
    end

    set -l p; if test $ok -ne 1; set p "s"; end
    echo (set_color green)"Updated $ok command$p."(set_color normal)
end

# --- Updinf ---

function __cc_updinf -a name
    __cc_init
    if not test -f "$__CC_FUNCS/$name.fish"
        echo (set_color red)"Error:"(set_color normal)" '$name' not found" >&2
        return 1
    end

    set -l idx (__cc_fetch_index)
    if test -z "$idx"
        echo (set_color red)"Error:"(set_color normal)" Could not fetch repo index." >&2
        return 1
    end

    set -l rv (echo "$idx" | __cc_idx_get $name version)
    if test -z "$rv"
        echo (set_color red)"Error:"(set_color normal)" '$name' not found in repo" >&2
        return 1
    end

    set -l rd (echo "$idx" | __cc_idx_get $name description)
    set -l rc (echo "$idx" | __cc_idx_get $name change)
    set -l lv (__cc_man_get $name ver)
    if test -z "$lv"; set lv (set_color brblack)"not tracked"(set_color normal); end

    echo (set_color cyan)"$name"(set_color normal)" (local: $lv, remote: $rv)"
    echo (set_color brblack)"  description:"(set_color normal)" $rd"
    echo (set_color brblack)"  update:"(set_color normal)" $rc"
end

# --- List remote ---

function __cc_list_remote
    __cc_init
    set -l idx (__cc_fetch_index)
    if test -z "$idx"
        echo (set_color red)"Error:"(set_color normal)" Could not fetch repo index." >&2
        return 1
    end

    set -l avail (echo "$idx" | __cc_idx_names)
    if test (count $avail) -eq 0
        echo (set_color yellow)"No commands available in the repo."(set_color normal)
        return 0
    end

    set -l remote
    for c in $avail
        if not test -f "$__CC_FUNCS/$c.fish"
            set -a remote $c
        end
    end

    if test (count $remote) -eq 0
        echo (set_color green)"All repo commands are already installed."(set_color normal)
        return 0
    end

    echo (set_color cyan)"Available for import:"(set_color normal)
    for c in $remote
        set -l d (echo "$idx" | __cc_idx_get $c description)
        echo "  "(set_color cyan)"$c"(set_color normal)
        if test -n "$d"
            echo "       $d"
        end
    end
    echo (set_color brblack)"  ($(count $remote) command$(if test (count $remote) -ne 1; echo s; end) available.)"(set_color normal)
end

# --- Self update ---

function __cc_self_update
    echo -n "  Fetching latest version... "
    set -l resp (curl -sfL "https://raw.githubusercontent.com/$__CC_REPO_SLUG/main/dist/customcmds-lite.fish")
    if test -z "$resp"
        echo (set_color red)"failed"(set_color normal) >&2
        return 1
    end
    echo (set_color green)"done"(set_color normal)
    echo "$resp" > "$__CC_FUNCS/customcmds.fish"
    echo (set_color green)"Updated customcmds to the latest version."(set_color normal)
    echo (set_color brblack)"  Restart your shell or run 'source ~/.config/fish/functions/customcmds.fish'"(set_color normal)
end

# --- Open helper ---

function __customcmds_open
    if set -q EDITOR
        command $EDITOR $argv
    else if set -q VISUAL
        command $VISUAL $argv
    else
        xdg-open $argv
    end
end

# --- Main ---

function customcmds -d "Manage custom fish functions"
    argparse -n customcmds 'h/help' 'rm' 'rs' 'cr' 'o' 't=' 'n=' 'd=' 'import' 'status' 'update' 'updinf' 'list-remote' 'refresh' 'self-update' -- $argv
    or return

    if set -q _flag_refresh
        rm -f "$__CC_CONFIG_DIR/index.json"
        set -g __CC_REFRESH 1
    end

    if set -q _flag_help
        echo "Usage: customcmds [options]"
        echo ""
        echo "Options:"
        echo "  -h, --help                  Show this help"
        echo "  -rm  -t <name>              Remove a function file"
        echo "  -rs  -t <name>              Reset a function to empty stub"
        echo "  -cr  -n <name> [-d <desc>]  Create a new function"
        echo "  -o   -t <name>              Open a function file in editor"
        echo "  --status                    Show command statistics and available updates"
        echo "  --import                    Import commands from the repo"
        echo "  --update                    Update outdated commands from the repo"
        echo "  --updinf -t <name>          Show update information for a command"
        echo "  --list-remote               List available commands from the repo"
        echo "  --refresh                   Force re-fetch remote index"
        echo "  --self-update               Update customcmds itself from the repo"
        echo ""
        echo "Examples:"
        echo "  customcmds                              List all commands"
        echo "  customcmds -o -t mycmd                  Open mycmd.fish"
        echo "  customcmds --status                     Show command status"
        echo "  customcmds --import                     Import from repo"
        echo "  customcmds --update                     Update all outdated"
        echo "  customcmds --list-remote                List available commands"
        echo "  customcmds --self-update                Update customcmds itself"
        return
    end

    if set -q _flag_self_update
        __cc_self_update
        return
    end

    if set -q _flag_rm
        if not set -q _flag_t
            echo (set_color red)"Error:"(set_color normal)" -t (target) is required with -rm" >&2
            return 1
        end
        set -l target "$HOME/.config/fish/functions/$_flag_t.fish"
        if test -f "$target"
            rm "$target"
            __cc_man_rm $_flag_t
            echo (set_color green)"Removed '$_flag_t'"(set_color normal)
        else
            echo (set_color red)"Error:"(set_color normal)" '$_flag_t' not found" >&2
            return 1
        end
    else if set -q _flag_rs
        if not set -q _flag_t
            echo (set_color red)"Error:"(set_color normal)" -t (target) is required with -rs" >&2
            return 1
        end
        set -l target "$HOME/.config/fish/functions/$_flag_t.fish"
        if test -f "$target"
            printf "function %s\n\nend\n" "$_flag_t" > "$target"
            echo (set_color green)"Reset '$_flag_t'"(set_color normal)
            if set -q _flag_o
                __customcmds_open "$target"
            end
        else
            echo (set_color red)"Error:"(set_color normal)" '$_flag_t' not found" >&2
            return 1
        end
    else if set -q _flag_cr
        if not set -q _flag_n
            echo (set_color red)"Error:"(set_color normal)" -n (name) is required with -cr" >&2
            return 1
        end
        set -l target "$HOME/.config/fish/functions/$_flag_n.fish"
        if test -f "$target"
            echo (set_color red)"Error:"(set_color normal)" '$_flag_n' already exists" >&2
            return 1
        end
        if set -q _flag_d
            printf "function %s -d \"%s\"\n\nend\n" "$_flag_n" "$_flag_d" > "$target"
        else
            printf "function %s\n\nend\n" "$_flag_n" > "$target"
        end
        echo (set_color green)"Created '$_flag_n'"(set_color normal)
        if set -q _flag_o
            __customcmds_open "$target"
        end
    else if set -q _flag_o
        if not set -q _flag_t
            echo (set_color red)"Error:"(set_color normal)" -t (target) is required with -o" >&2
            return 1
        end
        set -l target "$HOME/.config/fish/functions/$_flag_t.fish"
        if test -f "$target"
            __customcmds_open "$target"
        else
            echo (set_color red)"Error:"(set_color normal)" '$_flag_t' not found" >&2
            return 1
        end
    else if set -q _flag_status
        __cc_status
    else if set -q _flag_import
        __cc_import
    else if set -q _flag_update
        __cc_update
    else if set -q _flag_updinf
        if not set -q _flag_t
            echo (set_color red)"Error:"(set_color normal)" -t (target) is required with --updinf" >&2
            return 1
        end
        __cc_updinf $_flag_t
    else if set -q _flag_list_remote
        __cc_list_remote
    else
        echo (set_color cyan)"Custom commands:"(set_color normal)
        for f in "$HOME"/.config/fish/functions/*.fish
            set -l name (basename "$f" .fish)
            echo "  "(set_color cyan)"$name"(set_color normal)
        end
    end
end
