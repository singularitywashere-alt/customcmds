function attack
    set -l connections 200
    set -l duration 300
    set -l config_file "$HOME/.config/attack_links.txt"

    argparse -n attack 'c/connections=' 't/time=' 'h/help' -- $argv; or return

    if set -q _flag_help
        echo "Usage: attack <url_or_alias> [-c <connections>] [-t <time>]"
        echo "Example: attack --testserver -c 100"
        return 0
    end

    set -l target $argv[1]
    if test -z "$target"
        echo "Error: No target URL or alias specified."
        return 1
    end

    if string match -q "--*" "$target"
        set -l alias (string replace -- "--" "" $target)
        if test -f "$config_file"
            set -l found (grep "^$alias=" "$config_file" | cut -d'=' -f2-)
            if test -n "$found"
                set target $found
            else
                echo "Error: Alias '$alias' not found in $config_file"
                return 1
            end
        end
    end

    if set -q _flag_connections; set connections $_flag_connections; end
    if set -q _flag_time; set duration $_flag_time; end

    if test $duration -gt 10000
        while test $duration -gt 0
            set -l current_run (math "min($duration, 10000)")
            echo "Running attack on $target for $current_run seconds..."
            siege -c $connections -t "$current_run"S $target
            set duration (math "$duration - $current_run")
        end
    else
        siege -c $connections -t "$duration"S $target
    end
end
