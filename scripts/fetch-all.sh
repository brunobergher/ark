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
parallel_stages=(fetch-zims fetch-models fetch-apps fetch-python-tools fetch-maps)
serial_stages=(build-kiwix-library build-web-maps fetch-kolibri fetch-argos)
all_stages=( "${parallel_stages[@]}" "${serial_stages[@]}" )
stage_tmp_dir=$(mktemp -d)
parallel_pids=()
parallel_names=()
stage_count=0
pool_started=0

cleanup() {
  terminate_trees "${parallel_pids[@]:-}"
  if [ "$pool_started" = 1 ]; then
    exec 8>&- 8<&- || true
  fi
  rm -rf "$stage_tmp_dir"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

for stage in "${all_stages[@]}"; do
  [ -x "$HERE/$stage.sh" ] || die "missing scripts/$stage.sh. Add or restore this fetch stage before running ./update."
done

stage_parallel_limit() {
  local limit="${MAX_PARALLEL_STAGES:-3}"
  case "$limit" in
    ''|*[!0-9]*) limit=3 ;;
  esac
  [ "$limit" -ge 1 ] 2>/dev/null || limit=1
  printf '%s\n' "$limit"
}

run_stage() {
  local stage="$1"
  shift

  echo
  log "──────── $stage ────────"
  MANIFEST_TMP="$stage_tmp_dir/$stage.manifest.tmp" "$HERE/$stage.sh" "$@"
}

start_parallel_stage() {
  local stage="$1"
  shift

  stage_count=$((stage_count + 1))
  read -r _ <&8
  {
    trap 'terminate_trees $(child_pids $$); exit 130' INT TERM
    if ! run_stage "$stage" "$@"; then
      warn "$stage failed"
      : > "$stage_tmp_dir/failed.$stage_count"
    fi
    printf '%s\n' token >&8
  } &
  parallel_pids+=( "$!" )
  parallel_names+=( "$stage" )
}

start_stage_pool() {
  local limit="$1" i fifo

  fifo="$stage_tmp_dir/pool.fifo"
  mkfifo "$fifo"
  exec 8<>"$fifo"
  rm -f "$fifo"
  pool_started=1

  i=0
  while [ "$i" -lt "$limit" ]; do
    printf '%s\n' token >&8
    i=$((i + 1))
  done
}

wait_parallel_stages() {
  local pid i wait_rc=0

  for i in "${!parallel_pids[@]}"; do
    pid="${parallel_pids[$i]}"
    wait "$pid" || wait_rc=1
  done

  if find "$stage_tmp_dir" -name 'failed.*' -type f | grep -q .; then
    wait_rc=1
  fi

  parallel_pids=()
  parallel_names=()
  return "$wait_rc"
}

if [ "$PRUNE" = 1 ]; then
  log "stage parallelism disabled for --prune"
  for stage in "${all_stages[@]}"; do
    run_stage "$stage" "$@" || rc=1
  done
else
  limit=$(stage_parallel_limit)
  log "parallel stages: $limit"
  start_stage_pool "$limit"

  for stage in "${parallel_stages[@]}"; do
    start_parallel_stage "$stage" "$@"
  done
  wait_parallel_stages || rc=1

  for stage in "${serial_stages[@]}"; do
    run_stage "$stage" "$@" || rc=1
  done
fi

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
