#!/bin/bash
# Compila, empacota, assina (ad-hoc) e instala o StickIE em /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="The Styk"
BUILD=build
BUNDLE="$BUILD/$APP.app"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "→ compilando ($(ls Sources/*.swift | wc -l | tr -d ' ') arquivos)…"
swiftc -swift-version 5 -target arm64-apple-macos11.0 -O \
    Sources/*.swift -o "$BUNDLE/Contents/MacOS/$APP"

cp Info.plist "$BUNDLE/Contents/Info.plist"

# Ícone (gerado a partir de logo.png)
echo "→ gerando ícone…"
swiftc -O -o "$BUILD/make_icon" tools/make_icon.swift
"$BUILD/make_icon" "$BUILD/AppIcon.iconset" > /dev/null
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"
cp "$BUILD/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
cp "$BUILD/AppIcon.iconset/StatusBarIcon.png" "$BUNDLE/Contents/Resources/StatusBarIcon.png"
cp "$BUILD/AppIcon.iconset/StatusBarIcon@2x.png" "$BUNDLE/Contents/Resources/StatusBarIcon@2x.png"
cp -R Localization/*.lproj "$BUNDLE/Contents/Resources/"   # InfoPlist.strings (aviso do TCC por idioma)

echo "→ assinando (ad-hoc, hardened runtime + entitlement de Apple Events)…"
codesign --force --sign - --options runtime --entitlements StickIE.entitlements "$BUNDLE"

echo "→ instalando em /Applications…"
pkill -x "$APP" 2>/dev/null || true
rm -rf "/Applications/$APP.app"
cp -R "$BUNDLE" "/Applications/$APP.app"
ditto -c -k --keepParent "$BUNDLE" "$BUILD/$APP.zip"

# ─── Versão Intel legada (x86_64, macOS 10.13+ — Macs de 2010 em diante) ───
# Pausada até o aval: rode com BUILD_INTEL=1 para gerar.
if [ "${BUILD_INTEL:-0}" != "1" ]; then
    echo "→ versão Intel pulada (BUILD_INTEL=1 para gerar)"
    echo "✓ pronto: /Applications/$APP.app  (abra com: open -a $APP)"
    exit 0
fi
LEGACY="$BUILD/$APP-Intel.app"
rm -rf "$LEGACY"
mkdir -p "$LEGACY/Contents/MacOS" "$LEGACY/Contents/Resources"

echo "→ compilando versão Intel (x86_64, macOS 10.13+)…"
swiftc -swift-version 5 -target x86_64-apple-macos10.13 -O \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    Sources/*.swift -o "$LEGACY/Contents/MacOS/$APP"

# Runtime Swift embarcado: macOS < 10.14.4 não traz o Swift no sistema.
# swift-stdlib-tool copia só as dylibs que o binário realmente usa.
echo "→ embarcando runtime Swift (back-deploy)…"
xcrun swift-stdlib-tool --copy \
    --scan-executable "$LEGACY/Contents/MacOS/$APP" \
    --platform macosx \
    --destination "$LEGACY/Contents/Frameworks" > /dev/null

sed 's|<string>11.0</string>|<string>10.13</string>|' Info.plist > "$LEGACY/Contents/Info.plist"
cp "$BUILD/AppIcon.icns" "$LEGACY/Contents/Resources/AppIcon.icns"

# Ad-hoc sem hardened runtime: library validation rejeitaria dylibs ad-hoc embarcadas.
echo "→ assinando versão Intel (ad-hoc)…"
codesign --force --sign - "$LEGACY/Contents/Frameworks/"*.dylib
codesign --force --sign - "$LEGACY"
ditto -c -k --keepParent "$LEGACY" "$BUILD/$APP-Intel.zip"

echo "✓ pronto: /Applications/$APP.app  (abra com: open -a $APP)"
echo "✓ distribuição: $BUILD/$APP.zip (Apple Silicon, macOS 11+)"
echo "✓ distribuição: $BUILD/$APP-Intel.zip (Intel, macOS 10.13+)"
