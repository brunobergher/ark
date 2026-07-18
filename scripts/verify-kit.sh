#!/usr/bin/env bash
# verify-kit.sh - summarize the prepared Ark drive after an update.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"

summary_only=0
case "${1:-}" in
  --summary-only) summary_only=1 ;;
esac

dir_size() {
  local dir="$1"
  if [ -d "$dir" ]; then
    du -sk "$dir" 2>/dev/null | awk '{print $1 * 1024}'
  else
    printf '0\n'
  fi
}

dir_count() {
  local dir="$1" pattern="${2:-*}"
  if [ -d "$dir" ]; then
    find "$dir" -type f -name "$pattern" 2>/dev/null | wc -l | tr -d ' '
  else
    printf '0\n'
  fi
}

row() {
  printf '  %-18s %6s  %s\n' "$1" "$2" "$3"
}

echo
echo "ark — kit summary"
echo "══════════════════════════════════════════════════════════════════════════"
row "ZIM files" "$(dir_count "$ZIM_DIR" '*.zim')" "$(human "$(dir_size "$ZIM_DIR")")"
row "Models" "$(dir_count "$MODEL_DIR")" "$(human "$(dir_size "$MODEL_DIR")")"
row "Apps" "$(dir_count "$APP_DIR")" "$(human "$(dir_size "$APP_DIR")")"
row "Kolibri" "$(dir_count "$KOLIBRI_DIR")" "$(human "$(dir_size "$KOLIBRI_DIR")")"
row "Translate" "$(dir_count "$TRANSLATE_DIR")" "$(human "$(dir_size "$TRANSLATE_DIR")")"
row "Maps" "$(dir_count "$MAPS_DIR")" "$(human "$(dir_size "$MAPS_DIR")")"
row "Docs" "$(dir_count "$DOCS_DIR")" "$(human "$(dir_size "$DOCS_DIR")")"

if [ -f "$MANIFEST" ]; then
  echo
  echo "  manifest entries  $(wc -l < "$MANIFEST" | tr -d ' ')"
  echo "  manifest          $MANIFEST"
else
  echo
  warn "manifest missing — no completed fetch stage has committed yet"
fi

if [ "$summary_only" = 0 ]; then
  echo
  echo "Configured root: $KIT_ROOT"
fi

echo
