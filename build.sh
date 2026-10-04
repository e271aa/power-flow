#!/bin/bash
# Constrói PowerFlow.app a partir do executável do SwiftPM.
#
# Não é preciso o Xcode completo: as Command Line Tools chegam. O bundle é
# montado à mão porque o SwiftPM sozinho só produz um executável solto.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="PowerFlow"
BUNDLE="${APP_NAME}.app"
VERSION="1.0"

echo "==> A compilar (release)"
swift build -c release 2>&1 | grep -vE "xcrun:|could not determine XCTest|Source files for target" || true

BINARY=".build/release/${APP_NAME}"
[ -f "$BINARY" ] || { echo "Falhou: binário não encontrado"; exit 1; }

echo "==> A montar o bundle"
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "$BINARY" "${BUNDLE}/Contents/MacOS/${APP_NAME}"

# Textos PT-PT e EN: a única cópia está em Sources/PowerFlowCore/Resources.
# Na app lêem-se daqui; em `swift run` e nos testes, do bundle de recursos do SwiftPM.
cp -R Sources/PowerFlowCore/Resources/*.lproj "${BUNDLE}/Contents/Resources/"

cat > "${BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>pt-PT</string>
    <key>CFBundleLocalizations</key>
    <array><string>pt-PT</string><string>en</string></array>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>local.powerflow.${APP_NAME}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <!-- Só barra de menus: sem ícone no Dock e sem janela principal. -->
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> A assinar (ad-hoc)"
codesign --force --deep --sign - "$BUNDLE"
codesign --verify --verbose "$BUNDLE" 2>&1 | sed 's/^/    /'

echo "==> Auto-verificação"
"${BUNDLE}/Contents/MacOS/${APP_NAME}" --selftest | tail -1 | sed 's/^/    /'

if [ "${1:-}" = "--dmg" ]; then
    echo "==> A criar o DMG"
    DMG="${APP_NAME}-${VERSION}.dmg"
    STAGING="$(mktemp -d)"
    cp -R "$BUNDLE" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    rm -f "$DMG"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
        -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGING"
    echo "    ${DMG} ($(du -h "$DMG" | cut -f1))"
fi

echo "==> Pronto: ${BUNDLE}"
