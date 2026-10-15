#!/bin/bash
# Native focus tests need an unlocked macOS GUI session; no user app/data is accessed.
set -euo pipefail
cd "$(dirname "$0")/.."
MAC_ROOT="$(pwd -P)"
SDK_PATH="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
MODES=(close perform-close minimize perform-minimize)
for arg in "$@"; do
    case "$arg" in
        --sdk=*) SDK_PATH="${arg#--sdk=}" ;;
        --mode=close|--mode=perform-close|--mode=minimize|--mode=perform-minimize) MODES=("${arg#--mode=}") ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/suwudu-page-windows.XXXXXX")"
PROBE_PID=""
cleanup() {
    if [[ -n "$PROBE_PID" ]]; then
        kill "$PROBE_PID" 2>/dev/null || true
        wait "$PROBE_PID" 2>/dev/null || true
    fi
    rm -rf "$TEST_TMP"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
SWIFT_ARGS=(-parse-as-library -target "$(uname -m)-apple-macosx14.0" -sdk "$SDK_PATH"
            -module-cache-path "${SWIFT_MODULECACHE_PATH:-$TEST_TMP/module-cache}")
xcrun swiftc "${SWIFT_ARGS[@]}" "$MAC_ROOT/Tests/WindowLifecycle/ForegroundCover.swift" -o "$TEST_TMP/Cover"
xcrun swiftc "${SWIFT_ARGS[@]}" "$MAC_ROOT/Tests/WindowLifecycle/PageWindowProbe.swift" \
    "$MAC_ROOT/Sources/SuWuDu/AppPageWindow.swift" -o "$TEST_TMP/Probe"
for mode in "${MODES[@]}"; do
    "$TEST_TMP/Probe" "$mode" "$TEST_TMP/Cover" "$TEST_TMP/$mode.ready" &
    PROBE_PID=$!
    wait "$PROBE_PID"
    PROBE_PID=""
    # Let LaunchServices finish unregistering the previous pair of synthetic apps.
    sleep 1
done
