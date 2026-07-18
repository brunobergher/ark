#!/usr/bin/env bash
# fetch-kolibri.sh - import configured Kolibri channels into /kolibri/.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"

preflight
manifest_begin

rc=0

set +u
kolibri_entries=( "${KOLIBRI_CHANNELS[@]}" )
set -u

kolibri_bin=$(ensure_python_tool kolibri kolibri) || exit 1

kolibri_size() {
  du -sk "$KOLIBRI_DIR" 2>/dev/null | awk '{print $1 * 1024}'
}

echo
log "Kolibri channels"

set +u
if [ "${#kolibri_entries[@]}" -eq 0 ]; then
  log "SKIP  no Kolibri channels configured"
fi

for entry in "${kolibri_entries[@]}"; do
  label="${entry%%|*}"
  cid="${entry#*|}"

  if [ "$cid" = "CHANNEL_ID_HERE" ] || [ -z "$cid" ]; then
    warn "kolibri:$label has a placeholder or empty channel ID"
    rc=1
    continue
  fi

  log "kolibri:$label — channel $cid"
  if [ "$DRY_RUN" = 1 ]; then
    log "  ok  would import Kolibri channel metadata and content"
    continue
  fi

  if KOLIBRI_HOME="$KOLIBRI_DIR" "$kolibri_bin" manage importchannel network "$cid" \
     && KOLIBRI_HOME="$KOLIBRI_DIR" "$kolibri_bin" manage importcontent network "$cid"; then
    record "kolibri:$label" "kolibri-channel:$cid" "$(kolibri_size)"
    log "OK    kolibri:$label"
  else
    warn "kolibri:$label import failed"
    rc=1
  fi
done
set -u

if [ "$PRUNE" = 1 ]; then
  warn "Kolibri pruning is not automated. Remove old channels from Kolibri with kolibri manage deletecontent/deletechannel when needed."
fi

manifest_commit
exit "$rc"
