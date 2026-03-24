#!/usr/bin/env bash
# ============================================================
# ssl-expiry-check.sh — Check SSL cert expiry for all your services
# Supports: public HTTPS domains, local/self-signed via file path
# Usage: ./ssl-expiry-check.sh [--dry-run]
# Schedule: 0 9 * * 1 (9am every Monday)
# ============================================================
set -euo pipefail
source "$(dirname "$0")/../../shared/lib.sh"
init_script "ssl-expiry-check" "$@"

# --- Config ---
# Space-separated list of domains to check via HTTPS
SSL_DOMAINS="${SSL_DOMAINS:-}"
# Optionally check cert files directly (space-separated paths)
SSL_CERT_FILES="${SSL_CERT_FILES:-}"
# Days before expiry to warn
WARN_DAYS="${SSL_WARN_DAYS:-30}"
# Connection timeout in seconds
TIMEOUT=10
# Port to connect on (override per domain not supported here, use 443 globally)
PORT=443

require_cmds openssl

# ============================================================
# Check a domain via live TLS connection
# ============================================================
check_domain() {
    local domain="$1"
    local host="${domain%%:*}"   # strip custom port if given
    local port="${domain##*:}"
    [[ "$port" == "$domain" ]] && port=$PORT   # no port specified, use default

    log "  Checking: ${host}:${port}"

    # Fetch the certificate
    local cert_info
    if ! cert_info=$(echo "" \
        | timeout "$TIMEOUT" openssl s_client \
            -connect "${host}:${port}" \
            -servername "$host" \
            2>/dev/null \
        | openssl x509 -noout -dates -subject -issuer 2>/dev/null); then
        warn "  ${host}: Could not retrieve certificate (connection failed or no HTTPS)"
        return
    fi

    # Parse expiry date
    local not_after
    not_after=$(echo "$cert_info" | grep "notAfter" | cut -d= -f2)

    if [[ -z "$not_after" ]]; then
        warn "  ${host}: Could not parse certificate expiry date"
        return
    fi

    # Calculate days until expiry
    local expiry_epoch now_epoch days_left
    expiry_epoch=$(date -d "$not_after" +%s 2>/dev/null \
        || date -j -f "%b %d %T %Y %Z" "$not_after" +%s 2>/dev/null \
        || echo 0)
    now_epoch=$(date +%s)
    days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

    # Parse subject/issuer for context
    local cn issuer
    cn=$(echo "$cert_info" | grep "subject" | grep -oP 'CN\s*=\s*\K[^,/]+' || echo "$host")
    issuer=$(echo "$cert_info" | grep "issuer" | grep -oP 'O\s*=\s*\K[^,/]+' || echo "unknown")

    if (( days_left <= 0 )); then
        warn "  ❌ EXPIRED: ${host} — cert expired ${days_left#-} days ago! (CN: ${cn}, Issuer: ${issuer})"
    elif (( days_left <= WARN_DAYS )); then
        warn "  ⚠️  EXPIRING SOON: ${host} — ${days_left} days remaining (expires: ${not_after})"
    else
        log "  ✅ OK: ${host} — ${days_left} days remaining (expires: ${not_after}, Issuer: ${issuer})"
    fi
}

# ============================================================
# Check a cert file directly (self-signed, internal CA, etc.)
# ============================================================
check_cert_file() {
    local cert_path="$1"

    if [[ ! -f "$cert_path" ]]; then
        warn "Cert file not found: $cert_path"
        return
    fi

    log "  Checking file: $cert_path"

    local cert_info
    if ! cert_info=$(openssl x509 -in "$cert_path" -noout -dates -subject 2>/dev/null); then
        warn "  Could not parse cert file: $cert_path"
        return
    fi

    local not_after cn
    not_after=$(echo "$cert_info" | grep "notAfter" | cut -d= -f2)
    cn=$(echo "$cert_info" | grep "subject" | grep -oP 'CN\s*=\s*\K[^,/]+' || echo "$cert_path")

    local expiry_epoch now_epoch days_left
    expiry_epoch=$(date -d "$not_after" +%s 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

    if (( days_left <= 0 )); then
        warn "  ❌ EXPIRED: ${cn} (${cert_path}) expired ${days_left#-} days ago!"
    elif (( days_left <= WARN_DAYS )); then
        warn "  ⚠️  EXPIRING SOON: ${cn} — ${days_left} days remaining"
    else
        log "  ✅ OK: ${cn} — ${days_left} days remaining (expires: ${not_after})"
    fi
}

# ============================================================
# Summary table
# ============================================================
print_summary() {
    log_section "Check Complete"
    log "Warn threshold: ${WARN_DAYS} days"
    log "Checked domains: $(echo "$SSL_DOMAINS" | wc -w)"
    log "Checked cert files: $(echo "$SSL_CERT_FILES" | wc -w)"
}

# ============================================================
# Main
# ============================================================
main() {
    if [[ -z "$SSL_DOMAINS" && -z "$SSL_CERT_FILES" ]]; then
        die "No domains or cert files configured. Set SSL_DOMAINS or SSL_CERT_FILES in .env"
    fi

    if [[ -n "$SSL_DOMAINS" ]]; then
        log_section "Domain Certificate Checks"
        for domain in $SSL_DOMAINS; do
            check_domain "$domain"
        done
    fi

    if [[ -n "$SSL_CERT_FILES" ]]; then
        log_section "Certificate File Checks"
        for cert_file in $SSL_CERT_FILES; do
            check_cert_file "$cert_file"
        done
    fi

    print_summary
}

main "$@"