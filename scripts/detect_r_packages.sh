#!/usr/bin/env bash
# Detect whether any Quarto .qmd uses R, and if so, write required
# package names (one per line) to R.pkgs in the repo root.
# Heuristics only (no R required).
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
tmp_files=".detect_r_pkgs_files.$$"
if [ "$#" -gt 0 ]; then
  printf '%s\n' "$@" > "$tmp_files"
else
  git ls-files '*.qmd' 2>/dev/null > "$tmp_files" || true
fi
if ! [ -s "$tmp_files" ]; then rm -f R.pkgs "$tmp_files"; exit 0; fi
needs_r=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if grep -Fiq '```{r' "$f" || grep -Eq 'engine:[[:space:]]*[Rr]' "$f" || grep -Fq 'knitr::' "$f"; then
    needs_r=1; break; fi
done < "$tmp_files"
if [ "$needs_r" -ne 1 ]; then rm -f R.pkgs "$tmp_files"; exit 0; fi
all_eval_false=1
while IFS= read -r f; do
  [ -f "$f" ] || continue
  file_eval_false=0
  yaml=$(awk 'BEGIN{fs=0} /^---[[:space:]]*$/{fs++; next} fs==1{print}' "$f" 2>/dev/null || true)
  if printf '%s\n' "$yaml" | grep -Ei '^[[:space:]]*eval:[[:space:]]*(false|no|0)[[:space:]]*$' >/dev/null; then file_eval_false=1; fi
  if printf '%s\n' "$yaml" | grep -Ei '^[[:space:]]*execute:[[:space:]]*$' >/dev/null; then
    if printf '%s\n' "$yaml" | awk 'inexec==1 && /^[^[:space:]-]/{inexec=0} /^execute:[[:space:]]*$/{inexec=1} {if(inexec==1) print}' | \
       grep -Ei '^[[:space:]]*eval:[[:space:]]*(false|no|0)[[:space:]]*$' >/dev/null; then file_eval_false=1; fi
  fi
  if grep -Ei 'knitr::opts_chunk\$set\([^)]*eval[[:space:]]*=[[:space:]]*(false|no|0|f)\b' "$f" >/dev/null; then file_eval_false=1; fi
  if [ "$file_eval_false" -ne 1 ]; then all_eval_false=0; break; fi
done < "$tmp_files"
if [ "$all_eval_false" -eq 1 ]; then echo knitr > R.pkgs; rm -f "$tmp_files"; exit 0; fi
pkg_tmp=".detect_r_pkgs_pkgs.$$"
while IFS= read -r f; do
  [ -f "$f" ] || continue
  grep -Eho 'library[[:space:]]*\([[:space:]]*[^)]+' "$f" || true
  grep -Eho 'require[[:space:]]*\([[:space:]]*[^)]+' "$f" || true
  grep -Eho 'requireNamespace[[:space:]]*\([[:space:]]*[^)]+' "$f" || true
done < "$tmp_files" | sed -E "s/.*\(\s*//; s/^['\"]?//; s/[^A-Za-z0-9_.].*//" >> "$pkg_tmp" || true
while IFS= read -r f; do
  [ -f "$f" ] || continue
  grep -Eho '[A-Za-z0-9_.]+::[A-Za-z0-9_.]+' "$f" || true
done < "$tmp_files" | sed -E 's/::.*$//' >> "$pkg_tmp" || true
awk 'NF{print $0}' "$pkg_tmp" | sort -u > "$pkg_tmp.unique"
grep -Ev '^(base|stats|utils|graphics|grDevices|methods|datasets)$' "$pkg_tmp.unique" | awk 'length($0)>=2' > "$pkg_tmp.filtered" || true
{ echo knitr; cat "$pkg_tmp.filtered"; } | awk 'NF{print $0}' | sort -u > R.pkgs
rm -f "$tmp_files" "$pkg_tmp" "$pkg_tmp.unique" "$pkg_tmp.filtered"
exit 0

