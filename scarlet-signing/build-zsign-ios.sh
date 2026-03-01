#!/bin/bash
set -e

# Build zsign-ios C++ sources into a static library for iOS arm64

ZSIGN_DIR="$(cd "$(dirname "$0")/../zsign-ios/Sources/ZSign" && pwd)"
OPENSSL_DIR="$(cd "$(dirname "$0")/../zsign-ios/Binaries/OpenSSL.xcframework/ios-arm64_armv7/OpenSSL.framework" && pwd)"
OUTPUT_DIR="$(cd "$(dirname "$0")/../Scarlet/libs" && pwd)"

echo "🔨 Building zsign for iOS arm64..."
echo "   Sources: $ZSIGN_DIR"
echo "   OpenSSL: $OPENSSL_DIR"

# iOS SDK
SDKROOT=$(xcrun --sdk iphoneos --show-sdk-path)
CXX=$(xcrun --sdk iphoneos -f clang++)
AR=$(xcrun --sdk iphoneos -f ar)

CXXFLAGS="-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=15.0 \
  -std=c++14 -O2 -DNDEBUG \
  -I$ZSIGN_DIR \
  -I$ZSIGN_DIR/common \
  -I$OPENSSL_DIR/Headers \
  -F$(dirname $OPENSSL_DIR)"

# Compile each C++ source
SOURCES=(
  "$ZSIGN_DIR/archo.cpp"
  "$ZSIGN_DIR/bundle.cpp"
  "$ZSIGN_DIR/macho.cpp"
  "$ZSIGN_DIR/openssl.cpp"
  "$ZSIGN_DIR/signing.cpp"
  "$ZSIGN_DIR/xzsign.cpp"
  "$ZSIGN_DIR/common/base64.cpp"
  "$ZSIGN_DIR/common/common.cpp"
  "$ZSIGN_DIR/common/json.cpp"
)

OBJS=()
TMPDIR=$(mktemp -d)

for src in "${SOURCES[@]}"; do
  name=$(basename "$src" .cpp)
  obj="$TMPDIR/$name.o"
  echo "   Compiling $name.cpp..."
  $CXX $CXXFLAGS -c "$src" -o "$obj"
  OBJS+=("$obj")
done

# Create static library
echo "   Creating libzsign.a..."
$AR rcs "$OUTPUT_DIR/libzsign.a" "${OBJS[@]}"

echo "✅ Built $OUTPUT_DIR/libzsign.a"
ls -lh "$OUTPUT_DIR/libzsign.a"

# Copy OpenSSL framework
echo "📦 Copying OpenSSL.framework..."
cp -R "$OPENSSL_DIR" "$OUTPUT_DIR/OpenSSL.framework"
echo "✅ OpenSSL.framework copied"

# Cleanup
rm -rf "$TMPDIR"
echo "🎉 Done!"
