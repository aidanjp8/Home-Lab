#!/usr/bin/env bash
# ============================================================
# container-update.sh — Pull and recreate updated Docker containers
# Works with standalone containers and Compose stacks
# Usage: ./container-update.sh [--dry-run] [--prune] [stack-name]
# Schedule: 0 3 * * 0 (3am Sunday)
# ============================================================
set -euo pipefail
source "$(dirname "$0")/../../shared/lib.sh"
init_script "container-update" "$@"

# --- Config ---
COMPOSE_DIR="${DOCKER_COMPOSE_DIR:-/mnt/user/appdata}"
PRUNE="${CONTAINER_UPDATE_PRUNE:-true}"
TARGET_STACK="${TARGET_STACK:-}"   # if set, only update this stack name

# Parse extra flags
for arg in "$@"; do
    case "$arg" in
        --prune) PRUNE=true ;;
        --no-prune) PRUNE=false ;;
        --stack=*) TARGET_STACK="${arg#--stack=}" ;;
    esac
done

require_cmds docker

# ============================================================
# Find all compose stacks
# ============================================================
find_stacks() {
    find "$COMPOSE_DIR" -maxdepth 2 \
        \( -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yml" \) \
        2>/dev/null | sort
}

# ============================================================
# Update a single compose stack
# ============================================================
update_compose_stack() {
    local compose_file="$1"
    local stack_dir
    stack_dir=$(dirname "$compose_file")
    local stack_name
    stack_name=$(basename "$stack_dir")

    if [[ -n "$TARGET_STACK" && "$stack_name" != "$TARGET_STACK" ]]; then
        return
    fi

    log_section "Stack: ${stack_name}"
    log "Compose file: $compose_file"

    # Pull new images
    log "Pulling images for ${stack_name}..."
    if $DRY_RUN; then
        log "[DRY RUN] Would run: docker compose -f ${compose_file} pull"
    else
        docker compose -f "$compose_file" pull 2>&1 | tee -a "$LOG_FILE"
    fi

    # Check if anything actually changed
    local changed=false
    if ! $DRY_RUN; then
        # Compare image digests before/after pull
        if docker compose -f "$compose_file" config --images 2>/dev/null | \
            xargs -I{} docker inspect --format='{{.Id}}' {} 2>/dev/null | \
            sort > /tmp/hl_pre_ids.txt 2>/dev/null; then
            changed=true  # simplified — assume changed if pull succeeded
        fi
    fi

    # Recreate containers
    log "Recreating containers for ${stack_name}..."
    if $DRY_RUN; then
        log "[DRY RUN] Would run: docker compose -f ${compose_file} up -d --remove-orphans"
    else
        docker compose -f "$compose_file" up -d --remove-orphans 2>&1 | tee -a "$LOG_FILE"
    fi

    # Brief health check — wait 10s and check container states
    if ! $DRY_RUN; then
        sleep 10
        local unhealthy
        unhealthy=$(docker compose -f "$compose_file" ps \
            --format '{{.Name}} {{.Status}}' 2>/dev/null \
            | grep -v "Up\|running" | grep -v "^$" || true)

        if [[ -n "$unhealthy" ]]; then
            warn "Possible unhealthy containers in ${stack_name}:"$'\n'"$unhealthy"
        else
            log "All containers in ${stack_name} appear healthy"
        fi
    fi
}

# ============================================================
# Update standalone (non-compose) containers
# ============================================================
update_standalone() {
    log_section "Standalone Containers"

    # Find containers not managed by compose
    local standalone
    standalone=$(docker ps --format '{{.Names}}' \
        --filter "label!=com.docker.compose.project" 2>/dev/null || true)

    if [[ -z "$standalone" ]]; then
        log "No standalone containers found"
        return
    fi

    for ct_name in $standalone; do
        local image
        image=$(docker inspect --format '{{.Config.Image}}' "$ct_name" 2>/dev/null || continue)
        log "Pulling image for standalone container: ${ct_name} (${image})"

        if $DRY_RUN; then
            log "[DRY RUN] Would pull and recreate: $ct_name"
            continue
        fi

        local old_id
        old_id=$(docker inspect --format '{{.Image}}' "$ct_name" 2>/dev/null)

        docker pull "$image" 2>&1 | tee -a "$LOG_FILE"

        local new_id
        new_id=$(docker inspect --format '{{.Id}}' "$image" 2>/dev/null)

        if [[ "$old_id" != "$new_id" ]]; then
            log "Image updated — recreating container: $ct_name"
            warn "Standalone container ${ct_name} updated but needs manual recreate (no compose file). Run: docker restart ${ct_name}"
        else
            log "No change: $ct_name is already on latest image"
        fi
    done
}

# ============================================================
# Prune old images
# ============================================================
prune_images() {
    if ! $PRUNE; then
        log "Skipping image prune (--no-prune)"
        return
    fi

    log_section "Pruning Dangling Images"
    local freed
    if $DRY_RUN; then
        freed=$(docker image prune -f --dry-run 2>/dev/null | tail -1 || echo "unknown")
        log "[DRY RUN] Would free: $freed"
    else
        freed=$(docker image prune -f 2>&1 | tail -1 | tee -a "$LOG_FILE")
        log "Pruned: $freed"
    fi
}

# ============================================================
# Summary
# ============================================================
print_summary() {
    log_section "Container Status Summary"
    if ! $DRY_RUN; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>/dev/null \
            | tee -a "$LOG_FILE"
    fi
}

# ============================================================
# Main
# ============================================================
main() {
    log "Docker: $(docker --version 2>/dev/null)"
    log "Compose dir: $COMPOSE_DIR"

    local stacks
    stacks=$(find_stacks)

    if [[ -z "$stacks" ]]; then
        log "No compose stacks found in $COMPOSE_DIR"
    else
        local count
        count=$(echo "$stacks" | wc -l)
        log "Found ${count} compose stack(s)"
        while IFS= read -r stack_file; do
            update_compose_stack "$stack_file"
        done <<< "$stacks"
    fi

    update_standalone
    prune_images
    print_summary
}

main