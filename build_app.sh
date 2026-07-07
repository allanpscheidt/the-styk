#!/bin/bash
# Compila, empacota em DMG e ZIP, assina (ad-hoc) e instala o StickIE.
set -euo pipefail
cd "$(dirname "$0")"

APP="The Styk"
BUILD=build
BUNDLE="$BUILD/$APP.app"
LEGACY="$BUILD/$APP-Intel.app"

# Limpa build anterior
rm -rf "$BUILD"/*.dmg "$BUILD"/*.zip
rm -rf "$BUNDLE" "$LEGACY"
mkdir -p "$BUILD"

echo "→ compilando ($(ls Sources/*.swift | wc -l | tr -d ' ') arquivos)…"

# 1. Gerar ícones e recursos compartilhados
echo "→ gerando ícone…"
mkdir -p "$BUILD/AppIcon.iconset"
swiftc -O -o "$BUILD/make_icon" tools/make_icon.swift
"$BUILD/make_icon" "$BUILD/AppIcon.iconset" > /dev/null
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"

# 2. Compilar e empacotar versão Apple Silicon (arm64, macOS 11.0+)
echo "→ compilando versão Apple Silicon (arm64, macOS 11.0+)…"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
swiftc -swift-version 5 -target arm64-apple-macos11.0 -O \
    Sources/*.swift -o "$BUNDLE/Contents/MacOS/$APP"

cp Info.plist "$BUNDLE/Contents/Info.plist"
cp "$BUILD/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
cp "$BUILD/AppIcon.iconset/StatusBarIcon.png" "$BUNDLE/Contents/Resources/StatusBarIcon.png"
cp "$BUILD/AppIcon.iconset/StatusBarIcon@2x.png" "$BUNDLE/Contents/Resources/StatusBarIcon@2x.png"
cp -R Localization/*.lproj "$BUNDLE/Contents/Resources/"

echo "→ assinando Apple Silicon (ad-hoc, hardened runtime)…"
codesign --force --sign - --options runtime --entitlements StickIE.entitlements "$BUNDLE"

# Copiar para Applications para uso local
echo "→ instalando em /Applications…"
pkill -x "$APP" 2>/dev/null || true
rm -rf "/Applications/$APP.app"
cp -R "$BUNDLE" "/Applications/$APP.app"

# Criar ZIP da Silicon
ditto -c -k --keepParent "$BUNDLE" "$BUILD/$APP-Silicon.zip"

# Criar DMG da Silicon
echo "→ criando DMG Apple Silicon…"
TEMP_DMG_SILICON="$BUILD/temp_dmg_silicon"
rm -rf "$TEMP_DMG_SILICON"
mkdir -p "$TEMP_DMG_SILICON"
cp -R "$BUNDLE" "$TEMP_DMG_SILICON/"
ln -s /Applications "$TEMP_DMG_SILICON/Applications"
hdiutil create -volname "The Styk (Apple Silicon)" -srcfolder "$TEMP_DMG_SILICON" -ov -format UDZO "$BUILD/The Styk-Silicon.dmg"
rm -rf "$TEMP_DMG_SILICON"

# 3. Compilar e empacotar versão Intel (x86_64, macOS 10.15+)
echo "→ compilando versão Intel (x86_64, macOS 10.15+)…"
mkdir -p "$LEGACY/Contents/MacOS" "$LEGACY/Contents/Resources"
swiftc -swift-version 5 -target x86_64-apple-macos10.15 -O \
    Sources/*.swift -o "$LEGACY/Contents/MacOS/$APP"

sed 's|<string>11.0</string>|<string>10.15</string>|' Info.plist > "$LEGACY/Contents/Info.plist"
cp "$BUILD/AppIcon.icns" "$LEGACY/Contents/Resources/AppIcon.icns"
cp "$BUILD/AppIcon.iconset/StatusBarIcon.png" "$LEGACY/Contents/Resources/StatusBarIcon.png"
cp "$BUILD/AppIcon.iconset/StatusBarIcon@2x.png" "$LEGACY/Contents/Resources/StatusBarIcon@2x.png"
cp -R Localization/*.lproj "$LEGACY/Contents/Resources/"

echo "→ assinando versão Intel (ad-hoc, hardened runtime)…"
codesign --force --sign - --options runtime --entitlements StickIE.entitlements "$LEGACY"

# Criar ZIP da Intel
ditto -c -k --keepParent "$LEGACY" "$BUILD/$APP-Intel.zip"

# Criar DMG da Intel
echo "→ criando DMG Intel…"
TEMP_DMG_INTEL="$BUILD/temp_dmg_intel"
rm -rf "$TEMP_DMG_INTEL"
mkdir -p "$TEMP_DMG_INTEL"
cp -R "$LEGACY" "$TEMP_DMG_INTEL/"
ln -s /Applications "$TEMP_DMG_INTEL/Applications"
hdiutil create -volname "The Styk (Intel)" -srcfolder "$TEMP_DMG_INTEL" -ov -format UDZO "$BUILD/The Styk-Intel.dmg"
rm -rf "$TEMP_DMG_INTEL"

echo "✓ Pronto!"
echo "✓ Apple Silicon DMG: $BUILD/The Styk-Silicon.dmg (macOS 11.0+)"
echo "✓ Apple Intel DMG: $BUILD/The Styk-Intel.dmg (macOS 10.15+)"
