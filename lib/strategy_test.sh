#!/usr/bin/env bash
# Auto-test strategies by applying each in turn and probing a URL set with
# parallel curl jobs. Mirrors the parallel-curl bench from Zapret-Manager.

TEST_URLS_FILE="${DATA_DIR}/test-urls.txt"
TEST_TIMEOUT="${TEST_TIMEOUT:-4}"
TEST_PARALLEL="${TEST_PARALLEL:-8}"

#
# data/test-urls.txt format:
#   <tag>  <url>
# Lines starting with '#' or blank are ignored.
# Tag values: general | youtube | discord | ai
#

_test_urls_for_scope() {
    local scope="$1"
    [[ -r $TEST_URLS_FILE ]] || die "Missing $TEST_URLS_FILE"
    if [[ $scope == all ]]; then
        awk '!/^[[:space:]]*(#|$)/ { print $2 }' "$TEST_URLS_FILE"
    else
        awk -v s="$scope" '!/^[[:space:]]*(#|$)/ && $1 == s { print $2 }' "$TEST_URLS_FILE"
    fi
}

_test_strategy_ids_for_scope() {
    local scope="$1"
    case "$scope" in
        discord) strategies_list_discord | cut -f1 ;;
        youtube) strategies_ensure_youtube; strategies_list_youtube | cut -f1 ;;
        general|ai|all) strategies_list_builtin | cut -f1 ;;
        *) die "Unknown test scope: $scope" ;;
    esac
}

_probe_url() {
    # Print "<http_code> <total_seconds>" — silent on stderr.
    local url="$1"
    curl --max-time "$TEST_TIMEOUT" \
         --silent --output /dev/null \
         --insecure \
         --connect-timeout "$TEST_TIMEOUT" \
         --write-out '%{http_code} %{time_total}\n' \
         "$url" 2>/dev/null || printf '000 %s\n' "$TEST_TIMEOUT"
}

_run_probes() {
    # Args: <url1> <url2> ...
    # Stdout: one "<code> <time>" line per URL. Up to TEST_PARALLEL at once.
    local pids=() i=0
    local tmpd; tmpd=$(mktemp -d)
    for url in "$@"; do
        _probe_url "$url" >"$tmpd/$i" &
        pids+=($!)
        i=$((i+1))
        if (( ${#pids[@]} >= TEST_PARALLEL )); then
            wait "${pids[0]}" 2>/dev/null
            pids=("${pids[@]:1}")
        fi
    done
    wait 2>/dev/null
    cat "$tmpd"/* 2>/dev/null
    rm -rf "$tmpd"
}

_score_results() {
    # Reads "<code> <time>" lines, prints "<successes> <total> <avg_time>".
    awk '
        { total++; if ($1 ~ /^(200|206|301|302|304)$/) { ok++; sum += $2 } }
        END {
            avg = (ok > 0 ? sum/ok : 99.0)
            printf "%d %d %.3f\n", ok+0, total+0, avg
        }
    '
}

strategy_test_run() {
    require_root
    ensure_dirs
    zapret_is_installed || die "zapret is not installed."
    local scope="${1:-all}"
    local urls; urls=$(_test_urls_for_scope "$scope")
    [[ -n $urls ]] || die "No URLs configured for scope: $scope"
    local ids; ids=$(_test_strategy_ids_for_scope "$scope")
    [[ -n $ids ]] || die "No strategies available for scope: $scope"

    local ts; ts=$(date +%Y%m%d-%H%M%S)
    local csv="${LOG_DIR}/results-${scope}-${ts}.csv"
    : >"$csv"
    printf 'strategy,ok,total,avg_sec\n' >>"$csv"

    info "Testing scope=$scope, parallel=$TEST_PARALLEL, timeout=${TEST_TIMEOUT}s"
    info "URLs: $(printf '%s\n' "$urls" | wc -l), strategies: $(printf '%s\n' "$ids" | wc -l)"

    local id score
    while IFS= read -r id; do
        [[ -z $id ]] && continue
        printf '%s→ %s%s ' "$C_CYAN" "$id" "$C_RESET"
        strategies_apply "$id" >/dev/null 2>&1 || { warn "apply failed: $id"; continue; }
        sleep 1   # let nfqws settle after restart
        score=$(_run_probes $urls | _score_results)
        local ok_n total avg
        read -r ok_n total avg <<<"$score"
        printf '%sok=%d/%d avg=%.3fs%s\n' "$C_GREEN" "$ok_n" "$total" "$avg" "$C_RESET"
        printf '%s,%d,%d,%.3f\n' "$id" "$ok_n" "$total" "$avg" >>"$csv"
    done <<<"$ids"

    info "Ranked results (top 10):"
    {
        head -n1 "$csv"
        tail -n+2 "$csv" | sort -t, -k2,2nr -k4,4n
    } | column -t -s, | head -n 11

    local best; best=$(tail -n+2 "$csv" | sort -t, -k2,2nr -k4,4n | head -n1 | cut -d, -f1)
    if [[ -n $best ]]; then
        printf '\n%sBest:%s %s — apply it now? [y/N] ' "$C_BOLD" "$C_RESET" "$best"
        local ans; read -r ans || true
        if [[ ${ans,,} == y* ]]; then
            strategies_apply "$best"
        else
            info "Best result not applied. Re-apply manually: nzapret-manager apply $best"
        fi
    fi
    ok "Full results: $csv"
}
