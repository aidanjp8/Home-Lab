#!/usr/bin/env bash
# ============================================================
# node-health.sh — Proxmox node health report
# Reports: CPU temp, RAM, ZFS pool status, disk usage, load
# Usage: ./node-health.sh [--dry-run]
# Schedule: crontab — 0 * * * * (hourly) or as needed
# ============================================================
set -euo pipefail
source "$(dirname "$0")/../../shared/lib.sh"
init_script "node-health" "$@"

# --- Config ---
CPU_TEMP_WARN="${CPU_TEMP_WARN:-75}"    # °C — warn threshold
CPU_TEMP_CRIT="${CPU_TEMP_CRIT:-90}"   # °C — critical threshold
DISK_USAGE_WARN="${DISK_USAGE_WARN:-85}" # % full — warn threshold

require_cmds pvesh df free uptime

# ============================================================
# CPU Temperature
# ============================================================
check_cpu_temp() {
    log_section "CPU Temperature"

    if command -v sensors &>/dev/null; then
        local temp_raw
        temp_raw=$(sensors 2>/dev/null | awk '/^Core|^Package/{print $0}' | head -20)
        log "$temp_raw"

        # Extract highest reported temp
        local max_temp
        max_temp=$(sensors 2>/dev/null \
            | grep -oP '(?<=\+)\d+\.\d+(?=°C)' \
            | sort -n | tail -1 | cut -d. -f1)

        if (( max_temp >= CPU_TEMP_CRIT )); then
            warn "CPU temp CRITICAL: ${max_temp}°C (threshold: ${CPU_TEMP_CRIT}°C)"
        elif (( max_temp >= CPU_TEMP_WARN )); then
            warn "CPU temp elevated: ${max_temp}°C (threshold: ${CPU_TEMP_WARN}°C)"
        else
            log "CPU temp OK: ${max_temp}°C"
        fi
    else
        # Fallback: read from thermal zone
        local zone temp_mc temp_c
        for zone in /sys/class/thermal/thermal_zone*/temp; do
            temp_mc=$(cat "$zone")
            temp_c=$(( temp_mc / 1000 ))
            log "Thermal zone $(basename "$(dirname "$zone")"): ${temp_c}°C"
        done
        log "Tip: install lm-sensors for detailed CPU core temps"
    fi
}

# ============================================================
# Memory
# ============================================================
check_memory() {
    log_section "Memory"
    local mem_total mem_used mem_free mem_pct
    read -r mem_total mem_used mem_free < <(free -m | awk '/^Mem:/{print $2, $3, $4}')
    mem_pct=$(( (mem_used * 100) / mem_total ))
    log "RAM: ${mem_used}MB used / ${mem_total}MB total (${mem_pct}%)"

    local swap_total swap_used
    read -r swap_total swap_used < <(free -m | awk '/^Swap:/{print $2, $3}')
    if (( swap_total > 0 )); then
        local swap_pct=$(( (swap_used * 100) / swap_total ))
        log "Swap: ${swap_used}MB used / ${swap_total}MB total (${swap_pct}%)"
        (( swap_pct > 20 )) && warn "Swap usage is ${swap_pct}% — system may be under memory pressure"
    else
        log "Swap: not configured"
    fi
}

# ============================================================
# CPU Load
# ============================================================
check_load() {
    log_section "System Load"
    local cpu_count load1 load5 load15
    cpu_count=$(nproc)
    read -r load1 load5 load15 _ < /proc/loadavg
    log "Load average: ${load1} ${load5} ${load15} (${cpu_count} CPUs)"

    local load_int
    load_int=$(echo "$load1" | cut -d. -f1)
    if (( load_int > cpu_count * 2 )); then
        warn "Load average is very high: ${load1} on ${cpu_count} CPUs"
    fi

    local uptime_str
    uptime_str=$(uptime -p)
    log "Uptime: $uptime_str"
}

# ============================================================
# ZFS Pool Status
# ============================================================
check_zfs() {
    log_section "ZFS Pools"
    if ! command -v zpool &>/dev/null; then
        log "ZFS not present — skipping"
        return
    fi

    local pool_count
    pool_count=$(zpool list -H 2>/dev/null | wc -l)

    if (( pool_count == 0 )); then
        log "No ZFS pools found"
        return
    fi

    while IFS=$'\t' read -r name size alloc free cap health; do
        log "Pool: ${name} | ${health} | ${alloc}/${size} used (${cap})"
        if [[ "$health" != "ONLINE" ]]; then
            warn "ZFS pool '${name}' is ${health}!"
        fi
    done < <(zpool list -H -o name,size,alloc,free,cap,health 2>/dev/null)

    # Check for recent errors
    local errors
    errors=$(zpool status 2>/dev/null | grep -c "errors:" | grep -v "No known data errors" || true)
    (( errors > 0 )) && warn "ZFS errors detected — run 'zpool status' for details"

    # Scrub status
    local last_scrub
    last_scrub=$(zpool status 2>/dev/null | awk '/scan:/{print $0}' | head -1)
    [[ -n "$last_scrub" ]] && log "Scrub: $last_scrub"
}

# ============================================================
# Disk Usage
# ============================================================
check_disk_usage() {
    log_section "Disk Usage"
    while read -r fs size used avail pct mp; do
        local pct_num="${pct//%/}"
        log "  ${mp}: ${used}/${size} (${pct})"
        if (( pct_num >= DISK_USAGE_WARN )); then
            warn "Disk usage on ${mp} is ${pct} — above ${DISK_USAGE_WARN}% threshold"
        fi
    done < <(df -h --output=source,size,used,avail,pcent,target \
        -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | tail -n +2)
}

# ============================================================
# Proxmox VM/CT Summary
# ============================================================
check_pve_vms() {
    log_section "VMs & Containers"
    if ! command -v qm &>/dev/null; then
        log "Not a Proxmox node — skipping VM check"
        return
    fi

    local running stopped
    running=$(qm list 2>/dev/null | grep -c " running" || echo 0)
    stopped=$(qm list 2>/dev/null | grep -c " stopped" || echo 0)
    log "VMs — Running: ${running}, Stopped: ${stopped}"

    local ct_running ct_stopped
    ct_running=$(pct list 2>/dev/null | grep -c " running" || echo 0)
    ct_stopped=$(pct list 2>/dev/null | grep -c " stopped" || echo 0)
    log "Containers — Running: ${ct_running}, Stopped: ${ct_stopped}"
}

# ============================================================
# Main
# ============================================================
main() {
    check_cpu_temp
    check_memory
    check_load
    check_zfs
    check_disk_usage
    check_pve_vms
    log ""
    log "Health check complete."
}

main "$@"