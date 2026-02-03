#!/bin/bash

# Gemisper Build Script

set -e

echo "🔨 Building Gemisper..."

# Kill existing Gemisper process if running
if pgrep -x "Gemisper" > /dev/null; then
    echo "🛑 Stopping existing Gemisper process..."
    pkill -x "Gemisper"
    sleep 1
fi

# Remove existing app if present
if [ -d "Gemisper.app" ]; then
    echo "🗑️  Removing existing Gemisper.app..."
    rm -rf Gemisper.app
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
mkdir -p Gemisper.app/Contents/{MacOS,Resources}

# Copy binary
echo "📋 Copying binary..."
cp .build/arm64-apple-macosx/release/Gemisper Gemisper.app/Contents/MacOS/ 2>/dev/null || \
cp .build/arm64-apple-macosx/debug/Gemisper Gemisper.app/Contents/MacOS/

# Create Info.plist
echo "📝 Creating Info.plist..."
cat > Gemisper.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Gemisper</string>
    <key>CFBundleIdentifier</key>
    <string>com.gemisper.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Gemisper</string>
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
codesign --force --deep --sign - Gemisper.app

# Make executable
chmod +x Gemisper.app/Contents/MacOS/Gemisper

echo ""
echo "✅ Build complete!"
echo ""
echo "📍 Location: $(pwd)/Gemisper.app"
echo ""
echo "To install:"
echo "  cp -r Gemisper.app /Applications/"
echo ""
echo "To run:"
echo "  open Gemisper.app"
echo ""
