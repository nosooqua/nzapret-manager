#!/usr/bin/env bash
# tar.gz snapshots of zapret config + state + nzapret-manager hosts blocks.

backup_create() {
    require_root
    ensure_dirs
    [[ -d $ZAPRET_DIR ]] || die "$ZAPRET_DIR is missing; nothing to back up."
    local ts; ts=$(date +%Y%m%d-%H%M%S)
    local archive="${BACKUP_DIR}/zapret-${ts}.tar.gz"
    local hosts_snip; hosts_snip=$(mktemp)
    awk -v p="$HOSTS_MARKER_PREFIX" '
        index($0, p) == 1 { keep = ($0 ~ / begin ===$/) ? 1 : keep; print; if ($0 ~ / end ===$/) keep = 0; next }
        keep              { print }
    ' "$HOSTS_FILE" >"$hosts_snip"

    info "Creating $archive"
    local -a paths=("${ZAPRET_CONFIG#/}" "${STATE_DIR#/}" "${ZAPRET_UNIT#/}")
    # Optional bits — included only if present.
    [[ -f $DOH_CONFIG          ]] && paths+=("${DOH_CONFIG#/}")
    [[ -f $DOH_RESOLVED_DROPIN ]] && paths+=("${DOH_RESOLVED_DROPIN#/}")
    [[ -f $ZAPRET_USER_LIST    ]] && paths+=("${ZAPRET_USER_LIST#/}")
    [[ -f $ZAPRET_USER_EXCLUDE ]] && paths+=("${ZAPRET_USER_EXCLUDE#/}")
    [[ -f $ZAPRET_USER_IPBAN   ]] && paths+=("${ZAPRET_USER_IPBAN#/}")
    tar -czf "$archive" \
        --transform 's,^/,/,' \
        -C / \
        "${paths[@]}" 2>/dev/null
    tar -rzf "$archive" --transform "s,.*,nzapret-manager-hosts.snippet," "$hosts_snip" 2>/dev/null || \
        tar -czf "$archive" --transform "s,.*,nzapret-manager-hosts.snippet," "$hosts_snip" 2>/dev/null
    rm -f "$hosts_snip"
    ok "Backup: $archive"
}

backup_list() {
    ensure_dirs
    local f
    if ! compgen -G "${BACKUP_DIR}/*.tar.gz" >/dev/null; then
        printf 'No backups in %s\n' "$BACKUP_DIR"
        return 0
    fi
    ls -1t "${BACKUP_DIR}"/*.tar.gz
}

backup_restore() {
    require_root
    local archive="$1"
    [[ -f $archive ]] || die "No such archive: $archive"
    info "Stopping zapret.service"
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    info "Restoring $archive"
    tar -xzf "$archive" -C / 2>/dev/null
    # Restore hosts snippet (drop any existing nzapret-manager markers first)
    local snip; snip=$(tar -xzf "$archive" -O nzapret-manager-hosts.snippet 2>/dev/null || true)
    if [[ -n $snip ]]; then
        local tmp; tmp=$(mktemp)
        awk -v p="$HOSTS_MARKER_PREFIX" '
            index($0, p) == 1 { skip = ($0 ~ / begin ===$/) ? 1 : skip; if ($0 ~ / end ===$/) { skip = 0; next } next }
            !skip { print }
        ' "$HOSTS_FILE" >"$tmp"
        printf '%s\n' "$snip" >>"$tmp"
        install -m 0644 "$tmp" "$HOSTS_FILE"
        rm -f "$tmp"
    fi
    systemctl daemon-reload
    systemctl start "$SERVICE_NAME" 2>/dev/null || warn "Service failed to start; check journal."
    ok "Restored from $archive"
}

backup_prune() {
    require_root
    local keep="${1:-5}"
    ensure_dirs
    local f; local i=0
    while IFS= read -r f; do
        i=$((i+1))
        (( i > keep )) || continue
        rm -f -- "$f"
        info "Pruned $f"
    done < <(ls -1t "${BACKUP_DIR}"/*.tar.gz 2>/dev/null)
}
