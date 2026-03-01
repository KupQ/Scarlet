#!/bin/bash
# Build scarlet-signing for iOS (aarch64-apple-ios)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

TARGET="aarch64-apple-ios"
PROFILE="release"

echo "🔨 Building scarlet-signing for $TARGET..."
cargo build --target "$TARGET" --release

# Copy the static library to the Xcode project libs directory
LIBS_DIR="$SCRIPT_DIR/../Scarlet/Scarlet/libs"
mkdir -p "$LIBS_DIR"

SRC="$SCRIPT_DIR/target/$TARGET/$PROFILE/libscarlet_signing.a"
DST="$LIBS_DIR/libscarlet_signing.a"

cp "$SRC" "$DST"
echo "✅ Copied library to $DST"
echo "📦 Library size: $(du -h "$DST" | cut -f1)"
