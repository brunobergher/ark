#!/usr/bin/env bash
# fetch-models.sh - download configured local model files and llamafile runtime.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"

preflight
manifest_begin

rc=0
keep_file=$(mktemp)
trap 'rm -f "$keep_file"' EXIT

set +u
model_entries=( "${MODELS[@]}" )
set -u

keep() {
  printf '%s\n' "$1" >> "$keep_file"
}

expand_model_names() {
  local name="$1" n i part

  printf '%s\n' "$name"
  if [[ "$name" =~ -0*1-of-0*([0-9]+)\.gguf$ ]]; then
    n="${BASH_REMATCH[1]}"
    for i in $(seq 2 "$n"); do
      part=$(printf '%05d-of-%05d' "$i" "$n")
      printf '%s\n' "$name" | sed -E "s/[0-9]{5}-of-[0-9]{5}/$part/"
    done
  fi
}

expand_model_urls() {
  local url="$1" name="$2" n i part

  printf '%s\n' "$url"
  if [[ "$name" =~ -0*1-of-0*([0-9]+)\.gguf$ ]]; then
    n="${BASH_REMATCH[1]}"
    for i in $(seq 2 "$n"); do
      part=$(printf '%05d-of-%05d' "$i" "$n")
      printf '%s\n' "$url" | sed -E "s/[0-9]{5}-of-[0-9]{5}/$part/"
    done
  fi
}

echo
log "Models"

set +u
if [ "${#model_entries[@]}" -eq 0 ]; then
  log "SKIP  no models configured"
fi

for entry in "${model_entries[@]}"; do
  name="${entry%%|*}"
  url="${entry#*|}"
  names=()
  urls=()
  while IFS= read -r item; do
    names+=( "$item" )
  done < <(expand_model_names "$name")
  while IFS= read -r item; do
    urls+=( "$item" )
  done < <(expand_model_urls "$url" "$name")

  for i in "${!urls[@]}"; do
    dest="$MODEL_DIR/${names[$i]}"
    keep "$dest"
    fetch "${urls[$i]}" "$dest" "model:${names[$i]}" || rc=1
  done
done

if [ -n "${LLAMAFILE_RELEASE:-}" ]; then
  filename="$(basename "$LLAMAFILE_RELEASE")"
  dest="$APP_DIR/llamafile/$filename"
  keep "$dest"
  if [ "$DRY_RUN" = 0 ]; then
    mkdir -p "$APP_DIR/llamafile"
  fi
  fetch "$LLAMAFILE_RELEASE" "$dest" "app:llamafile:$filename" || rc=1
  if [ "$DRY_RUN" = 0 ] && [ -f "$dest" ]; then
    chmod +x "$dest" 2>/dev/null || warn "$dest downloaded, but chmod +x failed"
  fi
fi
set -u

if [ "$PRUNE" = 1 ]; then
  prune_unlisted "$MODEL_DIR" "$keep_file"
  prune_unlisted "$APP_DIR/llamafile" "$keep_file"
fi

manifest_commit
exit "$rc"
