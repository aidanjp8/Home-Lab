#!/usr/bin/env bash
# ============================================================
# appdata-backup.sh — Versioned backup of Unraid /appdata
# Creates dated tarballs with configurable retention
# Usage: ./appdata-backup.sh [--dry-run] [--compress]
# Schedule: 0 4 * * * (4am daily)
# ============================================================
set -euo pipefail
source "$(dirname "$0")/../../shared/lib.sh"
init_script "appdata-backup" "$@"

# --- Config ---
APPDATA_DIR="${UNRAID_APPDATA:-/mnt/user/appdata}"
BACKUP_DEST="${UNRAID_BACKUP_DEST:-/mnt/user/backups/appdata}"
KEEP_DAYS="${UNRAID_BACKUP_KEEP:-7}"
COMPRESS=false
EXCLUDE_PATTERNS=(
    "*/logs/*"
    "*/log/*"
    "*/.cache/*"
    "*/cache/*"
    "*/transcode/*"
    "*/temp/*"
    "*/tmp/*"
    "*/__pycache__/*"
)

for arg in "$@"; do
    [[ "$arg" == "--compress" ]] && COMPRESS=true
done

require_cmds rsync find du

# ============================================================
# Pre-flight checks
# ============================================================
preflight() {
    log_section "Pre-flight"

    [[ -d "$APPDATA_DIR" ]] || die "Appdata source not found: $APPDATA_DIR"

    if ! $DRY_RUN; then
        mkdir -p "$BACKUP_DEST"
    fi

    # Disk space check — warn if destination has less than 10GB free
    local avail_kb
    avail_kb=$(df -k "$BACKUP_DEST" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
    local avail_gb=$(( avail_kb / 1048576 ))
    log "Destination free space: ${avail_gb}GB"
    (( avail_gb < 10 )) && warn "Low disk space on backup destination: ${avail_gb}GB free"

    # Size of appdata
    local appdata_size
    appdata_size=$(du -sh "$APPDATA_DIR" 2>/dev/null | cut -f1)
    log "Appdata source size: ${appdata_size}"
}

# ============================================================
# Stop containers that need quiescing (optional list)
# ============================================================
stop_containers() {
    log_section "Container Pause (optional)"
    # Add container names here if they need to be stopped during backup
    # e.g. databases that don't handle hot-copy well
    local PAUSE_CONTAINERS="${PAUSE_CONTAINERS:-}"

    if [[ -z "$PAUSE_CONTAINERS" ]]; then
        log "PAUSE_CONTAINERS not set — backing up live (hot copy)"
        log "Tip: set PAUSE_CONTAINERS='mariadb postgres' in .env for clean DB backups"
        return
    fi

    for ct in $PAUSE_CONTAINERS; do
        log "Stopping container: $ct"
        run docker stop "$ct" || warn "Failed to stop $ct"
    done
}

resume_containers() {
    local PAUSE_CONTAINERS="${PAUSE_CONTAINERS:-}"
    [[ -z "$PAUSE_CONTAINERS" ]] && return

    log_section "Resuming Containers"
    for ct in $PAUSE_CONTAINERS; do
        log "Starting container: $ct"
        run docker start "$ct" || warn "Failed to restart $ct"
    done
}

# ============================================================
# Run the backup
# ============================================================
do_backup() {
    log_section "Running Backup"

    local date_stamp
    date_stamp=$(date '+%Y-%m-%d')
    local backup_dir="${BACKUP_DEST}/${date_stamp}"

    if $DRY_RUN; then
        log "[DRY RUN] Would backup ${APPDATA_DIR} → ${backup_dir}"
    else
        mkdir -p "$backup_dir"
    fi

    # Build exclude args
    local exclude_args=()
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_args+=(--exclude="$pattern")
    done

    if $COMPRESS; then
        # Tarball mode — single compressed archive
        local tarball="${backup_dir}/appdata-${date_stamp}.tar.gz"
        log "Creating compressed archive: $tarball"
        run tar czf "$tarball" \
            "${exclude_args[@]/--exclude=/--exclude=}" \
            -C "$(dirname "$APPDATA_DIR")" \
            "$(basename "$APPDATA_DIR")" \
            2>&1 | tee -a "$LOG_FILE" || warn "tar exited with errors"

        local size
        size=$(du -sh "$tarball" 2>/dev/null | cut -f1)
        log "Archive created: $tarball (${size})"
    else
        # Rsync mode — faster, incremental-friendly
        log "Rsyncing ${APPDATA_DIR}/ → ${backup_dir}/"
        run rsync -a --delete --stats \
            "${exclude_args[@]}" \
            "$APPDATA_DIR/" \
            "$backup_dir/" \
            2>&1 | tee -a "$LOG_FILE"

        local size
        size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1)
        log "Backup directory size: ${size}"
    fi

    log "Backup complete → ${backup_dir}"
}

# ============================================================
# Prune old backups
# ============================================================
prune_old_backups() {
    log_section "Pruning Old Backups (keeping ${KEEP_DAYS} days)"

    local pruned=0
    while IFS= read -r old_dir; do
        log "Removing old backup: $old_dir"
        run rm -rf "$old_dir"
        (( pruned++ ))
    done < <(find "$BACKUP_DEST" -maxdepth 1 -type d -name '????-??-??' \
        | sort | head -n "-${KEEP_DAYS}" 2>/dev/null || true)

    if (( pruned == 0 )); then
        log "No old backups to prune"
    else
        log "Pruned ${pruned} old backup(s)"
    fi
}

# ============================================================
# Summary
# ============================================================
print_summary() {
    log_section "Backup Summary"
    local backup_count
    backup_count=$(find "$BACKUP_DEST" -maxdepth 1 -type d -name '????-??-??' 2>/dev/null | wc -l)
    local total_size
    total_size=$(du -sh "$BACKUP_DEST" 2>/dev/null | cut -f1)
    log "Total backups retained: ${backup_count}"
    log "Total backup dir size: ${total_size}"
    log "Retention policy: ${KEEP_DAYS} days"
}

# ============================================================
# Main
# ============================================================
main() {
    preflight
    stop_containers
    do_backup
    resume_containers
    prune_old_backups
    print_summary
}

# Ensure containers are resumed even on failure
trap 'resume_containers' ERR

main "$@"