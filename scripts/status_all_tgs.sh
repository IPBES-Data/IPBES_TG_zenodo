#!/usr/bin/env bash
#
# status_all_tgs.sh — Show git status per IPBES_* directory
#
# What it does
# - Finds all top-level subdirectories matching IPBES_*.
# - For each directory, determines the enclosing git repository root.
# - Shows git status limited to the files under that specific IPBES_* directory.
#
# Why this is useful
# - The TGs workspace can include multiple nested git repositories.
# - Running a plain `git status` at the workspace root would miss or mix
#   changes from nested repos. This script scopes status per guide.
#
# Output format
# - Header line:  "--- <dir> (repo: <repo-name>)"
# - If no changes under that directory: prints "No changes".
# - Otherwise prints the porcelain status lines (added/modified/untracked),
#   indented by two spaces for readability, only for paths inside the directory.
#
# Notes
# - If a directory is not inside a git repo, it is skipped with a message.
# - Exits successfully even when no IPBES_* directories are found.

set -euo pipefail

## Guard: require git

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git not found in PATH" >&2
  exit 127
fi

echo "Scanning status for IPBES_* directories..."

found_any=false
while IFS= read -r -d '' dir; do
  found_any=true
  name="$(basename "$dir")"
  # Determine repo root and the path of the IPBES_* directory relative to it
  if ! repo_root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"; then
    echo "--- $name: SKIP (not in a git repo)"
    continue
  fi
  dir_abs="$(cd "$dir" && pwd)"
  rel_path="${dir_abs#${repo_root}/}"

  echo "--- $name (repo: $(basename "$repo_root"))"
  # Ask git for changes only under the scoped directory
  changes="$(git -C "$repo_root" status --porcelain=1 --untracked-files=all -- "$rel_path" || true)"
  if [ -z "$changes" ]; then
    echo "No changes"
  else
    echo "$changes" | sed 's/^/  /'
  fi
  echo
done < <(find . -maxdepth 1 -mindepth 1 -type d -name 'IPBES_*' -print0)

if [ "$found_any" = false ]; then
  echo "No IPBES_* directories found at this level."
fi

exit 0
