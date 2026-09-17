#!/bin/zsh
# Baut WachModus für die Architektur dieses Macs, ab macOS 13.
set -euo pipefail
cd "$(dirname "$0")"

APP="WachModus.app"
BIN="build/WachModus"
mkdir -p build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
TARGET="$(uname -m)-apple-macosx13.0"

if [[ ! -f WachModus.icns || makeicon.swift -nt WachModus.icns ]]; then
    echo "> Erzeuge Icon ..."
    swiftc -O -target "$TARGET" -module-cache-path "$CLANG_MODULE_CACHE_PATH" makeicon.swift -o build/makeicon -framework AppKit
    ./build/makeicon WachModus.iconset
    iconutil -c icns WachModus.iconset -o WachModus.icns
fi

echo "> Kompiliere App ..."
swiftc -O -target "$TARGET" -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
    main.swift KeepAwake.swift Dashboard.swift SelfTest.swift -o "$BIN" \
    -framework AppKit -framework SwiftUI -framework IOKit -framework CoreGraphics

echo "> Prüfe Sitzungslogik ..."
"$BIN" --selftest

echo "> Baue App-Bundle ..."
STAGING="$(mktemp -d "$PWD/build/bundle.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
STAGED_APP="$STAGING/WachModus.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN" "$STAGED_APP/Contents/MacOS/WachModus"
cp Info.plist "$STAGED_APP/Contents/Info.plist"
cp WachModus.icns "$STAGED_APP/Contents/Resources/WachModus.icns"
plutil -lint "$STAGED_APP/Contents/Info.plist"
codesign --force --sign - "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
# Erst nach erfolgreicher Kompilierung, Tests und Signatur das alte Bundle ersetzen.
rm -rf "$APP"
mv "$STAGED_APP" "$APP"

echo ""
echo "Fertig!  ->  $(pwd)/$APP"
echo "Starten:  open \"$(pwd)/$APP\"    (oder im Finder doppelklicken)"
