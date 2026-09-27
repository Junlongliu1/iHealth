#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="${BUILD_DIR:-$ROOT/build}"
PROJECT="$ROOT/iMusic.xcodeproj"
BUILD_VARIANT="${WALLET_BUILD_BUNDLE_VARIANT:-legacy}"
APP_NAME="iMusic"
MARKETING_VERSION="${WALLET_MARKETING_VERSION:-}"
CURRENT_PROJECT_VERSION="${WALLET_BUILD_NUMBER:-}"
DERIVED_DATA="$BUILD/DerivedData-iOS"
STAGING="$BUILD/IPA"
if [[ -n "$MARKETING_VERSION" ]]; then
  IPA_PATH="$BUILD/iMusic-iOS-unsigned-${MARKETING_VERSION}.ipa"
else
  IPA_PATH="$BUILD/iMusic-iOS-unsigned.ipa"
fi

# ✅ 新增：定义原始 Bundle ID 前缀，用于动态构建替换规则
ORIGINAL_BUNDLE_PREFIX="com.evron.iMusic"
LEGACY_BUNDLE_PREFIX="com.legacy.iMusic"

rm -rf "$DERIVED_DATA" "$STAGING"
rm -f "$IPA_PATH"
mkdir -p "$BUILD"

# ✅ 初始化构建参数数组（替代临时项目复制）
BUILD_SETTINGS=()
EXPECTED_APP_BUNDLE_ID=""

case "$BUILD_VARIANT" in
  legacy)
    EXPECTED_APP_BUNDLE_ID="$LEGACY_BUNDLE_PREFIX"
    # ✅ 核心：通过命令行直接注入所有 Bundle ID 和 Team ID
    # PRODUCT_BUNDLE_IDENTIFIER 会同时作用于主 App 及其所有 Extension
    BUILD_SETTINGS+=(
      "PRODUCT_BUNDLE_IDENTIFIER=$LEGACY_BUNDLE_PREFIX"
      "DEVELOPMENT_TEAM=LEGACY_TEAM_ID"
    )
    echo "🔧 Legacy 模式：Bundle ID 将通过命令行覆盖为 $LEGACY_BUNDLE_PREFIX"
    ;;
  *)
    EXPECTED_APP_BUNDLE_ID="$ORIGINAL_BUNDLE_PREFIX"
    ;;
esac

echo "========== 构建 iOS Release（${BUILD_VARIANT}）=========="

VERSION_ARGS=()
if [[ -n "$MARKETING_VERSION" ]]; then
  VERSION_ARGS+=(MARKETING_VERSION="$MARKETING_VERSION")
fi
if [[ -n "$CURRENT_PROJECT_VERSION" ]]; then
  VERSION_ARGS+=(CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION")
fi

# ✅ 关键改进：
# 1. 恢复 -derivedDataPath（保证构建隔离）
# 2. 移除 -target，改用 -scheme（满足 Xcode 参数约束）
# 3. 移除 -destination（避免与 -sdk 冲突）
# 4. 通过 BUILD_SETTINGS 数组注入 Bundle ID，无需修改任何项目文件
xcodebuild build \
  -project "$PROJECT" \
  -scheme "iMusic" \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$DERIVED_DATA" \
  REGISTER_APP_GROUPS=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  PROVISIONING_PROFILE="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  "${BUILD_SETTINGS[@]}" \
  "${VERSION_ARGS[@]}"

# ✅ 安全查找：限定在当前构建的 DerivedData 内搜索
APP_PATH="$(find "$DERIVED_DATA/Build/Products/Release-iphoneos" -maxdepth 1 -name "$APP_NAME.app" -type d -print -quit)"

if [[ -z "$APP_PATH" ]]; then
  echo "❌ 找不到 iOS 构建产物：$APP_NAME.app"
  echo "   已搜索路径：$DERIVED_DATA/Build/Products/Release-iphoneos"
  exit 1
fi

assert_bundle_identifier() {
  local bundle_path="$1"
  local expected_bundle_id="$2"
  local product_name="$3"
  local actual_bundle_id

  if [[ ! -f "$bundle_path/Info.plist" ]]; then
    echo "❌ 找不到 $product_name 的 Info.plist：$bundle_path"
    exit 1
  fi

  actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle_path/Info.plist")"
  if [[ "$actual_bundle_id" != "$expected_bundle_id" ]]; then
    echo "❌ $product_name Bundle ID 不符合 $BUILD_VARIANT 构建要求"
    echo "   期望：$expected_bundle_id"
    echo "   实际：$actual_bundle_id"
    exit 1
  fi
  echo "✅ Bundle ID 校验通过：$actual_bundle_id"
}

assert_bundle_identifier "$APP_PATH" "$EXPECTED_APP_BUNDLE_ID" "Wallet"

echo "========== 生成未签名 IPA =========="
mkdir -p "$STAGING/Payload"
ditto --norsrc "$APP_PATH" "$STAGING/Payload/$APP_NAME.app"
ditto -c -k --norsrc --keepParent "$STAGING/Payload" "$IPA_PATH"

if [[ ! -f "$IPA_PATH" ]]; then
  echo "❌ 生成未签名 IPA 失败"
  exit 1
fi

unzip -tq "$IPA_PATH"
ls -lh "$IPA_PATH"
echo "✅ 已生成：$IPA_PATH"