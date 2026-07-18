#!/usr/bin/env bash
# fetch-zims.sh - resolve and download configured Kiwix ZIM libraries.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"

preflight
manifest_begin

rc=0
keep_file=$(mktemp)
trap 'rm -f "$keep_file"' EXIT

set +u
zim_entries=( "${ZIMS[@]}" )
set -u

keep() {
  printf '%s\n' "$1" >> "$keep_file"
}

resolve_zim() {
  local subdir="$1" prefix="$2" index file

  index=$(curl -fsSL --max-time 60 "$MIRROR/$subdir/" 2>/dev/null) || return 1
  file=$(printf '%s' "$index" \
    | grep -o "href=\"${prefix}_[0-9]\{4\}-[0-9]\{2\}\.zim\"" \
    | sed 's/href="//; s/"$//' | sort -V | tail -n1)

  [ -n "$file" ] || return 1
  printf '%s\n' "$file"
}

echo
log "Kiwix ZIMs"

set +u
if [ "${#zim_entries[@]}" -eq 0 ]; then
  log "SKIP  no ZIMs configured"
fi

for entry in "${zim_entries[@]}"; do
  subdir="${entry%%:*}"
  prefix="${entry#*:}"
  file=$(resolve_zim "$subdir" "$prefix") || {
    warn "zim:$prefix could not resolve latest build in $MIRROR/$subdir/"
    rc=1
    continue
  }

  dest="$ZIM_DIR/$file"
  keep "$dest"
  fetch "$MIRROR/$subdir/$file" "$dest" "zim:$file" || rc=1
done
set -u

if [ "$PRUNE" = 1 ]; then
  prune_unlisted "$ZIM_DIR" "$keep_file"
fi

manifest_commit
exit "$rc"
