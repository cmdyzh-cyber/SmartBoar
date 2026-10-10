#!/bin/bash
set -euo pipefail
export LC_ALL=C
export COPYFILE_DISABLE=1
project="$(cd "$(dirname "$0")" && pwd)"
build="$project/build"
release="${1:-$project/release}"
mkdir -p "$build" "$release"
root="$build/payload"
[ ! -e "$root" ] || rm -rf "$root"
lib="$root/Library/Printers/LegacyPrint/Core"
app="$root/Applications/聪明的野猪.app"
driver="$lib/Drivers/hp108a-splix-fixed"
mkdir -p "$driver" "$lib/licenses" "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun clang -arch arm64 -mmacosx-version-min=14.0 -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations "$project/src/usb.c" -framework IOKit -framework CoreFoundation -o "$lib/legacyprint-usb"
xcrun clang -arch arm64 -mmacosx-version-min=14.0 -O2 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-deprecated-declarations "$project/src/Control.m" -framework Foundation -o "$lib/legacyprintctl"
xcrun clang -arch arm64 -mmacosx-version-min=14.0 -O2 -fobjc-arc -fblocks -Wall -Wextra -Werror "$project/src/App.m" -framework AppKit -o "$app/Contents/MacOS/LegacyPrint"
cp "$project/vendor/rastertoqpdl" "$driver/rastertoqpdl"
cp "$project/resources/HP108a.ppd" "$driver/HP108a.ppd"
cp "$project/resources/test-page.txt" "$lib/test-page.txt"
cp "$project/vendor/COPYING-SpliX.txt" "$project/vendor/SpliX-fixed-source.tar.gz" "$project/THIRD_PARTY.txt" "$project/LICENSE" "$lib/licenses/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LegacyPrint</string>
<key>CFBundleIdentifier</key><string>org.legacyprint.app</string>
<key>CFBundleName</key><string>聪明的野猪</string>
<key>CFBundleDisplayName</key><string>聪明的野猪</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>LegacyPrint contributors</string>
</dict></plist>
PLIST
/usr/bin/cupstestppd -q -I filters "$driver/HP108a.ppd"
chmod -R go-w "$root"
chmod 755 "$driver/rastertoqpdl" "$lib/legacyprintctl" "$lib/legacyprint-usb" "$app/Contents/MacOS/LegacyPrint"
for executable in "$driver/rastertoqpdl" "$lib/legacyprintctl" "$lib/legacyprint-usb"; do /usr/bin/codesign --force --sign - "$executable"; done
/usr/bin/codesign --force --sign - "$app"
# Asset hashes are computed after code signing, which changes executable bytes.
python3 "$project/scripts/build_catalog.py" "$project/resources/catalog.json" "$lib"
/usr/bin/xattr -cr "$root"
/usr/bin/pkgbuild --root "$root" --component-plist "$project/resources/components.plist" --scripts "$build/package-scripts" --identifier org.legacyprint.core --version 0.2.0 --install-location / --ownership recommended "$build/LegacyPrint-component.pkg"
/usr/bin/productbuild --distribution "$project/resources/distribution.xml" --resources "$project/resources" --package-path "$build" "$release/SmartBoar-0.2.0-arm64-unsigned.pkg"
/usr/bin/codesign --verify --strict "$app"
printf 'Built SmartBoar 0.2.0 unsigned prototype.\n'
