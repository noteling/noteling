#!/bin/bash
# Refuses an app that another account on the Mac couldn't read or run, or could change.
# Usage: check-modes.sh <folder> | <file.dmg> | <file.pkg>
# A DMG is checked as mounted and a .pkg as it unpacks: what a person gets, not what it was made from.
set -euo pipefail
TARGET="${1:?usage: check-modes.sh <folder, .dmg or .pkg>}"

WORK="$(mktemp -d)"
MOUNTED=""
cleanup() {
  if [ -n "$MOUNTED" ]; then hdiutil detach "$WORK/mount" -force >/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

case "$TARGET" in
  *.dmg)
    mkdir "$WORK/mount"
    hdiutil attach -readonly -nobrowse -mountpoint "$WORK/mount" "$TARGET" >/dev/null
    MOUNTED=1
    APP="$WORK/mount/Noteling.app" ;;
  *.pkg)
    pkgutil --expand "$TARGET" "$WORK/pkg"
    mkdir "$WORK/payload"
    tar -xpf "$WORK/pkg/Payload" -C "$WORK/payload"   # -p: the modes it carries, whatever our umask
    APP="$WORK/payload/Noteling.app" ;;
  *) APP="$TARGET" ;;
esac
[ -d "$APP" ] || { echo "refused: no app to check in $TARGET"; exit 1; }

# Links are skipped: macOS follows them without using their own mode.
BAD="$(find "$APP" ! -type l \( ! -perm -444 -o -perm -020 -o -perm -002 \
  -o \( -type d ! -perm -111 \) -o \( -perm -100 ! -perm -011 \) \) -exec stat -f '%Sp %N' {} +)"
if [ -n "$MOUNTED" ]; then   # the window the app is dragged from
  BAD="$BAD$(find "$WORK/mount" -maxdepth 0 ! -perm -555 -exec stat -f '%Sp %N' {} +)"
fi
if [ -n "$BAD" ]; then
  echo "refused: in $TARGET another account couldn't open these, or could change them:"
  echo "$BAD"
  exit 1
fi
echo "modes ok: $TARGET"
