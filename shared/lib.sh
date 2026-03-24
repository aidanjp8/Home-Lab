#!/usr/bin/env bash
# ============================================================
# shared/lib.sh — Common helpers sourced by all homelab scripts
# Usage: source "$(dirname "$0")/../shared/lib.sh"
# ============================================================

# --- Load .env from repo root (two levels up from any script) ---
_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$_REPO_ROOT/.env" ]]; then
    # shellcheck disable=SC1091
    set -a; source "$_REPO_ROOT/.env"; set +a
fi

# --- Defaults (overridden by .env) ---
EMAIL_FROM="${EMAIL_FROM:-homelab@localhost}"
EMAIL_TO="${EMAIL_TO:-root}"
EMAIL_SUBJECT_PREFIX="${EMAIL_SUBJECT_PREFIX:-[Homelab]}"
LOG_DIR="${LOG_DIR:-/var/log/homelab}"

# --- Runtime vars set by init_script() ---
SCRIPT_NAME=""
LOG_FILE=""
DRY_RUN=false
_EMAIL_BODY=""
_EMAIL_SUBJECT=""
_HAS_ERRORS=false

# ============================================================
# init_script <name> [--dry-run]
#   Call at the top of every script. Sets up logging, name,
#   dry-run mode, and the EXIT trap for email summary.
# ============================================================
init_script() {
    SCRIPT_NAME="$1"
    shift
    for arg in "$@"; do
        [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
    done

    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/${SCRIPT_NAME}.log"

    # Rotate log if > 5MB
    if [[ -f "$LOG_FILE" ]] && (( $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) > 5242880 )); then
        mv "$LOG_FILE" "${LOG_FILE}.1"
    fi

    _EMAIL_SUBJECT="${EMAIL_SUBJECT_PREFIX} ${SCRIPT_NAME}"
    _EMAIL_BODY=""

    trap '_on_exit' EXIT

    log "========== ${SCRIPT_NAME} started =========="
    $DRY_RUN && log "⚠️  DRY-RUN mode — no changes will be made"
}

# ============================================================
# Logging
# ============================================================
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOG_FILE"
    _EMAIL_BODY+="${msg}"$'\n'
}

log_section() {
    log ""
    log "--- $* ---"
}

warn() {
    _HAS_ERRORS=true
    log "⚠️  WARNING: $*"
}

die() {
    _HAS_ERRORS=true
    log "❌ FATAL: $*"
    exit 1
}

# ============================================================
# Email
# ============================================================
send_email() {
    local subject="$1"
    local body="$2"
    if command -v mail &>/dev/null; then
        echo "$body" | mail -s "$subject" -r "$EMAIL_FROM" "$EMAIL_TO"
    elif command -v sendmail &>/dev/null; then
        {
            echo "From: $EMAIL_FROM"
            echo "To: $EMAIL_TO"
            echo "Subject: $subject"
            echo ""
            echo "$body"
        } | sendmail -t
    else
        log "⚠️  No mail binary found — install mailutils or msmtp"
    fi
}

# ============================================================
# EXIT trap — emails the full log on finish
# ============================================================
_on_exit() {
    local exit_code=$?
    local status_icon="✅"
    local status_label="SUCCESS"

    if [[ $exit_code -ne 0 ]] || $DRY_RUN && [[ $_HAS_ERRORS == true ]]; then
        status_icon="❌"
        status_label="FAILED (exit $exit_code)"
        _EMAIL_SUBJECT="${_EMAIL_SUBJECT} — ❌ FAILED"
    else
        _EMAIL_SUBJECT="${_EMAIL_SUBJECT} — ✅ OK"
    fi

    log ""
    log "========== ${SCRIPT_NAME} ${status_label} =========="

    send_email "$_EMAIL_SUBJECT" "$_EMAIL_BODY"
}

# ============================================================
# Utilities
# ============================================================

# Check required commands exist
require_cmds() {
    for cmd in "$@"; do
        command -v "$cmd" &>/dev/null || die "Required command not found: $cmd — install it first"
    done
}

# Run a command, or print it in dry-run mode
run() {
    if $DRY_RUN; then
        log "[DRY RUN] Would run: $*"
    else
        log "Running: $*"
        "$@" 2>&1 | tee -a "$LOG_FILE"
    fi
}

# Human-readable bytes
hr_bytes() {
    local bytes=$1
    if   (( bytes >= 1073741824 )); then echo "$(( bytes / 1073741824 ))GB"
    elif (( bytes >= 1048576 ));    then echo "$(( bytes / 1048576 ))MB"
    elif (( bytes >= 1024 ));       then echo "$(( bytes / 1024 ))KB"
    else echo "${bytes}B"
    fi
}