#!/usr/bin/env bash
# build-kiwix-library.sh - generate /zim/library.xml for kiwix-serve --library.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"

preflight
manifest_begin

rc=0
library="$ZIM_DIR/library.xml"
tmp_library="$library.tmp"

echo
log "Kiwix library"

host_kiwix_manage() {
  local os arch archive root bin

  if command -v kiwix-manage >/dev/null; then
    command -v kiwix-manage
    return 0
  fi

  os=$(uname -s)
  arch=$(uname -m)
  case "$os:$arch" in
    Darwin:arm64)
      root="$APP_MACOS_DIR/kiwix-tools-arm64"
      archive=$(find "$root" -maxdepth 1 -type f -name 'kiwix-tools_macos-arm64-*.tar.gz' 2>/dev/null | sort | tail -n1)
      ;;
    Darwin:x86_64)
      root="$APP_MACOS_DIR/kiwix-tools-x86_64"
      archive=$(find "$root" -maxdepth 1 -type f -name 'kiwix-tools_macos-x86_64-*.tar.gz' 2>/dev/null | sort | tail -n1)
      ;;
    Linux:x86_64)
      root="$APP_LINUX_DIR/kiwix-tools"
      archive=$(find "$root" -maxdepth 1 -type f -name 'kiwix-tools_linux-x86_64-musl-*.tar.gz' 2>/dev/null | sort | tail -n1)
      ;;
    *)
      return 1
      ;;
  esac

  [ -n "${archive:-}" ] || return 1
  mkdir -p "$root/extracted"
  tar -xzf "$archive" -C "$root/extracted"
  bin=$(find "$root/extracted" -type f -name kiwix-manage | sort | tail -n1)
  [ -n "$bin" ] || return 1
  chmod +x "$bin" 2>/dev/null || true
  printf '%s\n' "$bin"
}

set +u
zim_files=( "$ZIM_DIR"/*.zim )
set -u

if [ "${#zim_files[@]}" -eq 0 ] || [ ! -f "${zim_files[0]}" ]; then
  log "SKIP  no completed ZIM files found"
  manifest_commit
  exit 0
fi

if [ "$DRY_RUN" = 1 ]; then
  log "DRY   would rebuild $library from ${#zim_files[@]} completed ZIM files"
  manifest_commit
  exit 0
fi

kiwix_manage=$(host_kiwix_manage) || {
  warn "kiwix-manage not available; run fetch-apps first or install Kiwix Tools"
  manifest_commit
  exit 1
}

rm -f "$tmp_library"
for zim in "${zim_files[@]}"; do
  [ -f "$zim" ] || continue
  log "ADD   $(basename "$zim")"
  "$kiwix_manage" "$tmp_library" add "$zim" || {
    warn "could not add $(basename "$zim") to Kiwix library"
    rc=1
  }
done

if [ "$rc" = 0 ] && [ -f "$tmp_library" ]; then
  mv "$tmp_library" "$library"
  size=$(wc -c < "$library" | tr -d ' ')
  record "kiwix-library" "zim-library:$library" "$size"
  log "OK    $library"
else
  rm -f "$tmp_library"
fi

manifest_commit
exit "$rc"
