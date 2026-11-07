#!/usr/bin/env bash
# Builds the Rust core (rust/) for iPhone and the iOS Simulator and packages it
# as ios/fqapi_core/fqapi_core.xcframework, which the fqapi_core pod embeds.
#
# This is the iOS counterpart of scripts/build_rust_backend.sh. It never
# touches the Android jniLibs directory.
#
# Usage:
#   ./scripts/build_rust_ios.sh
#   ./scripts/build_rust_ios.sh --skip-codegen
#   ./scripts/build_rust_ios.sh --simulator-only
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
MANIFEST="$APP_DIR/rust/Cargo.toml"
OUT_DIR="$APP_DIR/ios/fqapi_core"
WORK_DIR="$OUT_DIR/build"
FRAMEWORK_NAME="fqapi_core"

SKIP_CODEGEN=0
SIMULATOR_ONLY=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-codegen) SKIP_CODEGEN=1 ;;
    --simulator-only) SIMULATOR_ONLY=1 ;;
    -h|--help)
      sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "错误：未知参数：$1" >&2; exit 2 ;;
  esac
  shift
done

if ! command -v cargo >/dev/null 2>&1; then
  echo "错误：未找到 cargo，请先安装 Rust 工具链。" >&2
  exit 1
fi
if [ ! -f "$MANIFEST" ]; then
  echo "错误：找不到 Rust 核心清单 $MANIFEST" >&2
  exit 1
fi

FRB_VERSION=2.13.0
if [ "$SKIP_CODEGEN" -eq 0 ]; then
  if ! command -v flutter_rust_bridge_codegen >/dev/null 2>&1; then
    echo "错误：未找到 flutter_rust_bridge_codegen（需要 $FRB_VERSION）。" >&2
    exit 1
  fi
  echo "==> 生成 flutter_rust_bridge 绑定..."
  ( cd "$APP_DIR" && flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml )
fi

REQUIRED_TARGETS=(aarch64-apple-ios-sim x86_64-apple-ios)
if [ "$SIMULATOR_ONLY" -eq 0 ]; then
  REQUIRED_TARGETS+=(aarch64-apple-ios)
fi
for target in "${REQUIRED_TARGETS[@]}"; do
  if ! rustup target list --installed | grep -qx "$target"; then
    echo "错误：未安装 Rust 目标 $target（rustup target add $target）。" >&2
    exit 1
  fi
done

build_slice() {
  local target="$1"
  local slice="$2"
  local platform="$3"
  echo "==> cargo build --target $target --release"
  ( cd "$APP_DIR" && cargo build --manifest-path "$MANIFEST" --target "$target" --release )

  local lib="$APP_DIR/rust/target/$target/release/lib${FRAMEWORK_NAME}.dylib"
  if [ ! -s "$lib" ]; then
    echo "错误：未产出 $lib" >&2
    exit 1
  fi
  local framework="$WORK_DIR/$slice/${FRAMEWORK_NAME}.framework"
  rm -rf "$framework"
  mkdir -p "$framework"
  cp "$lib" "$framework/$FRAMEWORK_NAME"
  install_name_tool -id "@rpath/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" \
    "$framework/$FRAMEWORK_NAME"

  cat > "$framework/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>${FRAMEWORK_NAME}</string>
	<key>CFBundleIdentifier</key><string>com.fqapp.fqapi-core</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>${FRAMEWORK_NAME}</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>0.1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>MinimumOSVersion</key><string>15.0</string>
	<key>CFBundleSupportedPlatforms</key><array><string>${platform}</string></array>
	<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
</dict>
</plist>
EOF
}

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
# The simulator slice is universal: Xcode's generic simulator destination
# builds arm64 and x86_64, and a single-arch framework makes CocoaPods skip the
# copy step (the linker then reports "framework not found").
build_slice aarch64-apple-ios-sim sim-arm64 iPhoneSimulator
build_slice x86_64-apple-ios sim-x86_64 iPhoneSimulator
SIM_FRAMEWORK="$WORK_DIR/sim/${FRAMEWORK_NAME}.framework"
rm -rf "$SIM_FRAMEWORK"
mkdir -p "$SIM_FRAMEWORK"
lipo -create   "$WORK_DIR/sim-arm64/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}"   "$WORK_DIR/sim-x86_64/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}"   -output "$SIM_FRAMEWORK/${FRAMEWORK_NAME}"
cp "$WORK_DIR/sim-arm64/${FRAMEWORK_NAME}.framework/Info.plist" "$SIM_FRAMEWORK/Info.plist"
install_name_tool -id "@rpath/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" \
  "$SIM_FRAMEWORK/${FRAMEWORK_NAME}"
SLICES=(-framework "$SIM_FRAMEWORK")
if [ "$SIMULATOR_ONLY" -eq 0 ]; then
  build_slice aarch64-apple-ios dev iPhoneOS
  SLICES+=(-framework "$WORK_DIR/dev/${FRAMEWORK_NAME}.framework")
fi

rm -rf "$OUT_DIR/fqapi_core.xcframework"
xcodebuild -create-xcframework "${SLICES[@]}" -output "$OUT_DIR/fqapi_core.xcframework"
echo "==> XCFramework: $OUT_DIR/fqapi_core.xcframework"
find "$OUT_DIR/fqapi_core.xcframework" -maxdepth 1 -mindepth 1 -type d -print
