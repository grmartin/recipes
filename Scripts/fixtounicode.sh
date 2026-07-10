#!/bin/sh
# fixtounicode.sh - convert ASCII vulgar fractions and degree notations
# (C/F/K) in a markdown file to their Unicode equivalents, in place.
#
# Usage: fixtounicode.sh <markdown-file>
#
# Portability: written in POSIX sh, avoiding bashisms, GNU-only sed/awk
# extensions (\<, \>, \b, -i without a backup arg), and non-stock tools
# (realpath, python, perl) so it runs unmodified on stock macOS (BSD
# sed/awk, bash 3.2 /bin/sh), stock Debian (GNU sed/awk, dash /bin/sh),
# and Debian under WSL2 or Cygwin.
set -eu

printf "This is a test script. It is not yet to be trusted. Use at your own risk."

usage() {
    printf 'Usage: %s <markdown-file>\n' "$(basename -- "$0")" >&2
}

if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

target=$1

if [ ! -f "$target" ]; then
    printf 'Error: no such file: %s\n' "$target" >&2
    exit 1
fi

# Resolve an absolute path without relying on realpath/readlink -f, which
# are not guaranteed present on stock macOS.
abs_path() {
    _dir=$(dirname -- "$1")
    _base=$(basename -- "$1")
    _dir_abs=$(cd "$_dir" 2>/dev/null && pwd -P) || return 1
    printf '%s/%s\n' "$_dir_abs" "$_base"
}

# shellcheck disable=SC2310
# Intentional: calling abs_path inside `||` disables set -e for this call so
# we can catch its failure and print a clean error instead of a raw trace.
file_abs=$(abs_path "$target") || {
    printf 'Error: cannot resolve path: %s\n' "$target" >&2
    exit 1
}
file_dir=$(dirname -- "$file_abs")

# --- Determine whether user approval is required --------------------------
# Approval is required if the file is: outside any git repo, untracked
# (never committed), or currently altered (staged and/or unstaged relative
# to HEAD).

needs_approval=0
reason=""

if git -C "$file_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    status_line=$(git -C "$file_dir" status --porcelain -- "$file_abs" 2>/dev/null || true)
    if [ -n "$status_line" ]; then
        needs_approval=1
        case $status_line in
            '??'*) reason="file is new and has not been committed yet" ;;
            *) reason="file has uncommitted changes (staged and/or unstaged)" ;;
        esac
    fi
else
    needs_approval=1
    reason="file is not inside a git repository"
fi

if [ "$needs_approval" -eq 1 ]; then
    printf 'fixtounicode.sh: %s\n' "$reason" >&2
    printf 'This file will be modified in place: %s\n' "$file_abs" >&2
    printf 'Proceed? [y/N] ' >&2
    IFS= read -r reply || reply=""
    case $reply in
        y|Y|yes|YES|Yes) ;;
        *)
            printf 'Aborted; no changes made.\n' >&2
            exit 1
            ;;
    esac
fi

# --- Conversion -------------------------------------------------------------
# LC_ALL=C keeps sed's matching byte-wise and consistent across BSD sed
# (macOS) and GNU sed (Debian/WSL2/Cygwin). Patterns only match ASCII
# digits/letters, so pre-existing multi-byte UTF-8 content (e.g. already
# converted fractions) is never misinterpreted: UTF-8 continuation bytes
# are always >= 0x80 and cannot collide with ASCII digit/letter/space bytes.
#
# Degree matching is uppercase-only (F/C/K) and requires the letter to be
# directly preceded by a number (optionally with a pre-existing degree sign
# and/or spacing) so that ordinary words are left untouched. Kelvin has no
# combined Unicode "degree Kelvin" character (SI doesn't use one), so it is
# normalized to DEGREE SIGN + K instead of a single glyph.
#
# Neither sed dialect supports \< \> / \b reliably in the same way (BSD sed
# silently fails to match rather than erroring), so word boundaries are
# implemented by capturing and re-emitting a non-digit/non-word boundary
# character instead. Because that consumes the boundary character, back to
# back matches separated by a single boundary char (e.g. "1/2,1/2,1/2")
# would otherwise only convert every other occurrence, so the whole script
# is re-applied to a temp file until the output stabilizes.

sed_script='
  s/(^|[^0-9])1\/2([^0-9]|$)/\1½\2/g
  s/(^|[^0-9])1\/3([^0-9]|$)/\1⅓\2/g
  s/(^|[^0-9])2\/3([^0-9]|$)/\1⅔\2/g
  s/(^|[^0-9])1\/4([^0-9]|$)/\1¼\2/g
  s/(^|[^0-9])3\/4([^0-9]|$)/\1¾\2/g
  s/(^|[^0-9])1\/5([^0-9]|$)/\1⅕\2/g
  s/(^|[^0-9])2\/5([^0-9]|$)/\1⅖\2/g
  s/(^|[^0-9])3\/5([^0-9]|$)/\1⅗\2/g
  s/(^|[^0-9])4\/5([^0-9]|$)/\1⅘\2/g
  s/(^|[^0-9])1\/6([^0-9]|$)/\1⅙\2/g
  s/(^|[^0-9])5\/6([^0-9]|$)/\1⅚\2/g
  s/(^|[^0-9])1\/7([^0-9]|$)/\1⅐\2/g
  s/(^|[^0-9])1\/8([^0-9]|$)/\1⅛\2/g
  s/(^|[^0-9])3\/8([^0-9]|$)/\1⅜\2/g
  s/(^|[^0-9])5\/8([^0-9]|$)/\1⅝\2/g
  s/(^|[^0-9])7\/8([^0-9]|$)/\1⅞\2/g
  s/(^|[^0-9])1\/9([^0-9]|$)/\1⅑\2/g
  s/(^|[^0-9])1\/10([^0-9]|$)/\1⅒\2/g
  s/(^|[^0-9.])([0-9]+(\.[0-9]+)?) *(°)?F([^A-Za-z0-9]|$)/\1\2℉\5/g
  s/(^|[^0-9.])([0-9]+(\.[0-9]+)?) *(°)?C([^A-Za-z0-9]|$)/\1\2℃\5/g
  s/(^|[^0-9.])([0-9]+(\.[0-9]+)?) *(°)?K([^A-Za-z0-9]|$)/\1\2°K\5/g
'

tmp_a=$(mktemp "${TMPDIR:-/tmp}/fixtounicode.XXXXXX")
tmp_b=$(mktemp "${TMPDIR:-/tmp}/fixtounicode.XXXXXX")
trap 'rm -f "$tmp_a" "$tmp_b"' EXIT INT TERM

cat "$file_abs" > "$tmp_a"

max_iter=20
i=0
while [ "$i" -lt "$max_iter" ]; do
    LC_ALL=C sed -E "$sed_script" "$tmp_a" > "$tmp_b"
    if cmp -s "$tmp_a" "$tmp_b"; then
        break
    fi
    mv "$tmp_b" "$tmp_a"
    i=$((i + 1))
done

# Overwrite via the existing inode (not mv) to preserve the original
# file's permissions/ownership.
cat "$tmp_a" > "$file_abs"

printf 'fixtounicode.sh: converted %s\n' "$file_abs" >&2
