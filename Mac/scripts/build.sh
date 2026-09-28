#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MAC_ROOT="$(pwd -P)"
REPO_ROOT="$(cd .. && pwd -P)"
if [[ "$(uname -s)" != Darwin ]]; then
    echo "This build requires macOS 14+ and Swift 6+ (Xcode 16+ or compatible Command Line Tools)." >&2
    exit 1
fi
ARCH="$(uname -m)"
WITH_CODEX=1
MAKE_DMG=0
SDK_PATH="${SDKROOT:-}"
for arg in "$@"; do
    case "$arg" in
        --without-codex) WITH_CODEX=0 ;;
        --dmg) MAKE_DMG=1 ;;
        --arch=arm64) ARCH=arm64 ;;
        --arch=x86_64) ARCH=x86_64 ;;
        --sdk=*) SDK_PATH="${arg#--sdk=}" ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done
xcrun --find swift >/dev/null
command -v python3 >/dev/null
# The native engine also discovers Swift Testing plugins in Command Line Tools.
SWIFT_ARGS=(-c release --arch "$ARCH" --build-system native)
if [[ -n "$SDK_PATH" ]]; then
    if [[ ! -d "$SDK_PATH" ]]; then echo "SDK not found: $SDK_PATH" >&2; exit 1; fi
    SWIFT_ARGS+=(--sdk "$SDK_PATH")
fi
if [[ "$WITH_CODEX" == 1 ]]; then
    python3 scripts/fetch-runtime.py --arch "$ARCH"
fi
TEST_ARGS=("${SWIFT_ARGS[@]}" --disable-xctest)
# CLT ships Swift Testing outside the framework paths inferred by SwiftPM.
TEST_FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
if [[ -d "$TEST_FRAMEWORKS/Testing.framework" ]]; then
    TEST_ARGS+=(-Xswiftc -F -Xswiftc "$TEST_FRAMEWORKS" -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS")
fi
swift test "${TEST_ARGS[@]}"
# Rebuild without test-only framework paths before copying the distributable executable.
swift build "${SWIFT_ARGS[@]}"
BIN="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"
APP="$MAC_ROOT/output/$ARCH/SuWuDu.app"
mkdir -p "$MAC_ROOT/output/$ARCH"
# Only this build's generated bundle is replaced. User data lives in Application Support.
if [[ "$APP" != "$MAC_ROOT/output/$ARCH/SuWuDu.app" ]]; then exit 1; fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Assets" "$APP/Contents/Frameworks" "$APP/Contents/Helpers"
cp "$BIN/SuWuDu" "$APP/Contents/MacOS/SuWuDu"
cp -R "$BIN/SuWuDuMac_SuWuDu.bundle" "$APP/Contents/Resources/"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp -R "$REPO_ROOT/Assets/Sprites" "$APP/Contents/Resources/Assets/"
cp -R "$REPO_ROOT/Assets/Sounds" "$APP/Contents/Resources/Assets/"
cp "$REPO_ROOT/OPENAI-CODEX-LICENSE.txt" "$APP/Contents/Resources/"
cp Support/ThirdPartyNotices.txt "$APP/Contents/Resources/"
SPARKLE="$(find "$MAC_ROOT/.build/artifacts" -type d -path '*/macos*/Sparkle.framework' -print -quit)"
if [[ -z "$SPARKLE" ]]; then echo "Sparkle framework missing" >&2; exit 1; fi
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
if [[ "$WITH_CODEX" == 1 ]]; then
    mkdir -p "$APP/Contents/Helpers/Codex"
    cp "runtime/$ARCH/codex" "runtime/$ARCH/codex-code-mode-host" "$APP/Contents/Helpers/Codex/"
    cp "runtime/$ARCH/runtime-manifest.json" "$APP/Contents/Resources/codex-runtime-manifest.json"
fi
ICONSET="$MAC_ROOT/output/$ARCH/AppIcon.iconset"
mkdir -p "$ICONSET"
# Full-bleed jade artwork keeps the macOS icon from becoming a small inset badge.
ICON_SOURCE="$MAC_ROOT/Support/AppIcon.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${UPDATE_FEED_URL:-}" || -n "${UPDATE_PUBLIC_KEY:-}" ]]; then
    : "${UPDATE_FEED_URL:?Set both UPDATE_FEED_URL and UPDATE_PUBLIC_KEY}"
    : "${UPDATE_PUBLIC_KEY:?Set both UPDATE_FEED_URL and UPDATE_PUBLIC_KEY}"
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $UPDATE_FEED_URL" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $UPDATE_PUBLIC_KEY" "$APP/Contents/Info.plist"
fi
IDENTITY="${SIGNING_IDENTITY:--}"
SIGN_ARGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != - ]]; then SIGN_ARGS+=(--options runtime --timestamp); fi
# Sign nested Mach-O files and bundles inside-out, including Codex and Sparkle helpers.
while IFS= read -r -d '' executable; do
    # Signing the main executable signs its enclosing app before the helpers are ready.
    if [[ "$executable" == "$APP/Contents/MacOS/SuWuDu" ]]; then continue; fi
    if file -b "$executable" | grep -q 'Mach-O'; then codesign "${SIGN_ARGS[@]}" "$executable"; fi
done < <(find "$APP/Contents" -type f -print0)
while IFS= read -r -d '' bundle; do
    codesign "${SIGN_ARGS[@]}" "$bundle"
done < <(find "$APP/Contents" -depth -type d \( -name '*.xpc' -o -name '*.app' -o -name '*.framework' \) -print0)
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    if [[ "$IDENTITY" == - ]]; then echo "Notarization requires SIGNING_IDENTITY (Developer ID Application)." >&2; exit 1; fi
    ZIP="$MAC_ROOT/output/$ARCH/SuWuDu-notarize.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
fi
if [[ "$MAKE_DMG" == 1 ]]; then
    STAGING="$(mktemp -d "$MAC_ROOT/output/$ARCH/dmg.XXXXXX")"
    trap 'rm -rf "$STAGING"' EXIT
    ditto "$APP" "$STAGING/SuWuDu.app"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "SuWuDu" -srcfolder "$STAGING" -ov -format UDZO "$MAC_ROOT/output/$ARCH/SuWuDu-macOS-$ARCH.dmg"
fi
echo "Built: $APP"
echo "Launch: open \"$APP\""
