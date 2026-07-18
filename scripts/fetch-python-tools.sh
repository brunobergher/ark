#!/usr/bin/env bash
# fetch-python-tools.sh - populate /apps/python/ with offline Python wheels.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"

preflight
manifest_begin

rc=0
keep_file=$(mktemp)
trap 'rm -f "$keep_file"' EXIT

set +u
python_tool_entries=( "${PYTHON_TOOL_PACKAGES[@]}" )
set -u

valid_component() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

keep() {
  printf '%s\n' "$1" >> "$keep_file"
}

write_python_docs() {
  local path

  [ "$DRY_RUN" = 0 ] || return 0

  mkdir -p "$APP_PYTHON_DIR/wheelhouse" "$APP_PYTHON_DIR/venvs"

  path="$APP_PYTHON_DIR/README.txt"
  cat > "$path" <<'EOF'
Ark Python tools

This directory is populated by ./update. It carries offline wheelhouses for
Python-based tools such as Kolibri and Argos Translate.

Create a drive-local virtualenv, then install from a wheelhouse without using
the internet:

  python3 -m venv /Volumes/ark/apps/python/venvs/kolibri
  /Volumes/ark/apps/python/venvs/kolibri/bin/python -m pip install --no-index --find-links /Volumes/ark/apps/python/wheelhouse/kolibri kolibri

Use the matching package name and wheelhouse directory for other tools.
EOF
  keep "$path"
}

download_tool() {
  local name="$1" spec="$2" notes="$3" dest label size

  if ! valid_component "$name" || [ -z "$spec" ]; then
    warn "python-tool:$name has an invalid name or package spec"
    return 1
  fi

  dest="$APP_PYTHON_DIR/wheelhouse/$name"
  label="python-tool:$name"
  log "$label — $notes"

  if [ "$DRY_RUN" = 1 ]; then
    log "  ok  would download wheels for $spec into $dest"
    return 0
  fi

  mkdir -p "$dest"
  if python3 -m pip download --dest "$dest" "$spec"; then
    while IFS= read -r file; do
      keep "$file"
    done < <(find "$dest" -type f)
    size=$(find "$dest" -type f -exec wc -c {} + | awk 'END {print $1 + 0}')
    record "$label" "pip:$spec" "$size"
    log "OK    $label — wheelhouse ready ($(human "$size"))"
  else
    warn "$label download failed. Re-run to resume."
    return 1
  fi
}

write_python_docs

echo
log "Python tool wheelhouses"

set +u
if [ "${#python_tool_entries[@]}" -eq 0 ]; then
  log "SKIP  no Python tool packages configured"
fi

for entry in "${python_tool_entries[@]}"; do
  IFS='|' read -r name spec notes <<< "$entry"
  download_tool "$name" "$spec" "${notes:-}" || rc=1
done
set -u

if [ "$PRUNE" = 1 ]; then
  prune_unlisted "$APP_PYTHON_DIR" "$keep_file"
fi

manifest_commit
exit "$rc"
