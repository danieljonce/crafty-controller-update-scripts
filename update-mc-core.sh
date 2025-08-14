#!/usr/bin/env bash
set -euo pipefail

# Update the server JAR to the latest build of the chosen track (Purpur or Paper)
# Supports:
#   --friendly-name "cloudevans"
#   --server-name   "<uuid>"
#   --server-dir    "/crafty/servers/<uuid>"
# Optional:
#   --flavor purpur|paper
#   TARGET_VERSION="1.21.8"

die(){ echo "ERROR: $*" >&2; exit 1; }
log(){ echo "$*" >&2; }

# ---------- Require curl ----------
command -v curl >/dev/null 2>&1 || die "curl is required but not installed"

# ---------- Auto-detect Crafty paths ----------
if   [ -d "/crafty/app/servers" ]; then SROOT="/crafty/app/servers"; CCFG="/crafty/app/config"
elif [ -d "/crafty/servers"     ]; then SROOT="/crafty/servers";      CCFG="/crafty/app/config"
else die "Could not find Crafty servers dir"; fi
[ -d "$CCFG" ] || CCFG="/crafty/config"

# ---------- Downloader ----------
DOWNLOAD(){
  local url="$1" out="$2"
  curl -fsSL "$url" -o "$out" || die "download failed: $url"
}

# ---------- Friendly-name → UUID ----------
lookup_uuid_via_api(){
  local name="$1"
  [ -n "${CRAFTY_API_URL:-}" ] && [ -n "${CRAFTY_API_TOKEN:-}" ] || return 1
  local json; json="$(curl -fsSL -H "Authorization: Bearer ${CRAFTY_API_TOKEN}" "${CRAFTY_API_URL}/servers" 2>/dev/null || true)" || return 1
  grep -Eo '"(server_uuid|uuid)"[[:space:]]*:[[:space:]]*"([0-9a-fA-F-]+)"' <<<"$json" | grep -F "$name" -B1 | grep -Eo '[0-9a-fA-F-]+' | head -n1
}
lookup_uuid_via_config(){
  local name="$1" hits uuid
  hits="$(grep -RIl -e "$name" "$CCFG" 2>/dev/null || true)" || return 1
  uuid="$(grep -RhoE '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' $hits 2>/dev/null | head -n1 || true)"
  [ -n "$uuid" ] || return 1; echo "$uuid"
}
lookup_uuid_via_dirs(){
  local name="$1" d
  for d in "$SROOT"/*; do [ -d "$d" ] || continue
    grep -RIl -m1 -e "$name" "$d" >/dev/null 2>&1 && basename "$d" && return 0
  done
  return 1
}

# ---------- Args ----------
SERVER_DIR=""; FLAVOR=""; FRIENDLY=""; UUID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --server-dir)    SERVER_DIR="${2:-}"; shift 2 ;;
    --server-name)   UUID="${2:-}";       shift 2 ;;
    --friendly-name) FRIENDLY="${2:-}";   shift 2 ;;
    --flavor)        FLAVOR="${2:-}";     shift 2 ;;
    *) die "Unknown arg: $1" ;;
  esac
done

if [ -n "$FRIENDLY" ]; then
  UUID="$(lookup_uuid_via_api "$FRIENDLY" || true)"
  [ -z "$UUID" ] && UUID="$(lookup_uuid_via_config "$FRIENDLY" || true)"
  [ -z "$UUID" ] && UUID="$(lookup_uuid_via_dirs   "$FRIENDLY" || true)"
  [ -n "$UUID" ] || die "Could not resolve UUID for friendly name '$FRIENDLY'."
fi

if [ -z "$SERVER_DIR" ]; then
  if [ -n "$UUID" ]; then SERVER_DIR="$SROOT/$UUID"; else die "Provide --friendly-name, --server-name, or --server-dir"; fi
fi
[ -d "$SERVER_DIR" ] || die "No such dir: $SERVER_DIR"
cd "$SERVER_DIR"

# ---------- Infer flavor & TARGET_VERSION ----------
EXISTING_JAR="$(ls -1 *.jar 2>/dev/null | grep -Ei '^(purpur|paper).*\.jar$' | head -n1 || true)"
if [ -z "$FLAVOR" ]; then
  if   echo "$EXISTING_JAR" | grep -qi '^purpur'; then FLAVOR="purpur"
  elif echo "$EXISTING_JAR" | grep -qi '^paper';  then FLAVOR="paper"
  else FLAVOR="purpur"; fi
fi
if [ -z "${TARGET_VERSION:-}" ]; then
  if [ -n "$EXISTING_JAR" ]; then
    TARGET_VERSION="$(echo "$EXISTING_JAR" | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)"
  fi
fi
[ -n "${TARGET_VERSION:-}" ] || die "Could not infer TARGET_VERSION. Set TARGET_VERSION env var."

# ---------- Current build ----------
current_build="unknown"
if [ -f "logs/latest.log" ]; then
  if [ "$FLAVOR" = "purpur" ]; then
    current_build="$(grep -Eo 'git-Purpur-[0-9]+' logs/latest.log | tail -n1 | grep -Eo '[0-9]+' || true)"
  else
    current_build="$(grep -Eo 'git-Paper-[0-9]+' logs/latest.log | tail -n1 | grep -Eo '[0-9]+' || true)"
  fi
fi

# ---------- Latest build ----------
get_latest_build_num(){
  local flavor="$1" ver="$2" json=""
  if [ "$flavor" = "purpur" ]; then
    json="$(curl -fsSL "https://api.purpurmc.org/v2/purpur/${ver}/latest" || true)"
  else
    json="$(curl -fsSL "https://api.papermc.io/v2/projects/paper/versions/${ver}/builds/latest" || true)"
  fi
  echo "$json" | grep -Eo '"build"[[:space:]]*:[[:space:]]*[0-9]+' | tail -n1 | grep -Eo '[0-9]+' || true
}
latest_build="$(get_latest_build_num "$FLAVOR" "$TARGET_VERSION")"
[ -n "$latest_build" ] || latest_build="unknown"

log "Flavor: $FLAVOR | MC: $TARGET_VERSION | Current build: ${current_build} | Latest build: ${latest_build}"

# ---------- Download jar ----------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
OUT_JAR="${TMP}/server-latest.jar"
if [ "$FLAVOR" = "purpur" ]; then
  URL="https://api.purpurmc.org/v2/purpur/${TARGET_VERSION}/latest/download"
else
  URL="https://api.papermc.io/v2/projects/paper/versions/${TARGET_VERSION}/builds/latest/downloads/paper-${TARGET_VERSION}.jar"
fi
DOWNLOAD "$URL" "$OUT_JAR"
[ -s "$OUT_JAR" ] || die "Downloaded jar is empty"

# ---------- Backup & install ----------
if [ -f "server.jar" ]; then
  TS="$(date +%Y%m%d-%H%M%S)"; mkdir -p _backups; cp -f server.jar "_backups/server.jar.$TS"
  log "Backed up server.jar -> _backups/server.jar.$TS"
fi
mv -f "$OUT_JAR" server.jar
chmod 644 server.jar

log "Updated ${FLAVOR} build ${current_build} -> ${latest_build} (MC: ${TARGET_VERSION})."
log "Done. Restart your server to apply the new core."
