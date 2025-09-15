#!/usr/bin/env bash
#
# export_frontmatter.sh — Extract YAML front matter from a QMD
# Usage:
#   ./scripts/export_frontmatter.sh [path/to/file.qmd]
#
# Writes a standalone YAML document (with --- separators) to:
#   metadata_qmd.yaml
# in the repository root (same directory as the QMD).

set -euo pipefail

# Resolve repo root as the parent of this script's directory
script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
cd "$repo_root"

qmd=${1:-}
if [ -z "$qmd" ]; then
  qmd=$(ls -1 *.qmd 2>/dev/null | head -n1 || true)
fi

if [ -z "$qmd" ] || [ ! -f "$qmd" ]; then
  echo "ERROR: No .qmd file specified and none found in $(pwd)" >&2
  exit 1
fi

tmp_yaml=".frontmatter.$$"

# Extract lines between the first two '---' separators, normalize CRLF → LF
awk 'BEGIN{fs=0}
     { gsub(/\r$/, "", $0) }
     NR==1 && $0~/^---[[:space:]]*$/ {fs=1; next}
     fs==1 && $0~/^---[[:space:]]*$/ {exit}
     fs==1 {print}' "$qmd" > "$tmp_yaml" || true

if ! [ -s "$tmp_yaml" ]; then
  echo "ERROR: No YAML front matter found in $qmd" >&2
  rm -f "$tmp_yaml"
  exit 2
fi

out="metadata_qmd.yaml"
{
  echo '---'
  cat "$tmp_yaml"
  echo '---'
} > "$out"

rm -f "$tmp_yaml"
echo "Wrote $out (from $qmd)"

