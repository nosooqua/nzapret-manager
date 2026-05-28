#!/usr/bin/env bash
# TUI screens.

menu_header() {
    clear
    header "zapretozz — DPI bypass manager"
    printf '  Service: %s\n' "$(service_status_line)"
    if zapret_is_installed; then
        local commit; commit=$(state_get ZAPRET_COMMIT 2>/dev/null || echo "?")
        printf '  zapret:  %sinstalled%s (commit %s)\n' "$C_GREEN" "$C_RESET" "$commit"
    else
        printf '  zapret:  %snot installed%s\n' "$C_YELLOW" "$C_RESET"
    fi
    local active; active=$(state_get ACTIVE_STRATEGY 2>/dev/null || true)
    printf '  Strategy:%s\n' " ${active:-—}"
    printf '\n'
}

menu_main() {
    while true; do
        menu_header
        printf '  %s1)%s Install / Update / Remove zapret\n' "$C_CYAN" "$C_RESET"
        printf '  %s2)%s Strategies\n'                       "$C_CYAN" "$C_RESET"
        printf '  %s3)%s /etc/hosts blocks\n'                "$C_CYAN" "$C_RESET"
        printf '  %s4)%s Service control\n'                  "$C_CYAN" "$C_RESET"
        printf '  %s5)%s Backup & restore\n'                 "$C_CYAN" "$C_RESET"
        printf '  %s0)%s Exit\n\n'                           "$C_CYAN" "$C_RESET"
        local c; read -rp "Choose: " c || break
        case "$c" in
            1) menu_install ;;
            2) menu_strategies ;;
            3) menu_hosts ;;
            4) menu_service ;;
            5) menu_backup ;;
            0|q|Q) break ;;
            *) warn "Invalid choice"; sleep 1 ;;
        esac
    done
}

menu_install() {
    while true; do
        menu_header
        printf '  Install / Update / Remove zapret\n\n'
        if zapret_is_installed; then
            printf '  %s1)%s Update zapret (git pull + rebuild)\n' "$C_CYAN" "$C_RESET"
            printf '  %s2)%s Remove zapret\n'                       "$C_CYAN" "$C_RESET"
        else
            printf '  %s1)%s Install zapret\n'                      "$C_CYAN" "$C_RESET"
        fi
        printf '  %s0)%s Back\n\n'                                  "$C_CYAN" "$C_RESET"
        local c; read -rp "Choose: " c
        case "$c" in
            1) if zapret_is_installed; then zapret_update; else zapret_install; fi; pause ;;
            2) if zapret_is_installed; then zapret_remove; pause; fi ;;
            0) return ;;
            *) warn "Invalid"; sleep 1 ;;
        esac
    done
}

menu_strategies() {
    while true; do
        menu_header
        printf '  Strategies\n\n'
        printf '  %s1)%s Apply built-in v1..v9\n'           "$C_CYAN" "$C_RESET"
        printf '  %s2)%s Apply YouTube (Yv*)\n'             "$C_CYAN" "$C_RESET"
        printf '  %s3)%s Apply Discord (Dv1..Dv17)\n'       "$C_CYAN" "$C_RESET"
        printf '  %s4)%s Auto-test & pick best\n'           "$C_CYAN" "$C_RESET"
        printf '  %s5)%s Show current strategy\n'           "$C_CYAN" "$C_RESET"
        printf '  %s6)%s Refresh YouTube catalog\n'         "$C_CYAN" "$C_RESET"
        printf '  %s0)%s Back\n\n'                          "$C_CYAN" "$C_RESET"
        local c; read -rp "Choose: " c
        case "$c" in
            1) _menu_pick_apply builtin ;;
            2) strategies_ensure_youtube; _menu_pick_apply youtube ;;
            3) _menu_pick_apply discord ;;
            4) _menu_auto_test ;;
            5) strategies_show_current; pause ;;
            6) strategies_fetch_youtube; pause ;;
            0) return ;;
            *) warn "Invalid"; sleep 1 ;;
        esac
    done
}

_menu_pick_apply() {
    local kind="$1"
    local rows
    case "$kind" in
        builtin) rows=$(strategies_list_builtin) ;;
        youtube) rows=$(strategies_list_youtube) ;;
        discord) rows=$(strategies_list_discord) ;;
    esac
    if [[ -z $rows ]]; then
        warn "No strategies available for $kind"
        pause; return
    fi
    clear
    header "Pick a $kind strategy"
    local -a ids=()
    local i=1 id label _path
    while IFS=$'\t' read -r id label _path; do
        printf '  %s%2d)%s %-8s %s\n' "$C_CYAN" "$i" "$C_RESET" "$id" "$label"
        ids+=("$id")
        i=$((i+1))
    done <<<"$rows"
    printf '\n  %s 0)%s Back\n\n' "$C_CYAN" "$C_RESET"
    local c; read -rp "Apply (number, or 'p N' to preview): " c
    if [[ $c == p\ * ]]; then
        local n=${c#p }
        [[ $n =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#ids[@]} )) && strategies_preview "${ids[$((n-1))]}"
        pause; _menu_pick_apply "$kind"; return
    fi
    [[ $c == 0 ]] && return
    [[ $c =~ ^[0-9]+$ ]] || { warn "Invalid"; sleep 1; return; }
    (( c >= 1 && c <= ${#ids[@]} )) || { warn "Out of range"; sleep 1; return; }
    strategies_apply "${ids[$((c-1))]}"
    pause
}

_menu_auto_test() {
    clear
    header "Auto-test strategies"
    printf '  %s1)%s general (v1..v9 vs general URLs)\n'   "$C_CYAN" "$C_RESET"
    printf '  %s2)%s youtube (Yv* vs youtube URLs)\n'      "$C_CYAN" "$C_RESET"
    printf '  %s3)%s discord (Dv* vs discord URLs)\n'      "$C_CYAN" "$C_RESET"
    printf '  %s4)%s all (built-in v* vs all URLs)\n'      "$C_CYAN" "$C_RESET"
    printf '  %s0)%s Back\n\n'                             "$C_CYAN" "$C_RESET"
    local c; read -rp "Choose scope: " c
    case "$c" in
        1) strategy_test_run general ;;
        2) strategy_test_run youtube ;;
        3) strategy_test_run discord ;;
        4) strategy_test_run all ;;
        0) return ;;
        *) warn "Invalid"; sleep 1; return ;;
    esac
    pause
}

menu_hosts() {
    while true; do
        menu_header
        printf '  /etc/hosts blocks (toggle to enable/disable)\n\n'
        local -a names=()
        local i=1 b
        while IFS= read -r b; do
            local mark=' '
            hosts_block_enabled "$b" && mark="${C_GREEN}✓${C_RESET}"
            printf '  %s%2d)%s [%b] %-18s %s\n' "$C_CYAN" "$i" "$C_RESET" "$mark" "$b" "$(hosts_label_for "$b")"
            names+=("$b")
            i=$((i+1))
        done < <(hosts_blocks_available)
        printf '\n  %sA)%s Enable all   %sN)%s Disable all   %s0)%s Back\n\n' \
            "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
        local c; read -rp "Toggle (number) / A / N / 0: " c
        case "$c" in
            0) return ;;
            a|A) for b in "${names[@]}"; do hosts_block_enabled "$b" || hosts_enable "$b"; done; pause ;;
            n|N) hosts_disable_all; pause ;;
            *)
                if [[ $c =~ ^[0-9]+$ ]] && (( c >= 1 && c <= ${#names[@]} )); then
                    local sel="${names[$((c-1))]}"
                    if hosts_block_enabled "$sel"; then hosts_disable "$sel"; else hosts_enable "$sel"; fi
                else
                    warn "Invalid"; sleep 1
                fi
                ;;
        esac
    done
}

menu_service() {
    while true; do
        menu_header
        printf '  Service control\n\n'
        printf '  %s1)%s start    %s2)%s stop     %s3)%s restart\n' \
            "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
        printf '  %s4)%s enable   %s5)%s disable\n' "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
        printf '  %s6)%s status   %s7)%s tail journal (last 100)\n' "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
        printf '  %s0)%s Back\n\n' "$C_CYAN" "$C_RESET"
        local c; read -rp "Choose: " c
        case "$c" in
            1) service_start;   pause ;;
            2) service_stop;    pause ;;
            3) service_restart; pause ;;
            4) service_enable;  pause ;;
            5) service_disable; pause ;;
            6) service_show_status; pause ;;
            7) service_tail_log 100; pause ;;
            0) return ;;
            *) warn "Invalid"; sleep 1 ;;
        esac
    done
}

menu_backup() {
    while true; do
        menu_header
        printf '  Backup & restore\n\n'
        printf '  %s1)%s Create backup\n'    "$C_CYAN" "$C_RESET"
        printf '  %s2)%s List backups\n'     "$C_CYAN" "$C_RESET"
        printf '  %s3)%s Restore from file\n' "$C_CYAN" "$C_RESET"
        printf '  %s4)%s Prune (keep 5 newest)\n' "$C_CYAN" "$C_RESET"
        printf '  %s0)%s Back\n\n' "$C_CYAN" "$C_RESET"
        local c; read -rp "Choose: " c
        case "$c" in
            1) backup_create; pause ;;
            2) backup_list; pause ;;
            3) printf '  Path to archive: '; local p; read -r p; [[ -n $p ]] && backup_restore "$p"; pause ;;
            4) backup_prune 5; pause ;;
            0) return ;;
            *) warn "Invalid"; sleep 1 ;;
        esac
    done
}
