# lib.sh — shared helpers. Sourced by the fetch scripts; not run directly.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$HERE/kit.conf" ]; then
  printf 'error: missing scripts/kit.conf. Copy scripts/kit.conf.example to scripts/kit.conf, then edit it for this drive.\n' >&2
  exit 1
fi
# shellcheck source=kit.conf
. "$HERE/kit.conf"

ZIM_DIR="$KIT_ROOT/zim"
MODEL_DIR="$KIT_ROOT/models"
APP_DIR="$KIT_ROOT/apps"
APP_MACOS_DIR="$APP_DIR/macos"
APP_WINDOWS_DIR="$APP_DIR/windows"
APP_ANDROID_DIR="$APP_DIR/android"
APP_IOS_DIR="$APP_DIR/ios"
APP_PYTHON_DIR="$APP_DIR/python"
KOLIBRI_DIR="$KIT_ROOT/kolibri"
TRANSLATE_DIR="$KIT_ROOT/translate"
MAPS_DIR="$KIT_ROOT/maps"
DOCS_DIR="$KIT_ROOT/docs"
MANIFEST="$KIT_ROOT/manifest.tsv"
LOG="$KIT_ROOT/kit-log.txt"

DRY_RUN=0
PRUNE=0
for _a in "${@:-}"; do
  case "$_a" in
    --dry-run) DRY_RUN=1 ;;
    --prune)   PRUNE=1 ;;
  esac
done

log()  { printf '%s  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG"; }
warn() { log "WARN  $*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

human() { awk -v b="${1:-0}" 'BEGIN{ if (b<1073741824) printf "%.0f MB", b/1048576; else printf "%.1f GB", b/1073741824 }'; }

preflight() {
  [ -d "$KIT_ROOT" ] || die "$KIT_ROOT not mounted. Plug in the drive, or edit KIT_ROOT in scripts/kit.conf."
  command -v curl >/dev/null || die "curl not found"
  mkdir -p "$ZIM_DIR" "$MODEL_DIR" "$APP_DIR" "$KOLIBRI_DIR" \
           "$APP_MACOS_DIR" "$APP_WINDOWS_DIR" "$APP_ANDROID_DIR" "$APP_IOS_DIR" \
           "$APP_PYTHON_DIR" \
           "$TRANSLATE_DIR" "$MAPS_DIR" "$DOCS_DIR" || die "cannot write to $KIT_ROOT"
  touch "$LOG"
  local free
  free=$(df -k "$KIT_ROOT" | awk 'NR==2 {print int($4/1048576)}')
  log "kit root $KIT_ROOT — ${free} GB free"
  [ "$free" -ge "$MIN_FREE_GB" ] || die "only ${free} GB free, need at least ${MIN_FREE_GB}"
}

# probe <url> -> prints "STATUS<TAB>BYTES"
#
# Tries HEAD first. Some hosts (HuggingFace CDN, a few mirrors) either reject
# HEAD or return no content-length on it, so fall back to a one-byte ranged GET
# and read the total out of Content-Range. That transfers 1 byte, not the file.
probe() {
  local url="$1" status bytes hdr

  hdr=$(curl -sSLI --max-time 60 -w '\nHTTPSTATUS:%{http_code}\n' "$url" 2>/dev/null)
  status=$(printf '%s' "$hdr" | awk -F: '/^HTTPSTATUS:/ {print $2}' | tail -n1)
  bytes=$(printf '%s' "$hdr" | awk 'BEGIN{IGNORECASE=1} /^content-length:/ {gsub(/\r/,""); print $2}' | tail -n1)

  if [ "${status:-000}" != "200" ] || [ -z "$bytes" ]; then
    hdr=$(curl -sSL --max-time 60 -r 0-0 -o /dev/null -D - -w '\nHTTPSTATUS:%{http_code}\n' "$url" 2>/dev/null)
    local s2 range
    s2=$(printf '%s' "$hdr" | awk -F: '/^HTTPSTATUS:/ {print $2}' | tail -n1)
    # "Content-Range: bytes 0-0/1234" — the total is the last field, after the /
    range=$(printf '%s' "$hdr" | awk 'BEGIN{IGNORECASE=1} /^content-range:/ {gsub(/\r/,""); print $NF}' | tail -n1)
    if [ "$s2" = "206" ] || [ "$s2" = "200" ]; then
      status="200"
      [ -n "$range" ] && bytes="${range##*/}"
    else
      status="${s2:-$status}"
    fi
  fi

  printf '%s\t%s\n' "${status:-000}" "${bytes:-0}"
}

remote_size() { probe "$1" | cut -f2; }

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    die "sha256sum or shasum is required to verify checksums"
  fi
}

# fetch <url> <dest> <label>  — resumable, size-verified
fetch() {
  local url="$1" dest="$2" label="$3" expected have final status p
  p=$(probe "$url"); status="${p%%$'\t'*}"; expected="${p##*$'\t'}"

  if [ "$status" != "200" ]; then
    warn "$label — remote returned HTTP $status, skipping"
    warn "      $url"
    return 1
  fi

  if [ -f "$dest" ] && [ "$expected" -gt 0 ] 2>/dev/null; then
    have=$(wc -c < "$dest" | tr -d ' ')
    if [ "$have" = "$expected" ]; then
      log "SKIP  $label — already complete ($(human "$expected"))"
      record "$label" "$url" "$expected"
      return 0
    fi
    log "RESUME $label — $(human "$have") of $(human "$expected")"
  else
    log "GET   $label — $(human "$expected")"
  fi

  if [ "$DRY_RUN" = 1 ]; then
    log "  ok  reachable, HTTP $status, $(human "$expected")"
    DRY_TOTAL=$(( ${DRY_TOTAL:-0} + expected ))
    return 0
  fi

  if curl -fL --progress-bar -C - \
       --retry "$CURL_RETRIES" --retry-delay 5 --retry-all-errors \
       -o "$dest" "$url"; then
    final=$(wc -c < "$dest" | tr -d ' ')
    if [ "$expected" -gt 0 ] 2>/dev/null && [ "$final" != "$expected" ]; then
      warn "$label size mismatch — got $final, expected $expected. Re-run to resume."
      return 1
    fi
    log "OK    $label"
    record "$label" "$url" "$final"
  else
    warn "$label download failed. Re-run to resume from where it stopped."
    return 1
  fi
}

# fetch_verified <url> <dest> <label> <sha256>
fetch_verified() {
  local url="$1" dest="$2" label="$3" expected_hash="${4:-}" actual_hash tmp

  fetch "$url" "$dest" "$label" || return 1

  if [ "$DRY_RUN" = 1 ]; then
    return 0
  fi

  if [ -z "$expected_hash" ]; then
    warn "$label — no sha256 configured; size was verified but contents were not pinned"
    return 0
  fi

  actual_hash=$(sha256_file "$dest")
  if [ "$actual_hash" != "$expected_hash" ]; then
    warn "$label checksum mismatch — got $actual_hash, expected $expected_hash"
    if [ -f "$MANIFEST.tmp" ]; then
      tmp="$MANIFEST.tmp.$$"
      awk -F'\t' -v label="$label" '$1 != label' "$MANIFEST.tmp" > "$tmp"
      mv "$tmp" "$MANIFEST.tmp"
    fi
    return 1
  fi

  log "OK    $label sha256 verified"
}

prune_unlisted() {
  local root="$1" keep_file="$2" path

  [ "$PRUNE" = 1 ] || return 0
  [ "$DRY_RUN" = 1 ] && return 0
  [ -d "$root" ] || return 0

  while IFS= read -r path; do
    if ! grep -Fxq "$path" "$keep_file"; then
      log "PRUNE $path"
      rm -f "$path"
    fi
  done < <(find "$root" -type f)

  find "$root" -depth -type d -empty ! -path "$root" -delete
}

record() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$(date -u +%Y-%m-%d)" >> "$MANIFEST.tmp"
}

manifest_begin() { : > "$MANIFEST.tmp"; }
manifest_commit() {
  if [ "$DRY_RUN" = 1 ]; then rm -f "$MANIFEST.tmp"; return; fi
  # merge: keep entries from other scripts that didn't run this time
  if [ -f "$MANIFEST" ]; then
    awk -F'\t' 'NR==FNR {seen[$1]=1; next} !($1 in seen)' \
      "$MANIFEST.tmp" "$MANIFEST" >> "$MANIFEST.tmp"
  fi
  sort -u -o "$MANIFEST.tmp" "$MANIFEST.tmp"
  mv "$MANIFEST.tmp" "$MANIFEST"
  log "manifest updated — $MANIFEST"
}
