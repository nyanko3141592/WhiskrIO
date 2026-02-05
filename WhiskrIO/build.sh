#!/bin/bash

# WhiskrIO Build Script

set -e

echo "🐱 Building WhiskrIO..."

# Kill existing process if running
if pgrep -x "WhiskrIO" > /dev/null; then
    echo "🛑 Stopping existing WhiskrIO process..."
    pkill -x "WhiskrIO"
    sleep 1
fi

# Remove existing app if present
if [ -d "WhiskrIO.app" ]; then
    echo "🗑️  Removing existing WhiskrIO.app..."
    rm -rf WhiskrIO.app
fi

# Clean build
swift package clean

# Build debug version
echo "📦 Building debug version..."
swift build

# Build release version
echo "📦 Building release version..."
swift build -c release

# Create .app bundle
echo "📁 Creating .app bundle..."
mkdir -p WhiskrIO.app/Contents/{MacOS,Resources}

# Copy binary
echo "📋 Copying binary..."
cp .build/arm64-apple-macosx/release/WhiskrIO WhiskrIO.app/Contents/MacOS/ 2>/dev/null || \
cp .build/arm64-apple-macosx/debug/WhiskrIO WhiskrIO.app/Contents/MacOS/

# Copy icon
echo "🎨 Copying app icon..."
cp Resources/AppIcon.icns WhiskrIO.app/Contents/Resources/

# Copy cat sounds (if available)
if [ -d "Resources/Sounds" ] && [ "$(ls -A Resources/Sounds 2>/dev/null)" ]; then
    echo "🔊 Copying cat sounds..."
    mkdir -p WhiskrIO.app/Contents/Resources/Sounds
    cp Resources/Sounds/*.m4a WhiskrIO.app/Contents/Resources/Sounds/ 2>/dev/null || true
fi

# Create Info.plist
echo "📝 Creating Info.plist..."
cat > WhiskrIO.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>WhiskrIO</string>
    <key>CFBundleIdentifier</key>
    <string>io.whiskr.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>WhiskrIO</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>音声入力のため、マイクへのアクセスが必要です。</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>テキスト入力のため、アクセシビリティ機能が必要です。</string>
</dict>
</plist>
EOF

# Sign the app
echo "🔏 Signing app..."
codesign --force --deep --sign - WhiskrIO.app

# Make executable
chmod +x WhiskrIO.app/Contents/MacOS/WhiskrIO

echo ""
echo "✅ Build complete!"
echo ""
echo "📍 Location: $(pwd)/WhiskrIO.app"
echo ""
echo "To install:"
echo "  cp -r WhiskrIO.app /Applications/"
echo ""
echo "To run:"
echo "  open WhiskrIO.app"
echo ""
