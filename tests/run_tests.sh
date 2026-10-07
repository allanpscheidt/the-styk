#!/bin/bash
# Teste funcional do NoteStore (lixeira, migração, órfãs) em armazenamento isolado.
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d /tmp/thestyk-test-home.XXXX)
trap 'rm -rf "$T"' EXIT
SUITE="thestyk-test-store-$(uuidgen)"
export THESTYK_DEFAULTS_SUITE="$SUITE"
mkdir -p "$T/build"
cp tests/test_store_main.swift "$T/build/main.swift"
swiftc -swift-version 5 \
    Sources/Models.swift Sources/PasswordService.swift Sources/NoteStore.swift Sources/L10n*.swift "$T/build/main.swift" -o "$T/build/run"
THESTYK_DATA_DIR="$T/data" THESTYK_TEST_ROOT="$T" "$T/build/run"
