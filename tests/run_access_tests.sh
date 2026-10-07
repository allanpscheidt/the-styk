#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_root=$(mktemp -d "$PWD/thestyk-access-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/build" "$test_root/temp"
cp tests/test_access_main.swift "$test_root/build/main.swift"
swiftc -swift-version 5 Sources/Models.swift Sources/PasswordService.swift \
  Sources/L10n*.swift Sources/SafeFolderAccess.swift Sources/TemporaryExports.swift Sources/ExportService.swift \
  "$test_root/build/main.swift" -o "$test_root/build/run"
THESTYK_DEFAULTS_SUITE="thestyk-test-access-$(uuidgen)" THESTYK_EXPORT_TEMP_DIR="$test_root/temp" "$test_root/build/run"
