#!/usr/bin/env bash
# fetch-zims.sh - resolve and download configured Kiwix ZIM libraries.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"

preflight
manifest_begin

rc=0
keep_file=$(mktemp)
job_dir=$(mktemp -d)
fragment_list="$job_dir/fragments.list"
: > "$fragment_list"
job_pids=()
job_count=0
pool_started=0

cleanup() {
  local pid
  for pid in "${job_pids[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
  if [ "$pool_started" = 1 ]; then
    exec 9>&- 9<&- || true
  fi
  rm -f "$keep_file"
  rm -rf "$job_dir"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

set +u
zim_entries=( "${ZIMS[@]}" )
set -u

keep() {
  printf '%s\n' "$1" >> "$keep_file"
}

parallel_limit() {
  local limit="${MAX_PARALLEL_DOWNLOADS:-3}"
  case "$limit" in
    ''|*[!0-9]*) limit=3 ;;
  esac
  [ "$limit" -ge 1 ] 2>/dev/null || limit=1
  printf '%s\n' "$limit"
}

run_zim_job() {
  local url="$1" dest="$2" label="$3" job_manifest="$4"
  MANIFEST_TMP="$job_manifest" fetch "$url" "$dest" "$label"
}

start_zim_job() {
  local url="$1" dest="$2" label="$3" job_manifest

  job_count=$((job_count + 1))
  job_manifest="$job_dir/manifest.$job_count"
  : > "$job_manifest"
  printf '%s\n' "$job_manifest" >> "$fragment_list"

  read -r _ <&9
  {
    if ! run_zim_job "$url" "$dest" "$label" "$job_manifest"; then
      warn "$label failed"
      : > "$job_dir/failed.$job_count"
    fi
    printf '%s\n' token >&9
  } &
  job_pids+=( "$!" )
}

start_zim_pool() {
  local limit="$1" i fifo

  fifo="$job_dir/pool.fifo"
  mkfifo "$fifo"
  exec 9<>"$fifo"
  rm -f "$fifo"
  pool_started=1

  i=0
  while [ "$i" -lt "$limit" ]; do
    printf '%s\n' token >&9
    i=$((i + 1))
  done
}

wait_for_zim_jobs() {
  local pid wait_rc=0

  for pid in "${job_pids[@]:-}"; do
    wait "$pid" || wait_rc=1
  done

  if find "$job_dir" -name 'failed.*' -type f | grep -q .; then
    wait_rc=1
  fi

  return "$wait_rc"
}

merge_zim_fragments() {
  local fragment

  while IFS= read -r fragment; do
    [ -f "$fragment" ] || continue
    cat "$fragment" >> "$MANIFEST_TMP"
  done < "$fragment_list"
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
log "parallel downloads: $(parallel_limit)"

set +u
if [ "${#zim_entries[@]}" -eq 0 ]; then
  log "SKIP  no ZIMs configured"
fi

limit=$(parallel_limit)
start_zim_pool "$limit"
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
  start_zim_job "$MIRROR/$subdir/$file" "$dest" "zim:$file"
done
wait_for_zim_jobs || rc=1
set -u

merge_zim_fragments

if [ "$PRUNE" = 1 ]; then
  prune_unlisted "$ZIM_DIR" "$keep_file"
fi

manifest_commit
exit "$rc"
