#!/usr/bin/env bash
# ============================================================
# pve-update.sh — Safe Proxmox host update
# Snapshots all running VMs, updates the host, optionally reboots
# Usage: ./pve-update.sh [--dry-run] [--no-snapshot] [--reboot]
# ============================================================
set -euo pipefail
source "$(dirname "$0")/../../shared/lib.sh"
init_script "pve-update" "$@"

# --- Config ---
PVE_SNAPSHOT_NAME="${PVE_SNAPSHOT_NAME:-pre-update}"
PVE_STORAGE="${PVE_STORAGE:-local-zfs}"
SNAPSHOT_VMS=true
AUTO_REBOOT=false
SNAP_KEEP="${SNAP_KEEP:-3}"           # keep last N pre-update snapshots per VM

# Parse extra flags
for arg in "$@"; do
    case "$arg" in
        --no-snapshot) SNAPSHOT_VMS=false ;;
        --reboot)      AUTO_REBOOT=true ;;
    esac
done

require_cmds apt-get pvesh

# ============================================================
# Snapshot all running VMs
# ============================================================
snapshot_vms() {
    log_section "Snapshotting Running VMs"

    if ! command -v qm &>/dev/null; then
        log "qm not found — skipping VM snapshots"
        return
    fi

    local snap_name="${PVE_SNAPSHOT_NAME}-$(date '+%Y%m%d')"
    local vm_ids
    vm_ids=$(qm list 2>/dev/null | awk '/running/{print $1}')

    if [[ -z "$vm_ids" ]]; then
        log "No running VMs found — nothing to snapshot"
        return
    fi

    for vmid in $vm_ids; do
        local vm_name
        vm_name=$(qm config "$vmid" 2>/dev/null | awk -F': ' '/^name:/{print $2}')
        log "Snapshotting VM ${vmid} (${vm_name}) → ${snap_name}"
        run qm snapshot "$vmid" "$snap_name" \
            --description "Auto pre-update $(date '+%Y-%m-%d')" \
            --vmstate 0

        # Prune old pre-update snapshots, keep last $SNAP_KEEP
        local old_snaps
        old_snaps=$(qm listsnapshot "$vmid" 2>/dev/null \
            | awk -v prefix="$PVE_SNAPSHOT_NAME" '$0 ~ prefix {print $2}' \
            | sort | head -n "-${SNAP_KEEP}" 2>/dev/null || true)

        for snap in $old_snaps; do
            log "Pruning old snapshot: VM ${vmid} → ${snap}"
            run qm delsnapshot "$vmid" "$snap"
        done
    done

    log "All VM snapshots complete"
}

# ============================================================
# Snapshot all running LXC containers
# ============================================================
snapshot_cts() {
    log_section "Snapshotting Running Containers"

    if ! command -v pct &>/dev/null; then
        log "pct not found — skipping LXC snapshots"
        return
    fi

    local snap_name="${PVE_SNAPSHOT_NAME}-$(date '+%Y%m%d')"
    local ct_ids
    ct_ids=$(pct list 2>/dev/null | awk '/running/{print $1}')

    if [[ -z "$ct_ids" ]]; then
        log "No running containers found"
        return
    fi

    for ctid in $ct_ids; do
        local ct_name
        ct_name=$(pct config "$ctid" 2>/dev/null | awk -F': ' '/^hostname:/{print $2}')
        log "Snapshotting CT ${ctid} (${ct_name}) → ${snap_name}"
        run pct snapshot "$ctid" "$snap_name" \
            --description "Auto pre-update $(date '+%Y-%m-%d')"

        # Prune old snapshots
        local old_snaps
        old_snaps=$(pct listsnapshot "$ctid" 2>/dev/null \
            | awk -v prefix="$PVE_SNAPSHOT_NAME" '$0 ~ prefix {print $2}' \
            | sort | head -n "-${SNAP_KEEP}" 2>/dev/null || true)

        for snap in $old_snaps; do
            log "Pruning old snapshot: CT ${ctid} → ${snap}"
            run pct delsnapshot "$ctid" "$snap"
        done
    done

    log "All container snapshots complete"
}

# ============================================================
# Update Proxmox host packages
# ============================================================
update_host() {
    log_section "Updating Host Packages"

    log "Running apt-get update..."
    run apt-get update -qq

    log "Checking for upgrades..."
    local upgradeable
    upgradeable=$(apt list --upgradable 2>/dev/null | grep -v "^Listing" | wc -l || echo 0)
    log "Packages to upgrade: ${upgradeable}"

    if (( upgradeable == 0 )); then
        log "System is already up to date"
        return
    fi

    log "Running apt-get dist-upgrade..."
    run apt-get dist-upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"

    log "Running apt-get autoremove..."
    run apt-get autoremove -y

    log "Host packages updated successfully"
}

# ============================================================
# Check if reboot is required
# ============================================================
check_reboot() {
    log_section "Reboot Check"
    if [[ -f /var/run/reboot-required ]]; then
        log "⚠️  Reboot is required"
        if $AUTO_REBOOT; then
            log "Auto-reboot is enabled — rebooting in 60 seconds"
            log "Run 'shutdown -c' within 60s to cancel"
            run shutdown -r +1 "Automated post-update reboot by pve-update.sh"
        else
            warn "Reboot required but --reboot not set. Please reboot manually."
        fi
    else
        log "No reboot required"
    fi
}

# ============================================================
# Main
# ============================================================
main() {
    log "Proxmox node: $(hostname)"
    log "PVE version: $(pveversion 2>/dev/null || echo 'unknown')"

    if $SNAPSHOT_VMS; then
        snapshot_vms
        snapshot_cts
    else
        log "Skipping snapshots (--no-snapshot passed)"
    fi

    update_host
    check_reboot

    log ""
    log "Update complete. Check email for full log."
}

main