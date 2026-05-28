#!/usr/bin/env bash
# Strategy catalog and apply/preview logic.
#
# A strategy is a file under data/strategies/ where each non-blank, non-comment
# line is one nfqws CLI option. `--new` lines separate sections. When applied,
# all lines are joined with spaces and written as NFQWS_OPT="..." into the
# zapret config between marker lines, so re-applying is idempotent.

YT_CACHE_DIR="${STRATEGY_DIR}/youtube"

strategies_list_builtin() {
    # echoes "id<TAB>label<TAB>path" for v1..v9
    local f
    for f in "${STRATEGY_DIR}"/v[0-9].conf; do
        [[ -e $f ]] || continue
        local id; id=$(basename "$f" .conf)
        local label; label=$(_strategy_label "$f")
        printf '%s\t%s\t%s\n' "$id" "$label" "$f"
    done
}

strategies_list_discord() {
    local f
    for f in "${STRATEGY_DIR}/discord"/Dv*.conf; do
        [[ -e $f ]] || continue
        local id; id=$(basename "$f" .conf)
        local label; label=$(_strategy_label "$f")
        printf '%s\t%s\t%s\n' "$id" "$label" "$f"
    done | sort -t v -k2 -n
}

strategies_list_youtube() {
    local f
    [[ -d $YT_CACHE_DIR ]] || return 0
    for f in "${YT_CACHE_DIR}"/Yv*.conf; do
        [[ -e $f ]] || continue
        local id; id=$(basename "$f" .conf)
        local label; label=$(_strategy_label "$f")
        printf '%s\t%s\t%s\n' "$id" "$label" "$f"
    done | sort -t v -k2 -n
}

strategies_list_all() {
    strategies_list_builtin
    strategies_list_youtube
    strategies_list_discord
}

_strategy_label() {
    awk '/^[[:space:]]*#/ { sub(/^[[:space:]]*#[[:space:]]*/, ""); print; exit }' "$1"
}

strategies_path_for_id() {
    local id="$1"
    local candidates=(
        "${STRATEGY_DIR}/${id}.conf"
        "${STRATEGY_DIR}/discord/${id}.conf"
        "${YT_CACHE_DIR}/${id}.conf"
    )
    local c
    for c in "${candidates[@]}"; do
        [[ -f $c ]] && { printf '%s\n' "$c"; return 0; }
    done
    return 1
}

_strategy_body_oneline() {
    # Strip comments and blank lines; join with single spaces.
    grep -Ev '^[[:space:]]*(#|$)' "$1" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//'
}

_strategy_required_ports() {
    # Read filter-tcp= / filter-udp= values from the strategy file.
    # Outputs:  TCP=...  UDP=...
    local file="$1"
    local tcp_ports udp_ports
    tcp_ports=$(grep -oE '\-\-filter-tcp=[0-9,\-]+' "$file" | sed 's/--filter-tcp=//' | tr '\n' ',' | sed 's/,$//')
    udp_ports=$(grep -oE '\-\-filter-udp=[0-9,\-]+' "$file" | sed 's/--filter-udp=//' | tr '\n' ',' | sed 's/,$//')
    printf 'TCP=%s\nUDP=%s\n' "$tcp_ports" "$udp_ports"
}

_merge_ports() {
    # union of two comma-separated port lists, with deduplication preserved order
    local a="$1" b="$2"
    printf '%s\n' "$a" "$b" | tr ',' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ',' | sed 's/,$//'
}

strategies_apply() {
    require_root
    local id="$1"
    local path
    path=$(strategies_path_for_id "$id") || die "Unknown strategy id: $id"
    [[ -f $ZAPRET_CONFIG ]] || die "$ZAPRET_CONFIG not found; run: zapretozz install"

    local body; body=$(_strategy_body_oneline "$path")
    local ports; ports=$(_strategy_required_ports "$path")
    local strat_tcp strat_udp
    strat_tcp=$(awk -F= '/^TCP=/{print $2}' <<<"$ports")
    strat_udp=$(awk -F= '/^UDP=/{print $2}' <<<"$ports")

    local merged_tcp merged_udp
    merged_tcp=$(_merge_ports "80,443" "$strat_tcp")
    merged_udp=$(_merge_ports "443,50000-50100,19294-19344" "$strat_udp")

    info "Applying strategy $id"
    local tmp; tmp=$(mktemp)
    # 1) strip out any previously injected block
    awk -v B="$STRATEGY_BEGIN" -v E="$STRATEGY_END" '
        $0 == B { skip = 1; next }
        $0 == E { skip = 0; next }
        !skip   { print }
    ' "$ZAPRET_CONFIG" >"$tmp"
    # 2) append fresh block
    {
        printf '\n%s\n' "$STRATEGY_BEGIN"
        printf 'NFQWS_PORTS_TCP=%s\n'  "$merged_tcp"
        printf 'NFQWS_PORTS_UDP=%s\n'  "$merged_udp"
        printf 'NFQWS_OPT="%s"\n' "$body"
        printf '%s\n' "$STRATEGY_END"
    } >>"$tmp"
    install -m 0644 "$tmp" "$ZAPRET_CONFIG"
    rm -f "$tmp"

    state_set ACTIVE_STRATEGY "$id"

    if service_exists; then
        info "Restarting zapret.service"
        systemctl restart "$SERVICE_NAME" || warn "Service failed to restart cleanly."
    fi
    ok "Strategy $id applied."
}

strategies_show_current() {
    local active; active=$(state_get ACTIVE_STRATEGY 2>/dev/null || true)
    if [[ -z $active ]]; then
        printf 'No strategy applied yet.\n'
    else
        printf 'Active strategy: %s%s%s\n' "$C_GREEN" "$active" "$C_RESET"
        local p; p=$(strategies_path_for_id "$active" 2>/dev/null) || return 0
        printf '%s\n' "$C_GRAY"
        cat "$p"
        printf '%s\n' "$C_RESET"
    fi
}

strategies_preview() {
    local id="$1"
    local path
    path=$(strategies_path_for_id "$id") || die "Unknown strategy id: $id"
    printf '%s──── %s (%s) ────%s\n' "$C_CYAN" "$id" "$path" "$C_RESET"
    cat "$path"
}

#
# YouTube strategy fetch & parse.
#
# Upstream ListStrYou (from Zapret-Manager) is a text catalog where each
# strategy entry begins with a "#Yv<NN>" marker and the following lines
# (until the next "#Yv" or EOF) are nfqws args. We split it into per-file
# entries on first use and cache under data/strategies/youtube/.
#

strategies_fetch_youtube() {
    require_root
    install -d -m 0755 "$YT_CACHE_DIR"
    info "Fetching YouTube strategy catalog"
    local raw; raw=$(mktemp)
    if ! curl -fsSL --retry 3 --max-time 20 -o "$raw" "$YT_STRATEGY_URL"; then
        rm -f "$raw"
        die "Failed to fetch $YT_STRATEGY_URL"
    fi
    awk -v outdir="$YT_CACHE_DIR" '
        function flush(   p) {
            if (id != "") {
                p = outdir "/" id ".conf"
                printf("# %s — fetched from ListStrYou\n", id) > p
                for (i = 0; i < n; i++) print buf[i] > p
                close(p)
                id = ""; n = 0
            }
        }
        /^[[:space:]]*#[[:space:]]*Yv[0-9]+/ {
            flush()
            match($0, /Yv[0-9]+/); id = substr($0, RSTART, RLENGTH)
            next
        }
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*#/ { next }
        { if (id != "") buf[n++] = $0 }
        END { flush() }
    ' "$raw"
    rm -f "$raw"
    local count; count=$(ls "$YT_CACHE_DIR"/Yv*.conf 2>/dev/null | wc -l)
    ok "Cached ${count} YouTube strategies under ${YT_CACHE_DIR}"
}

strategies_ensure_youtube() {
    # On-demand fetch if no Yv* files cached yet.
    if ! ls "$YT_CACHE_DIR"/Yv*.conf >/dev/null 2>&1; then
        strategies_fetch_youtube
    fi
}
