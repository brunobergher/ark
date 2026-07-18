#!/usr/bin/env bash
# fetch-argos.sh - download and install configured Argos Translate packages.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"

preflight
manifest_begin

rc=0

set +u
pair_entries=( "${ARGOS_PAIRS[@]}" )
set -u

argospm_bin=$(ensure_python_tool argostranslate argospm) || exit 1
argos_python="$(dirname "$argospm_bin")/python"
if [ ! -x "$argos_python" ]; then
  if [ "$DRY_RUN" = 1 ]; then
    argos_python="python3"
  elif python3 -c "import argostranslate.package" >/dev/null 2>&1; then
    argos_python="python3"
  else
    die "argostranslate is not importable. Run scripts/fetch-python-tools.sh first."
  fi
fi

argos_size() {
  du -sk "$TRANSLATE_DIR" 2>/dev/null | awk '{print $1 * 1024}'
}

echo
log "Argos Translate packages"

set +u
if [ "${#pair_entries[@]}" -eq 0 ]; then
  log "SKIP  no Argos language pairs configured"
fi

for entry in "${pair_entries[@]}"; do
  from_code="${entry%%:*}"
  to_code="${entry#*:}"
  label="argos:$from_code:$to_code"

  if [ -z "$from_code" ] || [ -z "$to_code" ] || [ "$from_code" = "$to_code" ]; then
    warn "$label has an invalid language pair"
    rc=1
    continue
  fi

  log "$label"
  if [ "$DRY_RUN" = 1 ]; then
    log "  ok  would download and install Argos package $from_code -> $to_code"
    continue
  fi

  mkdir -p "$TRANSLATE_DIR/packages" "$TRANSLATE_DIR/downloads" "$TRANSLATE_DIR/cache" "$TRANSLATE_DIR/config"
  if ARGOS_PACKAGES_DIR="$TRANSLATE_DIR/packages" \
     XDG_CACHE_HOME="$TRANSLATE_DIR/cache" \
     XDG_CONFIG_HOME="$TRANSLATE_DIR/config" \
     "$argos_python" - "$from_code" "$to_code" "$TRANSLATE_DIR/downloads" <<'PY'
import pathlib
import shutil
import sys

import argostranslate.package

from_code = sys.argv[1]
to_code = sys.argv[2]
downloads = pathlib.Path(sys.argv[3])
downloads.mkdir(parents=True, exist_ok=True)

argostranslate.package.update_package_index()
available = argostranslate.package.get_available_packages()
matches = [
    package
    for package in available
    if package.from_code == from_code and package.to_code == to_code
]

if not matches:
    raise SystemExit(f"no Argos package found for {from_code}:{to_code}")

package = matches[0]
downloaded = pathlib.Path(package.download())
target = downloads / downloaded.name
if downloaded.resolve() != target.resolve():
    shutil.copy2(downloaded, target)

argostranslate.package.install_from_path(target)
print(target)
PY
  then
    record "$label" "argos-pair:$from_code:$to_code" "$(argos_size)"
    log "OK    $label"
  else
    warn "$label download or install failed"
    rc=1
  fi
done
set -u

if [ "$PRUNE" = 1 ]; then
  warn "Argos pruning is not automated. Remove old packages from $TRANSLATE_DIR/packages when needed."
fi

manifest_commit
exit "$rc"
