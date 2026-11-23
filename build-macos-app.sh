#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
BUILD_DIR="$(/usr/bin/mktemp -d "${TMPDIR%/}/TrPaper-build.XXXXXX")"
APP_NAME="TrPaper"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
WORKER_DIR="$SCRIPT_DIR/worker-dist/TrPaperWorker"
WORKER_RESOURCES="$SCRIPT_DIR/worker-dist/resources"

find_key() {
  if [[ -n "${DEEPSEEK_API_KEY:-}" ]]; then
    print -r -- "$DEEPSEEK_API_KEY"
    return 0
  fi
  local candidate line
  for candidate in \
    "$SCRIPT_DIR/.env" \
    "$SCRIPT_DIR/../.env"; do
    [[ -f "$candidate" ]] || continue
    line="$(/usr/bin/awk -F= '/^DEEPSEEK_API_KEY=/{sub(/^[^=]*=/, ""); gsub(/^['\"']|['\"']$/, ""); print; exit}' "$candidate")"
    if [[ -n "$line" ]]; then
      print -r -- "$line"
      return 0
    fi
  done
  return 1
}

API_KEY="$(find_key || true)"
if [[ -z "$API_KEY" ]]; then
  print -u2 "未找到 DEEPSEEK_API_KEY。可先执行：DEEPSEEK_API_KEY='你的密钥' ./build-macos-app.sh"
  exit 1
fi

/bin/rm -rf "$BUILD_DIR"
/bin/mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

if [[ ! -x "$WORKER_DIR/TrPaperWorker" ]]; then
  "$SCRIPT_DIR/build-worker.sh"
fi

/usr/bin/clang -fobjc-arc -O2 -mmacosx-version-min=13.0 \
  -framework AppKit -framework Security -framework UniformTypeIdentifiers \
  "$SCRIPT_DIR/main.m" -o "$MACOS_DIR/TrPaper"

/usr/bin/clang -fobjc-arc -O2 -mmacosx-version-min=13.0 -framework AppKit \
  "$SCRIPT_DIR/icon_generator.m" -o "$BUILD_DIR/icon-generator"

for pixels in 16 32 64 128 256 512 1024; do
  "$BUILD_DIR/icon-generator" "$BUILD_DIR/icon-${pixels}.png" "$pixels"
done
/bin/cp "$BUILD_DIR/icon-16.png" "$ICONSET_DIR/icon_16x16.png"
/bin/cp "$BUILD_DIR/icon-32.png" "$ICONSET_DIR/icon_16x16@2x.png"
/bin/cp "$BUILD_DIR/icon-32.png" "$ICONSET_DIR/icon_32x32.png"
/bin/cp "$BUILD_DIR/icon-64.png" "$ICONSET_DIR/icon_32x32@2x.png"
/bin/cp "$BUILD_DIR/icon-128.png" "$ICONSET_DIR/icon_128x128.png"
/bin/cp "$BUILD_DIR/icon-256.png" "$ICONSET_DIR/icon_128x128@2x.png"
/bin/cp "$BUILD_DIR/icon-256.png" "$ICONSET_DIR/icon_256x256.png"
/bin/cp "$BUILD_DIR/icon-512.png" "$ICONSET_DIR/icon_256x256@2x.png"
/bin/cp "$BUILD_DIR/icon-512.png" "$ICONSET_DIR/icon_512x512.png"
/bin/cp "$BUILD_DIR/icon-1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

/usr/bin/ditto "$WORKER_DIR" "$RESOURCES_DIR/TrPaperWorker"
/usr/bin/ditto "$WORKER_RESOURCES" "$RESOURCES_DIR/TranslationResources"

/bin/cp "$SCRIPT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
/bin/cp "$SCRIPT_DIR/LICENSE" "$RESOURCES_DIR/LICENSE"
/bin/cp "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md"
/usr/bin/xattr -cr "$APP_DIR" 2>/dev/null || true
/usr/bin/xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
/usr/bin/xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$APP_DIR" >/dev/null

print "已构建：$APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
  INSTALL_DIR="/Applications/$APP_NAME.app"
  /bin/rm -rf "$INSTALL_DIR"
  /usr/bin/ditto "$APP_DIR" "$INSTALL_DIR"
  /usr/bin/xattr -cr "$INSTALL_DIR" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.FinderInfo "$INSTALL_DIR" 2>/dev/null || true
  /usr/bin/xattr -d 'com.apple.fileprovider.fpfs#P' "$INSTALL_DIR" 2>/dev/null || true
  /usr/bin/codesign --force --deep --sign - "$INSTALL_DIR" >/dev/null
  # Put the secret on stdin rather than the process command line, so it never
  # appears in `ps` output or build logs. With `-w` last, `security` reads it.
  /usr/bin/printf '%s\n' "$API_KEY" | /usr/bin/security add-generic-password \
    -U -a "$USER" -s "com.essaypod.trpaper.deepseek" \
    -T "$INSTALL_DIR/Contents/MacOS/TrPaper" -w >/dev/null
  print "已安装：$INSTALL_DIR"
  /usr/bin/find "$BUILD_DIR" -depth -delete 2>/dev/null || true
fi

