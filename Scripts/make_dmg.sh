#!/bin/bash
set -e

PROJ="/Users/c.kilicarsl/Documents/Projects/PkgLens"
BUILD="$PROJ/.build/release"
APP_NAME="PkgLens"
APP="$PROJ/$APP_NAME.app"
ICON_SRC="$PROJ/Sources/PkgLens/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
DMG_OUT="$PROJ/$APP_NAME-1.0.1.dmg"
VERSION="1.0.1"

echo "==> Cleaning previous app bundle..."
rm -rf "$APP" "$DMG_OUT" /tmp/PkgLens.iconset

# ── 1. Build AppIcon.icns ───────────────────────────────────────────────────
echo "==> Building AppIcon.icns..."
mkdir /tmp/PkgLens.iconset

for size in 16 32 128 256 512; do
    sips -z $size $size "$ICON_SRC" --out "/tmp/PkgLens.iconset/icon_${size}x${size}.png" > /dev/null
    double=$((size * 2))
    sips -z $double $double "$ICON_SRC" --out "/tmp/PkgLens.iconset/icon_${size}x${size}@2x.png" > /dev/null
done

iconutil --convert icns /tmp/PkgLens.iconset --output /tmp/AppIcon.icns
echo "   AppIcon.icns created."

# ── 2. Assemble .app bundle ─────────────────────────────────────────────────
echo "==> Assembling $APP_NAME.app..."
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BUILD/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"
cp /tmp/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM resource bundle — binary uses Bundle.module which looks for this
# in Contents/Resources at runtime; missing = immediate crash on launch.
if [ -d "$BUILD/${APP_NAME}_${APP_NAME}.bundle" ]; then
    echo "==> Copying resource bundle..."
    cp -R "$BUILD/${APP_NAME}_${APP_NAME}.bundle" "$APP/Contents/Resources/"
fi

# Compile Assets.xcassets → Assets.car
echo "==> Compiling assets..."
xcrun actool \
    "$PROJ/Sources/PkgLens/Assets.xcassets" \
    --compile "$APP/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist /tmp/actool_info.plist \
    2>&1 | grep -v "^$" || true

# ── 3. Info.plist ───────────────────────────────────────────────────────────
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.canberkki.pkglens</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>PkgLens</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Canberk Kılıçarslan. MIT License.</string>
</dict>
</plist>
PLIST

echo "==> App bundle ready: $APP"

# ── 4. Entitlements + ad-hoc sign ───────────────────────────────────────────
# Non-sandboxed entitlements: required for subprocess execution (brew, npm, pip…)
cat > /tmp/pkglens.entitlements <<ENTITLEMENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

echo "==> Ad-hoc signing with entitlements..."
codesign --force --deep --sign - \
    --entitlements /tmp/pkglens.entitlements \
    --options runtime \
    "$APP" 2>&1 || echo "   (codesign warning — continue)"

# ── 5. Create DMG ───────────────────────────────────────────────────────────
echo "==> Creating DMG..."

# Make a temp folder with the app + Applications alias
TMP_DMG_DIR=$(mktemp -d)
cp -R "$APP" "$TMP_DMG_DIR/"
ln -s /Applications "$TMP_DMG_DIR/Applications"

# Create writable image
hdiutil create \
    -volname "PkgLens $VERSION" \
    -srcfolder "$TMP_DMG_DIR" \
    -ov -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_OUT" 2>&1

rm -rf "$TMP_DMG_DIR"

echo ""
echo "✓ DMG ready: $DMG_OUT"
du -sh "$DMG_OUT"
