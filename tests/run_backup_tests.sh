#!/bin/bash
# Isolated corruption, ZIP resource-limit, atomic-commit and real backup tests.
set -euo pipefail
cd "$(dirname "$0")/.."
# A real workspace path avoids macOS /tmp symlinks in folder-anchor validation.
TEST_ROOT=$(mktemp -d "$PWD/thestyk-backup-tests-XXXXXX")
TEST_SUITE="thestyk.backup-tests.$(basename "$TEST_ROOT")"
trap 'rm -rf "$TEST_ROOT"; defaults delete "$TEST_SUITE" >/dev/null 2>&1 || true' EXIT
mkdir -p "$TEST_ROOT/build"
cp tests/test_backup_main.swift "$TEST_ROOT/build/main.swift"
swiftc -swift-version 5 \
    Sources/Models.swift Sources/PasswordService.swift Sources/L10n*.swift \
    Sources/SafeFolderAccess.swift Sources/NoteStore.swift Sources/BackupService.swift \
    Sources/BackupArchive.swift Sources/BackupRestoreTransaction.swift \
    "$TEST_ROOT/build/main.swift" -o "$TEST_ROOT/build/run"
THESTYK_DATA_DIR="$TEST_ROOT/data" THESTYK_TEST_ROOT="$TEST_ROOT" \
    THESTYK_DEFAULTS_SUITE="$TEST_SUITE" "$TEST_ROOT/build/run"
