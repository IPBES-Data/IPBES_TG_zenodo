#!/usr/bin/env bash
#
# detect_r_packages.sh — Discover R usage and required packages for Quarto QMDs
#
# Purpose
# - Scan one or more Quarto .qmd files in this repo to determine whether they
#   use the R engine and, if so, which R packages they reference.
# - Write the unique package names, one per line, to a file named `R.pkgs` in
#   the repository root. CI can read this file to conditionally set up R and
#   install only what’s needed.
#
# What it detects
# - R usage via any of the following patterns:
#     - Code fences with ```{r}
#     - YAML/option lines like `engine: r`
#     - Direct references like `knitr::...`
# - Global “do not evaluate” signals:
#     - YAML front matter with `eval: false` or within an `execute:` block
#     - knitr global options `knitr::opts_chunk$set(..., eval = FALSE, ...)`
# - Package references via:
#     - library(pkg), require(pkg), requireNamespace("pkg")
#     - pkg::function occurrences
#
# Behavior
# - If no R usage is detected: do nothing (ensures CI won’t set up R).
# - If all scanned files have global eval=false: write only `knitr` and
#   `rmarkdown` to `R.pkgs` (enough for weaving without evaluation).
# - Otherwise: write `knitr`, `rmarkdown`, plus all detected packages (excluding
#   base/recommended packages).
#
# Usage
#   ./scripts/detect_r_packages.sh [file1.qmd file2.qmd ...]
#   # If no files are passed, scans all tracked *.qmd in this repo.
#
# Output
# - Creates/overwrites `R.pkgs` at the repo root (if R usage is detected).
# - No output file is created when no R usage is found.
#
# Notes and limitations
# - This is a heuristic, regex-based scan; it won’t catch dynamic/indirect
#   references in all cases.
# - No R is required to run this script.
# - Uses only POSIX-friendly shell tools (grep/sed/awk) and avoids features
#   missing in macOS’s default Bash 3.2 (e.g., mapfile, assoc arrays).
set -euo pipefail

# Resolve repository root and switch there to make paths predictable
repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

# Phase 0 — Collect target QMD files into a temp list
# - If file arguments are passed, use them verbatim
# - Otherwise, scan all tracked *.qmd files
tmp_files=".detect_r_pkgs_files.$$"
if [ "$#" -gt 0 ]; then
  printf '%s\n' "$@" > "$tmp_files"
else
  git ls-files '*.qmd' 2>/dev/null > "$tmp_files" || true
fi

# Nothing to do if the list is empty
if ! [ -s "$tmp_files" ]; then rm -f R.pkgs "$tmp_files"; exit 0; fi

# Phase 1 — Detect whether any R is used at all across the files
needs_r=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if grep -Fiq '```{r' "$f" || grep -Eq 'engine:[[:space:]]*[Rr]' "$f" || grep -Fq 'knitr::' "$f"; then
    needs_r=1; break; fi
done < "$tmp_files"

# No R usage detected → ensure no stale R.pkgs remains and exit quietly
if [ "$needs_r" -ne 1 ]; then rm -f R.pkgs "$tmp_files"; exit 0; fi

# Phase 2 — Check if evaluation is globally disabled (eval=false) for all files
all_eval_false=1
while IFS= read -r f; do
  [ -f "$f" ] || continue
  file_eval_false=0
  # Extract YAML front matter (first block between --- and ---)
  yaml=$(awk 'BEGIN{fs=0} /^---[[:space:]]*$/{fs++; next} fs==1{print}' "$f" 2>/dev/null || true)
  # Case A: plain eval: false at the top level of YAML
  if printf '%s\n' "$yaml" | grep -Ei '^[[:space:]]*eval:[[:space:]]*(false|no|0)[[:space:]]*$' >/dev/null; then file_eval_false=1; fi
  # Case B: execute: block with eval: false nested inside
  if printf '%s\n' "$yaml" | grep -Ei '^[[:space:]]*execute:[[:space:]]*$' >/dev/null; then
    if printf '%s\n' "$yaml" | awk 'inexec==1 && /^[^[:space:]-]/{inexec=0} /^execute:[[:space:]]*$/{inexec=1} {if(inexec==1) print}' | \
       grep -Ei '^[[:space:]]*eval:[[:space:]]*(false|no|0)[[:space:]]*$' >/dev/null; then file_eval_false=1; fi
  fi
  # Case C: knitr global options disable evaluation in code
  if grep -Ei 'knitr::opts_chunk\$set\([^)]*eval[[:space:]]*=[[:space:]]*(false|no|0|f)\b' "$f" >/dev/null; then file_eval_false=1; fi
  if [ "$file_eval_false" -ne 1 ]; then all_eval_false=0; break; fi
done < "$tmp_files"

# All files have eval=false → only list knitr+rmarkdown (needed to weave)
if [ "$all_eval_false" -eq 1 ]; then { echo knitr; echo rmarkdown; } | sort -u > R.pkgs; rm -f "$tmp_files"; exit 0; fi

# Phase 3 — Extract referenced packages from the files
pkg_tmp=".detect_r_pkgs_pkgs.$$"
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # Match library()/require()/requireNamespace() and capture text inside parens
  grep -Eho 'library[[:space:]]*\([[:space:]]*[^)]+' "$f" || true
  grep -Eho 'require[[:space:]]*\([[:space:]]*[^)]+' "$f" || true
  grep -Eho 'requireNamespace[[:space:]]*\([[:space:]]*[^)]+' "$f" || true
done < "$tmp_files" | sed -E "s/.*\([[:space:]]*//; s/^['\"]?//; s/[^A-Za-z0-9_.].*//" >> "$pkg_tmp" || true
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # Match pkg::function and keep only the package portion
  grep -Eho '[A-Za-z0-9_.]+::[A-Za-z0-9_.]+' "$f" || true
done < "$tmp_files" | sed -E 's/::.*$//' >> "$pkg_tmp" || true
awk 'NF{print $0}' "$pkg_tmp" | sort -u > "$pkg_tmp.unique"

# Drop base/recommended and any 1-char tokens
grep -Ev '^(base|stats|utils|graphics|grDevices|methods|datasets)$' "$pkg_tmp.unique" | awk 'length($0)>=2' > "$pkg_tmp.filtered" || true

# Always include knitr and rmarkdown at the top of the output
{ echo knitr; echo rmarkdown; cat "$pkg_tmp.filtered"; } | awk 'NF{print $0}' | sort -u > R.pkgs

# Cleanup temp files
rm -f "$tmp_files" "$pkg_tmp" "$pkg_tmp.unique" "$pkg_tmp.filtered"
exit 0
