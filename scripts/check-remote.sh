#!/usr/bin/env bash
# check-remote.sh — prove every URL in scripts/kit.conf resolves before a
# multi-hundred-gigabyte download. Transfers nothing but headers.
#
#   ./update --check
#
# For each ZIM it resolves the newest build from the mirror index, then probes
# it. For each model it probes the URL directly (including every shard of a
# split GGUF). Prints a total and compares it against free space on the drive.

. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

[ -d "$KIT_ROOT" ] || die "$KIT_ROOT not mounted"
command -v curl >/dev/null || die "curl not found"

green() { printf '\033[32m%s\033[0m' "$1"; }
red()   { printf '\033[31m%s\033[0m' "$1"; }
yellow(){ printf '\033[33m%s\033[0m' "$1"; }

total=0
bad=0
row() { printf '  %-8s %-52s %s\n' "$1" "$2" "$3"; }

set +u
zim_entries=( "${ZIMS[@]}" )
model_entries=( "${MODELS[@]}" )
kolibri_entries=( "${KOLIBRI_CHANNELS[@]}" )

echo
echo "ark — remote preflight  $(date -u +%Y-%m-%dT%H:%MZ)"
echo "══════════════════════════════════════════════════════════════════════════"

# ── ZIMs ─────────────────────────────────────────────────────────────────────
echo
echo "Kiwix ZIMs"
for entry in "${zim_entries[@]}"; do
  subdir="${entry%%:*}"; prefix="${entry#*:}"

  index=$(curl -fsSL --max-time 60 "$MIRROR/$subdir/" 2>/dev/null)
  if [ -z "$index" ]; then
    row "$(red FAIL)" "$prefix" "mirror dir $subdir/ unreachable"
    bad=$((bad+1)); continue
  fi

  file=$(printf '%s' "$index" \
    | grep -o "href=\"${prefix}_[0-9]\{4\}-[0-9]\{2\}\.zim\"" \
    | sed 's/href="//; s/"$//' | sort -V | tail -n1)

  if [ -z "$file" ]; then
    row "$(red FAIL)" "$prefix" "no build matches this prefix"
    bad=$((bad+1)); continue
  fi

  p=$(probe "$MIRROR/$subdir/$file"); st="${p%%$'\t'*}"; sz="${p##*$'\t'}"
  if [ "$st" = "200" ] && [ "$sz" -gt 0 ] 2>/dev/null; then
    row "$(green OK)" "$file" "$(human "$sz")"
    total=$(( total + sz ))
  else
    row "$(red FAIL)" "$file" "HTTP $st"
    bad=$((bad+1))
  fi
done

# ── models ───────────────────────────────────────────────────────────────────
echo
echo "Models"
if [ "${#model_entries[@]}" -eq 0 ]; then
  row "$(yellow SKIP)" "(none configured)" ""
else
  for entry in "${model_entries[@]}"; do
    name="${entry%%|*}"; url="${entry#*|}"
    urls=("$url"); names=("$name")

    # expand sharded GGUF: -00001-of-0000N
    if [[ "$name" =~ -0*1-of-0*([0-9]+)\.gguf$ ]]; then
      n="${BASH_REMATCH[1]}"
      for i in $(seq 2 "$n"); do
        part=$(printf '%05d-of-%05d' "$i" "$n")
        names+=("$(echo "$name" | sed -E "s/[0-9]{5}-of-[0-9]{5}/$part/")")
        urls+=("$(echo "$url"   | sed -E "s/[0-9]{5}-of-[0-9]{5}/$part/")")
      done
    fi

    for i in "${!urls[@]}"; do
      p=$(probe "${urls[$i]}"); st="${p%%$'\t'*}"; sz="${p##*$'\t'}"
      if [ "$st" = "200" ] && [ "$sz" -gt 0 ] 2>/dev/null; then
        row "$(green OK)" "${names[$i]}" "$(human "$sz")"
        total=$(( total + sz ))
      else
        row "$(red FAIL)" "${names[$i]}" "HTTP $st"
        bad=$((bad+1))
      fi
    done
  done
fi

if [ -n "$LLAMAFILE_RELEASE" ]; then
  p=$(probe "$LLAMAFILE_RELEASE"); st="${p%%$'\t'*}"; sz="${p##*$'\t'}"
  if [ "$st" = "200" ]; then
    row "$(green OK)" "$(basename "$LLAMAFILE_RELEASE")" "$(human "$sz")"
    total=$(( total + sz ))
  else
    row "$(red FAIL)" "$(basename "$LLAMAFILE_RELEASE")" "HTTP $st"; bad=$((bad+1))
  fi
fi

# ── things that aren't plain URLs ────────────────────────────────────────────
echo
echo "Tool-driven content (size not knowable in advance)"
if command -v kolibri >/dev/null; then
  row "$(green OK)" "kolibri CLI" "installed"
else
  row "$(yellow WARN)" "kolibri CLI" "missing — pipx install kolibri"
fi
for entry in "${kolibri_entries[@]}"; do
  label="${entry%%|*}"; cid="${entry#*|}"
  if [ "$cid" = "CHANNEL_ID_HERE" ]; then
    row "$(red FAIL)" "$label" "placeholder channel ID — set it in scripts/kit.conf"
    bad=$((bad+1))
  else
    row "$(green OK)" "$label" "$cid"
  fi
done
set -u

if python3 -c "import argostranslate.package" 2>/dev/null; then
  row "$(green OK)" "argostranslate" "installed"
else
  row "$(yellow WARN)" "argostranslate" "missing — pipx install argostranslate"
fi

# ── verdict ──────────────────────────────────────────────────────────────────
free_gb=$(df -k "$KIT_ROOT" | awk 'NR==2 {print int($4/1048576)}')
need_gb=$(awk -v b="$total" 'BEGIN{printf "%.0f", b/1073741824}')

echo
echo "══════════════════════════════════════════════════════════════════════════"
echo "  direct downloads   $(human "$total")"
echo "  free on $KIT_ROOT  ${free_gb} GB"
echo
if [ "$need_gb" -gt "$free_gb" ]; then
  echo "  $(red "NOT ENOUGH SPACE") — need ${need_gb} GB, have ${free_gb} GB"
  bad=$((bad+1))
else
  echo "  space is fine — ${need_gb} GB of ${free_gb} GB"
fi
echo
echo "  Kolibri is not counted above. Full Khan Academy English is roughly"
echo "  200 GB on its own, so budget for that separately."
echo

if [ "$bad" -eq 0 ]; then
  set +u
  missing_stages=()
  for stage in fetch-zims fetch-models fetch-kolibri fetch-argos; do
    [ -x "$HERE/$stage.sh" ] || missing_stages+=( "scripts/$stage.sh" )
  done

  if [ "${#missing_stages[@]}" -eq 0 ]; then
    echo "  $(green "All checks passed.") Run ./update when ready."
  else
    echo "  $(green "All remote checks passed.") Add missing fetch stages before ./update:"
    printf '    %s\n' "${missing_stages[@]}"
  fi
  set -u
else
  echo "  $(red "$bad problem(s).") Fix scripts/kit.conf, or check the mirror for renamed"
  echo "  builds, before starting the real download."
fi
echo

exit $(( bad > 0 ))
