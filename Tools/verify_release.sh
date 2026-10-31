#!/usr/bin/env bash
# verify_release.sh — check what a TacoTip release package would contain.
#
# The add-on root doubles as the development workshop (bench/, desks/, docs/,
# Tests/, a stale full copy of the add-on in OLD/), so release packages are
# built with `git archive`, filtered by the export-ignore rules in
# .gitattributes. This script builds that archive into a temporary directory,
# prints its file listing, and checks the package is TacoTip's runtime files
# only:
#
#   * exactly one .toc: TacoTip.toc
#   * none of desks/, bench/, docs/, Tests/, OLD/, TacoTip_Extras/, Tools/
#   * none of the workshop documents at the repository root
#   * every file matches the runtime allowlist below
#
# Read-only: nothing is written to the repository and the temporary tree is
# removed on exit. Run it before attaching a package to a release:
#
#   Tools/verify_release.sh              # the package built from HEAD
#   Tools/verify_release.sh --worktree   # the package built from the working tree
#
# Both modes run the identical checks; they differ only in where the packaged
# CONTENT comes from:
#
#   HEAD        the content of the last commit.
#   --worktree  the content of every tracked path as it is in the working tree
#               right now -- the tree that will actually ship. The file SET is
#               still the tracked one (a package is built from tracked files),
#               so an untracked file is not in the package and is not checked;
#               what is checked is that the tracked files ship the right
#               content. The tree is built in a temporary index and a temporary
#               object directory, so the repository's own index, its object
#               store and its worktree are never written to.
#
# `.gitattributes` is read from the working tree (--worktree-attributes) in both
# modes, so the check is meaningful before that file is committed; the file
# listing itself comes from HEAD by default and from the working tree under
# --worktree.

set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

tree="$tmp/tree"
contents="$tmp/contents.txt"
mkdir "$tree"

usage() {
  cat <<'EOF'
usage: verify_release.sh [--worktree]

  (no option)   validate the release package built from HEAD
  --worktree    validate the release package built from the current working tree
EOF
}

source_desc="HEAD"
mode="head"
case "${1:-}" in
  "") ;;
  --worktree) source_desc="the working tree"; mode="worktree" ;;
  -h|--help) usage; exit 0 ;;
  *) echo "verify_release.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
  echo "verify_release.sh: too many arguments" >&2
  usage >&2
  exit 2
fi

# Build a tree object that holds the CURRENT working-tree content of every
# tracked path, without writing anything into the repository:
#
#   * the repository's index is COPIED to a temporary file, so the real index is
#     never touched;
#   * `git add -u` refreshes that temporary index from the working tree, so a
#     modified file contributes its current content and a deleted file drops
#     out;
#   * `git write-tree` writes the tree into a TEMPORARY object directory, with
#     the repository's own object store attached read-only as an alternate, so
#     no object is written into the repository either.
#
# The result is the tree a release package would carry if the working tree were
# committed, which is what --worktree is meant to check. The GIT_* variables
# are exported on purpose: they must still be in effect for the `git archive`
# call that follows, which reads the tree back out of the temporary store.
build_worktree_tree() {
  local gitdir common objects
  gitdir="$(git -C "$root" rev-parse --absolute-git-dir)"
  common="$(git -C "$root" rev-parse --git-common-dir)"
  case "$common" in
    /*) ;;
    *) common="$root/$common" ;;
  esac
  objects="$common/objects"

  mkdir -p "$tmp/objects"
  export GIT_INDEX_FILE="$tmp/index"
  export GIT_OBJECT_DIRECTORY="$tmp/objects"
  export GIT_ALTERNATE_OBJECT_DIRECTORIES="$objects"

  if [ -f "$gitdir/index" ]; then
    cp "$gitdir/index" "$GIT_INDEX_FILE"
  else
    git -C "$root" read-tree HEAD
  fi
  if ! git -C "$root" add -u; then
    echo "verify_release.sh: cannot index the working tree (git add -u failed)" >&2
    exit 1
  fi
  if ! worktree_tree="$(git -C "$root" write-tree)"; then
    echo "verify_release.sh: cannot build a tree from the working tree" >&2
    exit 1
  fi
}

if [ "$mode" = "head" ]; then
  git -C "$root" archive --format=tar --worktree-attributes HEAD | tar -x -C "$tree"
else
  build_worktree_tree
  git -C "$root" archive --format=tar --worktree-attributes "$worktree_tree" \
    | tar -x -C "$tree"
fi
find "$tree" -type f | sed "s|^$tree/||" | LC_ALL=C sort > "$contents"

count="$(wc -l < "$contents" | tr -d '[:space:]')"
echo "TacoTip release archive — $count files from $source_desc"
echo
sed 's/^/  /' "$contents"
echo

failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }

# 1. Exactly one .toc, and it is TacoTip.toc.
tocs="$(grep -E '\.toc$' "$contents" || true)"
if [ "$tocs" = "TacoTip.toc" ]; then
  pass "single .toc: TacoTip.toc"
else
  fail "expected exactly one .toc (TacoTip.toc); found:"
  if [ -n "$tocs" ]; then
    while IFS= read -r p; do echo "        $p"; done <<< "$tocs"
  else
    echo "        (none)"
  fi
fi

# 2. No workshop directories, at the root or nested.
shipped=""
for d in desks bench docs Tests OLD TacoTip_Extras Tools; do
  if grep -Eq "(^|/)$d/" "$contents"; then
    shipped="$shipped $d/"
  fi
done
if [ -z "$shipped" ]; then
  pass "no workshop directories (desks/ bench/ docs/ Tests/ OLD/ TacoTip_Extras/ Tools/)"
else
  fail "workshop paths shipped:$shipped"
fi

# 2b. No workshop documents at the repository root. These are individual files
# rather than directories, so they need their own list: the export-ignore rules
# in .gitattributes are what keeps them out of the archive, and this check is
# what fails loudly if one of those rules is ever lost.
shipped_docs=""
for f in hands-up.md workshop.md; do
  if grep -Fxq "$f" "$contents"; then
    shipped_docs="$shipped_docs $f"
  fi
done
if [ -z "$shipped_docs" ]; then
  pass "no workshop documents (hands-up.md workshop.md)"
else
  fail "workshop documents shipped:$shipped_docs"
fi

# 3. Runtime allowlist — report every file not deliberately shipped.
unexpected=""
while IFS= read -r f; do
  case "$f" in
    TacoTip.toc|CHANGELOG.md|LICENSE|README.md|THIRD_PARTY_NOTICES.md|tt.tga) ;;
    */*)
      case "$f" in
        Locale/*.lua|Libs/*) ;;
        *) unexpected="$unexpected$f"$'\n' ;;
      esac
      ;;
    *.lua) ;;
    *) unexpected="$unexpected$f"$'\n' ;;
  esac
done < "$contents"
if [ -z "$unexpected" ]; then
  pass "runtime files only (root *.lua, Locale/*.lua, Libs/*, TacoTip.toc, tt.tga, README/CHANGELOG/LICENSE/THIRD_PARTY_NOTICES)"
else
  fail "not on the runtime allowlist:"
  while IFS= read -r f; do
    [ -n "$f" ] && echo "        $f"
  done <<< "$unexpected"
fi

# 4. Version consistency. A release bump touches the TOC, both Lua fallbacks
# (used when GetAddOnMetadata is unavailable) and the README frontmatter; if
# they drift, the package advertises two versions.
toc_version="$(sed -n 's/^## Version:[[:space:]]*//p' "$tree/TacoTip.toc" | tr -d '\r' | head -1)"
if [ -n "$toc_version" ] \
  && grep -Fq "\"$toc_version\"" "$tree/main.lua" \
  && grep -Fq "\"$toc_version\"" "$tree/options.lua" \
  && grep -Fxq "version: $toc_version" "$tree/README.md"; then
  pass "version $toc_version is consistent (TOC, main.lua, options.lua, README)"
else
  fail "version drift (TOC='$toc_version'; check main.lua/options.lua fallbacks and README 'version:')"
fi

# 5. Interfaces. The five supported client builds are load-bearing: a missing or
# stale value is an "out of date" add-on on that client.
interfaces_line="$(grep -m1 '^## Interface:' "$tree/TacoTip.toc" | tr -d '\r')"
missing_iface=""
for iface in 11509 20506 38002 16001 120105; do
  case "$interfaces_line" in
    *"$iface"*) ;;
    *) missing_iface="$missing_iface $iface" ;;
  esac
done
if [ -z "$missing_iface" ]; then
  pass "TOC advertises all five interfaces (11509, 20506, 38002, 16001, 120105)"
else
  fail "TOC is missing interface(s):$missing_iface"
fi

# 6. SavedVariables name, so a rename cannot ship silently.
if grep -Eq '^## SavedVariables:.*TacoTipConfig' "$tree/TacoTip.toc"; then
  pass "SavedVariables declares TacoTipConfig"
else
  fail "TOC does not declare TacoTipConfig in ## SavedVariables"
fi

# 7. The icon target exists in the package.
icon_rel="$(grep -m1 '^## IconTexture:' "$tree/TacoTip.toc" | sed 's/^## IconTexture:[[:space:]]*//' | tr -d '\r' | tr '\\\\' '/')"
icon_rel="${icon_rel#Interface/AddOns/TacoTip/}"
if [ -n "$icon_rel" ] && [ -f "$tree/$icon_rel" ]; then
  pass "icon target exists ($icon_rel)"
else
  fail "icon target missing from the package: '$icon_rel'"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "verify_release: PASS"
else
  echo "verify_release: FAIL ($failures check(s))"
  exit 1
fi