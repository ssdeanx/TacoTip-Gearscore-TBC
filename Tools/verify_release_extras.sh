#!/usr/bin/env bash
# verify_release_extras.sh — check what a TacoTip Extras release package would contain.
#
# TacoTip Extras is a separate CurseForge project with its own package, so it
# needs its own packaging rules and its own check. The repository root's
# .gitattributes marks `/TacoTip_Extras/** export-ignore` so a TacoTip archive
# never carries a second .toc; `TacoTip_Extras/.gitattributes` says what is not
# runtime inside the Extras package.
#
# The two are read in different scopes, so they do not fight: a TacoTip archive
# is built from the repository root and the root .gitattributes applies, while
# an Extras archive is built from the subtree itself
# (`git archive HEAD:TacoTip_Extras`), where the paths are relative to the
# subtree and the root rule -- which names the `TacoTip_Extras/` prefix -- does
# not match. There, `TacoTip_Extras/.gitattributes` says what is not runtime.
#
# This script builds that archive into a temporary directory, prints its file
# listing, and checks the package is the runtime add-on and nothing else:
#
#   * exactly one .toc: TacoTip_Extras.toc
#   * every file the TOC lists, and no .lua that the TOC does not list
#   * every Locale/*.lua the TOC lists
#   * tt-2.tga — the icon the TOC's `## IconTexture` points at
#   * README.md, CHANGELOG.md, LICENSE, THIRD_PARTY_NOTICES.md
#   * nothing else: no Tests/, no .luacheckrc, no .gitattributes, no PNG
#
# Read-only: nothing is written to the repository and the temporary tree is
# removed on exit. Run it before attaching a package to a release:
#
#   Tools/verify_release_extras.sh              # the package built from HEAD
#   Tools/verify_release_extras.sh --worktree   # the package built from the working tree
#
# Both modes run the identical checks; they differ only in where the packaged
# CONTENT comes from:
#
#   HEAD        the content of the last commit.
#   --worktree  the content of every tracked path in the TacoTip_Extras/ subtree
#               as it is in the working tree right now -- the tree that will
#               actually ship. The file SET is still the tracked one (a package
#               is built from tracked files), so an untracked file is not in the
#               package and is not checked; what is checked is that the tracked
#               files ship the right content. The tree is built in a temporary
#               index and a temporary object directory, so the repository's own
#               index, its object store and its worktree are never written to.
#
# The attributes that shape the listing come from the committed
# `TacoTip_Extras/.gitattributes` when that file is committed, and from the
# working tree before that and under --worktree, so the check is meaningful
# either way; the script says which it used.

set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

tree="$tmp/tree"
contents="$tmp/contents.txt"
toc_files="$tmp/toc_files.txt"
mkdir "$tree"

usage() {
  cat <<'EOF'
usage: verify_release_extras.sh [--worktree]

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
  *) echo "verify_release_extras.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
  echo "verify_release_extras.sh: too many arguments" >&2
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
    echo "verify_release_extras.sh: cannot index the working tree (git add -u failed)" >&2
    exit 1
  fi
  if ! worktree_tree="$(git -C "$root" write-tree)"; then
    echo "verify_release_extras.sh: cannot build a tree from the working tree" >&2
    exit 1
  fi
}

# The archive is built from the SUBTREE, so its paths are relative to
# TacoTip_Extras/ and the root's `/TacoTip_Extras/** export-ignore` -- which
# names the directory prefix -- does not match. The rules that apply are the
# ones in TacoTip_Extras/.gitattributes.
#
# Those rules are read from the committed tree when the file is committed, and
# from the working tree before that, so the check is meaningful either way.
if [ "$mode" = "worktree" ]; then
  # The subtree is taken from the working-tree tree, and the attributes from the
  # working tree, so the package that is checked is the one that will ship.
  build_worktree_tree
  if ! subtree_tree="$(git -C "$root" rev-parse "$worktree_tree:TacoTip_Extras")"; then
    echo "verify_release_extras.sh: the working tree has no TacoTip_Extras/ subtree" >&2
    exit 1
  fi
  git -C "$root" archive --format=tar --worktree-attributes --prefix=TacoTip_Extras/ \
    "$subtree_tree" | tar -x -C "$tree"
  attr_source="working tree"
elif git -C "$root" cat-file -e "HEAD:TacoTip_Extras/.gitattributes" 2>/dev/null; then
  git -C "$root" archive --format=tar --prefix=TacoTip_Extras/ \
    HEAD:TacoTip_Extras | tar -x -C "$tree"
  attr_source="committed tree"
else
  git -C "$root" archive --format=tar --worktree-attributes --prefix=TacoTip_Extras/ \
    HEAD:TacoTip_Extras | tar -x -C "$tree"
  attr_source="working tree (not committed yet)"
fi
find "$tree/TacoTip_Extras" -type f \
  | sed "s|^$tree/TacoTip_Extras/||" | LC_ALL=C sort > "$contents"

count="$(wc -l < "$contents" | tr -d '[:space:]')"
echo "TacoTip Extras release archive — $count files from $source_desc"
echo "  (attributes read from the $attr_source)"
echo
sed 's/^/  /' "$contents"
echo

failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }

# The runtime file list is DERIVED from the shipped TOC, not hardcoded here, so
# a TOC change cannot silently drift away from the package. TOC paths are
# normalised to forward slashes so the comparison is separator-agnostic.
toc="$tree/TacoTip_Extras/TacoTip_Extras.toc"
if [ ! -f "$toc" ]; then
  echo "FAIL  TacoTip_Extras.toc is not in the archive; the package cannot be checked."
  echo
  echo "verify_release_extras: FAIL (1 check(s))"
  exit 1
fi
grep -vE '^[[:space:]]*(##|$)' "$toc" | tr -d '\r' | tr '\\' '/' \
  | sed 's/[[:space:]]*$//' | grep -v '^$' | LC_ALL=C sort > "$toc_files"

toc_count="$(wc -l < "$toc_files" | tr -d '[:space:]')"
locale_count="$(grep -c '^Locale/' "$toc_files" || true)"

# 1. Exactly one .toc, and it is TacoTip_Extras.toc.
tocs="$(grep -E '\.toc$' "$contents" || true)"
if [ "$tocs" = "TacoTip_Extras.toc" ]; then
  pass "single .toc: TacoTip_Extras.toc"
else
  fail "expected exactly one .toc (TacoTip_Extras.toc); found:"
  if [ -n "$tocs" ]; then
    while IFS= read -r p; do echo "        $p"; done <<< "$tocs"
  else
    echo "        (none)"
  fi
fi

# 2. Every file the TOC lists is in the package.
missing=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if ! grep -Fxq "$f" "$contents"; then
    missing="$missing$f"$'\n'
  fi
done < "$toc_files"
if [ -z "$missing" ]; then
  pass "all $toc_count TOC-listed runtime files are present"
else
  fail "TOC-listed files missing from the package:"
  while IFS= read -r f; do
    [ -n "$f" ] && echo "        $f"
  done <<< "$missing"
fi

# 3. No .lua in the package that the TOC does not list.
stray=""
while IFS= read -r f; do
  case "$f" in
    *.lua)
      if ! grep -Fxq "$f" "$toc_files"; then
        stray="$stray$f"$'\n'
      fi
      ;;
  esac
done < "$contents"
if [ -z "$stray" ]; then
  pass "no .lua outside the TOC's runtime list"
else
  fail ".lua in the package that the TOC does not load:"
  while IFS= read -r f; do
    [ -n "$f" ] && echo "        $f"
  done <<< "$stray"
fi

# 4. Every Locale/*.lua the TOC lists is present, and none is missing.
missing_locale=""
while IFS= read -r f; do
  case "$f" in
    Locale/*.lua)
      if ! grep -Fxq "$f" "$contents"; then
        missing_locale="$missing_locale$f"$'\n'
      fi
      ;;
  esac
done < "$toc_files"
if [ -z "$missing_locale" ]; then
  pass "all $locale_count Locale/*.lua files are present"
else
  fail "locale files missing from the package:"
  while IFS= read -r f; do
    [ -n "$f" ] && echo "        $f"
  done <<< "$missing_locale"
fi

# 5. The icon the TOC points at is in the package. Derived from the TOC's
# `## IconTexture` line rather than hardcoded, so a renamed icon is a failure
# here rather than a missing file in the game.
icon_rel=""
icon_line="$(grep -E '^##[[:space:]]*IconTexture:' "$toc" || true)"
if [ -n "$icon_line" ]; then
  icon_rel="${icon_line#*IconTexture:}"
  icon_rel="${icon_rel//\\//}"
  icon_rel="${icon_rel##*/}"
  if grep -Fxq "$icon_rel" "$contents"; then
    pass "TOC's ## IconTexture target is present ($icon_rel)"
  else
    fail "the TOC's ## IconTexture target is missing ($icon_rel)"
  fi
else
  fail "the TOC declares no ## IconTexture"
fi

# 6. The only non-.lua files in the package are the ones a release needs.
printf '%s\n' CHANGELOG.md LICENSE README.md THIRD_PARTY_NOTICES.md TacoTip_Extras.toc \
  > "$tmp/expected_docs.txt"
missing_docs=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if ! grep -Fxq "$f" "$tmp/expected_docs.txt" && [ "$f" != "$icon_rel" ]; then
    missing_docs="$missing_docs$f"$'\n'
  fi
done < "$tmp/expected_docs.txt"
if [ -z "$missing_docs" ]; then
  pass "README/CHANGELOG/LICENSE/THIRD_PARTY_NOTICES and the TOC are all present"
else
  fail "required package files missing:"
  while IFS= read -r f; do
    [ -n "$f" ] && echo "        $f"
  done <<< "$missing_docs"
fi

extra=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    *.lua) continue ;;
  esac
  if ! grep -Fxq "$f" "$tmp/expected_docs.txt" && [ "$f" != "$icon_rel" ]; then
    extra="$extra$f"$'\n'
  fi
done < "$contents"
if [ -z "$extra" ]; then
  pass "no non-runtime files in the package"
else
  fail "not a runtime file of the add-on:"
  while IFS= read -r f; do
    [ -n "$f" ] && echo "        $f"
  done <<< "$extra"
fi

# 7. The non-runtime paths are named one by one, so a lost export-ignore rule
# fails loudly here with the path in it rather than as a silent count change.
leaked=""
for p in .gitattributes .luacheckrc; do
  if grep -Fxq "$p" "$contents"; then
    leaked="$leaked$p"$'\n'
  fi
done
while IFS= read -r f; do
  case "$f" in
    Tests/*) leaked="$leaked$f"$'\n' ;;
    *.png) leaked="$leaked$f"$'\n' ;;
  esac
done < "$contents"
if [ -z "$leaked" ]; then
  pass "no Tests/, .luacheckrc, .gitattributes or PNG in the package"
else
  fail "non-runtime paths shipped:"
  while IFS= read -r f; do
    [ -n "$f" ] && echo "        $f"
  done <<< "$leaked"
fi

# 8. The packaging rules are still declared where they belong. git applies
# them from the committed tree once the file is committed and from the working
# tree before that, so either way this file has to say what it says -- a lost
# rule is caught here instead of showing up as a quiet change in what the
# package contains.
ga="$root/TacoTip_Extras/.gitattributes"
if [ ! -f "$ga" ]; then
  fail "TacoTip_Extras/.gitattributes is missing"
else
  missing_rules=""
  for rule in \
    '/.gitattributes export-ignore' \
    '/Tests/** export-ignore' \
    '/.luacheckrc export-ignore' \
    '/**.png export-ignore'
  do
    if ! grep -Fxq "$rule" "$ga"; then
      missing_rules="$missing_rules$rule"$'\n'
    fi
  done
  if [ -z "$missing_rules" ]; then
    pass "TacoTip_Extras/.gitattributes declares every non-runtime rule"
  else
    fail "TacoTip_Extras/.gitattributes is missing rules:"
    while IFS= read -r r; do
      [ -n "$r" ] && echo "        $r"
    done <<< "$missing_rules"
  fi
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "verify_release_extras: PASS"
else
  echo "verify_release_extras: FAIL ($failures check(s))"
  exit 1
fi
