#!/usr/bin/env bash
# fetch-all.sh — internal stage runner. Use ../update from the drive root.
#
#   ../update --dry-run   resolve everything, show sizes, download nothing
#   ../update             download or resume
#   ../update --prune     also delete files no longer listed in scripts/kit.conf

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"

preflight

started=$(date -u +%s)
rc=0
stages=(fetch-zims fetch-models fetch-apps fetch-kolibri fetch-argos)

for stage in "${stages[@]}"; do
  [ -x "$HERE/$stage.sh" ] || die "missing scripts/$stage.sh. Add or restore this fetch stage before running ./update."
done

for stage in "${stages[@]}"; do
  echo
  log "──────── $stage ────────"
  "$HERE/$stage.sh" "$@" || rc=1
done

elapsed=$(( $(date -u +%s) - started ))
echo
log "all stages done in $(( elapsed / 60 )) min (exit $rc)"

if [ "$DRY_RUN" = 1 ]; then
  echo
  log "dry run — nothing was written to $KIT_ROOT"
  log "for a per-URL reachability table, run ./update --check"
  exit $rc
fi

echo
"$HERE/verify-kit.sh" --summary-only
