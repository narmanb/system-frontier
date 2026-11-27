#!/usr/bin/env bash
# Downloads the pinned Godot editor (and optionally export templates) and verifies SHA-512.
# Usage: setup_godot.sh <install-dir> [templates]
# Pinned checksums are from the official 4.7.2-stable SHA512-SUMS.txt.
set -euo pipefail
VERSION="$(cat .godot-version)"           # e.g. 4.7.2-stable
DIR="${1:?install dir required}"; WANT_TEMPLATES="${2:-}"
BASE="https://github.com/godotengine/godot/releases/download/${VERSION}"
EDITOR_ZIP="Godot_v${VERSION}_linux.x86_64.zip"
EDITOR_SHA512="9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65"
TPZ="Godot_v${VERSION}_export_templates.tpz"
TPZ_SHA512="ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"
mkdir -p "$DIR"
if [ ! -x "$DIR/godot" ]; then
  curl -fsSL --retry 4 -o "$DIR/$EDITOR_ZIP" "$BASE/$EDITOR_ZIP"
  echo "$EDITOR_SHA512  $DIR/$EDITOR_ZIP" | sha512sum -c -
  unzip -oq "$DIR/$EDITOR_ZIP" -d "$DIR"
  mv "$DIR/Godot_v${VERSION}_linux.x86_64" "$DIR/godot"
  rm -f "${DIR:?}/${EDITOR_ZIP:?}"
fi
"$DIR/godot" --version
if [ "$WANT_TEMPLATES" = "templates" ]; then
  TDIR="$HOME/.local/share/godot/export_templates/${VERSION/-/.}"
  if [ ! -f "$TDIR/version.txt" ]; then
    curl -fsSL --retry 4 -o "$DIR/$TPZ" "$BASE/$TPZ"
    echo "$TPZ_SHA512  $DIR/$TPZ" | sha512sum -c -
    mkdir -p "$TDIR"
    # Only the templates we export with (keeps disk and cache use down).
    unzip -oqj "$DIR/$TPZ" templates/version.txt \
      templates/android_debug.apk templates/android_release.apk \
      'templates/linux_*.x86_64' 'templates/linux_*.arm64' \
      'templates/windows_*_x86_64*.exe' 'templates/web_nothreads_*.zip' -d "$TDIR"
    rm -f "${DIR:?}/${TPZ:?}"
  fi
  ls "$TDIR"
fi
