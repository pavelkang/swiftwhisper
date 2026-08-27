#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD_ROOT="$PROJECT_ROOT/.build/manual-app"
MODULES_DIR="$BUILD_ROOT/Modules"
APP_BUNDLE="$BUILD_ROOT/SwiftWhisper.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MODULES_DIR" "$MACOS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR"

swiftc \
  -emit-library \
  -emit-module \
  -parse-as-library \
  -module-name SwiftWhisperCore \
  "$PROJECT_ROOT"/Sources/SwiftWhisperCore/*.swift \
  -emit-module-path "$MODULES_DIR/SwiftWhisperCore.swiftmodule" \
  -o "$FRAMEWORKS_DIR/libSwiftWhisperCore.dylib" \
  -Xlinker -install_name \
  -Xlinker @rpath/libSwiftWhisperCore.dylib \
  -strict-concurrency=complete \
  -warn-concurrency \
  -swift-version 6

swiftc \
  -emit-library \
  -emit-module \
  -parse-as-library \
  -module-name SwiftWhisperPlatform \
  -I "$MODULES_DIR" \
  -L "$FRAMEWORKS_DIR" \
  -lSwiftWhisperCore \
  "$PROJECT_ROOT"/Sources/SwiftWhisperPlatform/*.swift \
  -emit-module-path "$MODULES_DIR/SwiftWhisperPlatform.swiftmodule" \
  -o "$FRAMEWORKS_DIR/libSwiftWhisperPlatform.dylib" \
  -Xlinker -install_name \
  -Xlinker @rpath/libSwiftWhisperPlatform.dylib \
  -framework AppKit \
  -framework ApplicationServices \
  -framework AVFoundation \
  -framework Speech \
  -strict-concurrency=complete \
  -warn-concurrency \
  -swift-version 6

swiftc \
  -parse-as-library \
  -I "$MODULES_DIR" \
  -L "$FRAMEWORKS_DIR" \
  -lSwiftWhisperCore \
  -lSwiftWhisperPlatform \
  "$PROJECT_ROOT"/Sources/SwiftWhisperApp/*.swift \
  -o "$MACOS_DIR/SwiftWhisperApp" \
  -Xlinker -rpath \
  -Xlinker @executable_path/../Frameworks \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  -strict-concurrency=complete \
  -warn-concurrency \
  -swift-version 6

cp "$PROJECT_ROOT/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

codesign --force --sign - "$FRAMEWORKS_DIR/libSwiftWhisperCore.dylib"
codesign --force --sign - "$FRAMEWORKS_DIR/libSwiftWhisperPlatform.dylib"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "$APP_BUNDLE"
