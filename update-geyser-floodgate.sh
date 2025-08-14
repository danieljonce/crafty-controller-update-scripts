#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Update/Install Geyser + Floodgate for a Crafty/Paper server
# Supports:
#   --friendly-name "cloudevans"   # resolve to UUID automatically
#   --server-name "<uuid>"         # direct UUID
#   /absolute/path/to/plugins      # direct plugins dir
#
# Optional (for API lookup):
#   export CRAFTY_API_URL="http://localhost:8000/api/v3"
#   export CRAFTY_API_TOKEN="YOUR_TOKEN"
# ------------------------------------------------------------

GEYSER_URL="https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot"
FLOODGATE_URL="https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot"

# Auto-detect Crafty paths (supports /crafty/app/* and /crafty/* layouts)
CRAFTY_ROOT="/crafty"

if [ -d "/crafty/app/servers" ]; then
  CRAFTY_SERVERS_ROOT="/crafty/app/servers"
  CRAFTY_CONFIG_DIR="/crafty/app/config"
elif [ -d "/crafty/servers" ]; then
  CRAFTY_SERVERS_ROOT="/crafty/servers"
  # config may still be under /crafty/app/config or /crafty/config — pick what exists
  if   [ -d "/crafty/app/config" ]; then CRAFTY_CONFIG_DIR="/crafty/app/config"
  elif [ -d "/crafty/config" ];    then CRAFTY_CONFIG_DIR="/crafty/config"
  else CRAFTY_CONFIG_DIR="/crafty"; fi
else
  echo "ERROR: Could not find Crafty servers dir at /crafty/app/servers or /crafty/servers" >&2
  echo "Hint: run 'ls -al /crafty' inside the container to see your layout." >&2
  exit 1
fi

log() { printf '%s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

ensure_dir() {
  local d="$1"
  if [ ! -d "$d" ]; then
    die "Directory not found: $d"
  fi
}

backup_if_exists() {
  local file="$1"
  if [ -f "$file" ]; then
    local backup_dir
    backup_dir="${PLUGINS_DIR}/_backups/$(date +%Y-%m-%d_%H-%M-%S)"
    mkdir -p "$backup_dir"
    mv "$file" "$backup_dir/"
    log "Backed up $(basename "$file") -> $backup_dir/"
  fi
}

download_to() {
  local url="$1"
  local dest="$2"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log "[DRY RUN] Would download: $url -> $dest"
  else
    curl -fsSL "$url" -o "$dest"
  fi
}

is_uuid() {
  # loose check; Crafty uses standard UUIDs
  case "$1" in
    *[!0-9a-fA-F-]*|"") return 1 ;;
    *)                  return 0 ;;
  esac
}

resolve_plugins_dir_from_uuid() {
  local uuid="$1"
  local candidate="${CRAFTY_SERVERS_ROOT}/${uuid}/plugins"
  if [ ! -d "$candidate" ]; then
    die "Could not find plugins dir at ${candidate}"
  fi
  printf '%s\n' "$candidate"
}

lookup_uuid_via_api() {
  # uses CRAFTY_API_URL/CRAFTY_API_TOKEN if set
  local fname="$1"
  if [ -z "${CRAFTY_API_URL:-}" ] || [ -z "${CRAFTY_API_TOKEN:-}" ]; then
    return 1
  fi
  local json
  if ! json="$(curl -fsSL -H "Authorization: Bearer ${CRAFTY_API_TOKEN}" "${CRAFTY_API_URL}/servers" 2>/dev/null)"; then
    return 1
  fi

  # Prefer jq if available
  if command -v jq >/dev/null 2>&1; then
    local uuid
    uuid="$(printf '%s' "$json" \
      | jq -r --arg n "$fname" '.data[]? | select((.server_name // .name // "")==$n) | (.server_uuid // .uuid // empty)' \
      | head -n1)"
    if [ -n "$uuid" ]; then
      printf '%s\n' "$uuid"
      return 0
    fi
    return 1
  fi

  # Fallback: simple grep heuristic
  # Try to find a line containing the name; then scan entire payload for a UUID
  if printf '%s\n' "$json" | grep -qi "\"server_name\"[[:space:]]*:[[:space:]]*\"${fname}\""; then
    :
  elif printf '%s\n' "$json" | grep -qi "\"name\"[[:space:]]*:[[:space:]]*\"${fname}\""; then
    :
  else
    return 1
  fi

  # Extract the first UUID-looking token
  local uuid_guess
  uuid_guess="$(printf '%s\n' "$json" | grep -Eo '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | head -n1 || true)"
  if [ -n "$uuid_guess" ]; then
    printf '%s\n' "$uuid_guess"
    return 0
  fi
  return 1
}

lookup_uuid_via_config_scan() {
  local fname="$1"
  if [ ! -d "$CRAFTY_CONFIG_DIR" ]; then
    return 1
  fi
  # search for the friendly name in config files
  local hits
  hits="$(grep -RIl --exclude-dir=.cache -e "$fname" "$CRAFTY_CONFIG_DIR" 2>/dev/null || true)"
  if [ -z "$hits" ]; then
    return 1
  fi
  # then pull out a UUID from the same files
  local uuid
  uuid="$(grep -RhoE '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' $hits 2>/dev/null | head -n1 || true)"
  if [ -n "$uuid" ]; then
    printf '%s\n' "$uuid"
    return 0
  fi
  return 1
}

lookup_uuid_via_server_dirs() {
  local fname="$1"
  ensure_dir "$CRAFTY_SERVERS_ROOT"
  local d uuid
  for d in "$CRAFTY_SERVERS_ROOT"/*; do
    [ -d "$d" ] || continue
    uuid="$(basename "$d")"
    # look for the friendly name anywhere under this server dir (metadata/config)
    if grep -RIl -m1 -e "$fname" "$d" >/dev/null 2>&1; then
      printf '%s\n' "$uuid"
      return 0
    fi
  done
  return 1
}

# ---------- Parse args ----------
PLUGINS_DIR=""
FRIENDLY_NAME=""

if [ "${1:-}" = "--server-name" ]; then
  [ $# -ge 2 ] || die "Missing value for --server-name"
  SERVER_NAME="$2"
  shift 2
  if is_uuid "$SERVER_NAME"; then
    PLUGINS_DIR="$(resolve_plugins_dir_from_uuid "$SERVER_NAME")"
  else
    die "--server-name expects the internal UUID. Use --friendly-name \"cloudevans\" for UI name."
  fi
elif [ "${1:-}" = "--friendly-name" ]; then
  [ $# -ge 2 ] || die "Missing value for --friendly-name"
  FRIENDLY_NAME="$2"
  shift 2
  uuid="$(lookup_uuid_via_api "$FRIENDLY_NAME" || true)"
  if [ -z "${uuid:-}" ]; then
    uuid="$(lookup_uuid_via_config_scan "$FRIENDLY_NAME" || true)"
  fi
  if [ -z "${uuid:-}" ]; then
    uuid="$(lookup_uuid_via_server_dirs "$FRIENDLY_NAME" || true)"
  fi
  if [ -z "${uuid:-}" ]; then
    log "Could not resolve UUID for friendly name \"$FRIENDLY_NAME\"."
    log "Existing server UUIDs under ${CRAFTY_SERVERS_ROOT}:"
    ls -1 "$CRAFTY_SERVERS_ROOT" || true
    die "Re-run with: --server-name <uuid>  OR set CRAFTY_API_URL/CRAFTY_API_TOKEN for API lookup."
  fi
  PLUGINS_DIR="$(resolve_plugins_dir_from_uuid "$uuid")"
elif [ $# -eq 1 ]; then
  PLUGINS_DIR="$1"
else
  cat <<'USAGE'
Usage:
  update-geyser-floodgate.sh /absolute/path/to/plugins
  update-geyser-floodgate.sh --server-name "<crafty-uuid>"
  update-geyser-floodgate.sh --friendly-name "<crafty-ui-name>"

Examples:
  update-geyser-floodgate.sh /crafty/app/servers/00000000-0000-0000-0000-000000000000/plugins
  update-geyser-floodgate.sh --server-name "00000000-0000-0000-0000-000000000000"
  update-geyser-floodgate.sh --friendly-name "cloudevans"
USAGE
  exit 1
fi

ensure_dir "$PLUGINS_DIR"

GEYSER_JAR="${PLUGINS_DIR}/Geyser-Spigot.jar"
FLOODGATE_JAR="${PLUGINS_DIR}/floodgate-spigot.jar"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log "Plugins dir: $PLUGINS_DIR"
log "Fetching latest Geyser + Floodgate ..."

GEYSER_TMP="${TMP_DIR}/Geyser-Spigot-latest.jar"
FLOODGATE_TMP="${TMP_DIR}/floodgate-spigot-latest.jar"

download_to "$GEYSER_URL" "$GEYSER_TMP"
download_to "$FLOODGATE_URL" "$FLOODGATE_TMP"

if [ "${DRY_RUN:-0}" != "1" ]; then
  [ -s "$GEYSER_TMP" ] || die "Downloaded Geyser jar is empty"
  [ -s "$FLOODGATE_TMP" ] || die "Downloaded Floodgate jar is empty"
fi

backup_if_exists "$GEYSER_JAR"
backup_if_exists "$FLOODGATE_JAR"

if [ "${DRY_RUN:-0}" = "1" ]; then
  log "[DRY RUN] Would install:"
  log "  $GEYSER_TMP -> $GEYSER_JAR"
  log "  $FLOODGATE_TMP -> $FLOODGATE_JAR"
else
  mv "$GEYSER_TMP" "$GEYSER_JAR"
  mv "$FLOODGATE_TMP" "$FLOODGATE_JAR"
  chmod 644 "$GEYSER_JAR" "$FLOODGATE_JAR"
fi

log "Done. Restart your server from Crafty to apply updates."
