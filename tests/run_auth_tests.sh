#!/bin/bash
# Authentication and store boundaries use a disposable store and preferences.
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d /tmp/thestyk-auth-test.XXXX)
SUITE="thestyk-test-auth-$(uuidgen)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/build"
cp tests/test_auth_main.swift "$T/build/main.swift"
swiftc -swift-version 5 \
    Sources/Models.swift Sources/PasswordService.swift Sources/NoteStore.swift Sources/L10n*.swift \
    "$T/build/main.swift" -o "$T/build/run"
THESTYK_DEFAULTS_SUITE="$SUITE" THESTYK_DATA_DIR="$T/data" THESTYK_TEST_ROOT="$T" "$T/build/run" initial
THESTYK_DEFAULTS_SUITE="$SUITE" THESTYK_DATA_DIR="$T/data" THESTYK_TEST_ROOT="$T" "$T/build/run" relaunch
