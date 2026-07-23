#!/usr/bin/env bash
# fetch-maps.sh - populate /maps/ with mobile and hosted offline map files.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"

preflight
manifest_begin

rc=0
keep_file=$(mktemp)
trap 'rm -f "$keep_file"' EXIT

set +u
map_entries=( "${MAPS[@]}" )
resolver_entries=( "${MAP_RESOLVERS[@]}" )
set -u

valid_component() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

keep() {
  printf '%s\n' "$1" >> "$keep_file"
}

fetch_map() {
  local platform="$1" provider="$2" region="$3" filename="$4" url="$5" sha256="$6" notes="$7"
  local dir dest label

  if ! valid_component "$platform" || ! valid_component "$provider" || ! valid_component "$region" || [ -z "$filename" ]; then
    warn "map:$platform:$provider:$region has an invalid platform, provider, region, or filename"
    return 1
  fi

  dir="$MAPS_DIR/$platform/$provider/$region"
  dest="$dir/$filename"
  label="map:$platform:$provider:$region"
  keep "$dest"

  log "$label — $notes"
  if [ "$DRY_RUN" = 0 ]; then
    mkdir -p "$dir"
  fi

  fetch_verified "$url" "$dest" "$label" "$sha256"
}

resolve_map() {
  local resolver="$1" pattern="$2" repo api tmp resolved url

  case "$resolver" in
    direct:*)
      url="${resolver#direct:}"
      [ -n "$pattern" ] || return 1
      printf 'direct\t%s\t%s\n' "$pattern" "$url"
      ;;
    github-release:*)
      repo="${resolver#github-release:}"
      api="https://api.github.com/repos/$repo/releases/latest"
      tmp=$(mktemp)
      if ! curl -fsSL --max-time 60 "$api" -o "$tmp"; then
        rm -f "$tmp"
        return 1
      fi
      resolved=$(python3 -c '
import json
import re
import sys

pattern = sys.argv[1]
path = sys.argv[2]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)
tag = data.get("tag_name", "latest")

for asset in data.get("assets", []):
    name = asset.get("name", "")
    url = asset.get("browser_download_url", "")
    if name and url and re.search(pattern, name):
        print(f"{tag}\t{name}\t{url}")
        raise SystemExit(0)

raise SystemExit(2)
' "$pattern" "$tmp")
      rm -f "$tmp"
      [ -n "$resolved" ] || return 1
      printf '%s\n' "$resolved"
      ;;
    *)
      return 1
      ;;
  esac
}

echo
log "Offline maps"

set +u
if [ "${#map_entries[@]}" -eq 0 ] && [ "${#resolver_entries[@]}" -eq 0 ]; then
  log "SKIP  no maps configured"
fi

for entry in "${map_entries[@]}"; do
  IFS='|' read -r platform provider region filename url sha256 notes <<< "$entry"
  fetch_map "$platform" "$provider" "$region" "$filename" "$url" "${sha256:-}" "${notes:-}" || rc=1
done

for entry in "${resolver_entries[@]}"; do
  IFS='|' read -r platform provider region resolver pattern sha256 notes <<< "$entry"
  log "map:$platform:$provider:$region resolving $resolver"
  resolved=$(resolve_map "$resolver" "$pattern") || {
    warn "map:$platform:$provider:$region could not resolve $resolver with pattern $pattern"
    rc=1
    continue
  }
  IFS=$'\t' read -r tag filename url <<< "$resolved"
  log "map:$platform:$provider:$region resolved $tag $filename"
  fetch_map "$platform" "$provider" "$region" "$filename" "$url" "${sha256:-}" "${notes:-latest release}" || rc=1
done
set -u

if [ "$PRUNE" = 1 ]; then
  prune_unlisted "$MAPS_DIR" "$keep_file"
fi

manifest_commit
exit "$rc"
