#!/usr/bin/env bash
#
# build-ipa.sh —— 在 macOS 上打包「完整版」IPA（含分享扩展 + 小组件）
#
# 需要：macOS + Xcode 16 或更高（命令行工具 xcode-select 指向 Xcode）
#
# 用法：
#   ./tools/build-ipa.sh            # 生成未签名 IPA（用于重签 / 自签）
#   SIGN=1 TEAM_ID=XXXXXXXXXX ./tools/build-ipa.sh   # 生成已签名 IPA（development 分发）
#
set -euo pipefail

PROJECT_NAME="QingDianJiZhang"
SCHEME="${SCHEME:-QingDianJiZhang}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="build"
ARCHIVE_PATH="${BUILD_DIR}/${PROJECT_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
SIGN="${SIGN:-0}"

cd "$(dirname "$0")/.."
echo "==> 工程目录: $(pwd)"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "!! 找不到 xcodebuild。这个脚本必须在 macOS 上运行。"
  exit 1
fi

rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR"

if [[ "$SIGN" == "1" ]]; then
  : "${TEAM_ID:?请设置 TEAM_ID 环境变量，例如 TEAM_ID=AB12CD34EF}"
  echo "==> 归档（已签名，自动管理证书）"
  xcodebuild \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    archive

  cat > "${BUILD_DIR}/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>development</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>compileBitcode</key>
  <false/>
</dict>
</plist>
PLIST

  echo "==> 导出已签名 IPA"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist" \
    -allowProvisioningUpdates

  echo "==> 完成：$(ls -1 "$EXPORT_DIR"/*.ipa)"
  exit 0
fi

echo "==> 归档（不签名）"
xcodebuild \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  archive

APP_PATH="${ARCHIVE_PATH}/Products/Applications/${PROJECT_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "!! 没找到构建产物：$APP_PATH"
  exit 1
fi

echo "==> 打包未签名 IPA"
PAYLOAD="${BUILD_DIR}/Payload"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"
cp -R "$APP_PATH" "$PAYLOAD/"
(cd "$BUILD_DIR" && zip -qry "简记-unsigned.ipa" Payload)

echo "==> 完成：${BUILD_DIR}/简记-unsigned.ipa"
echo "    下一步：用 Sideloadly / AltStore / ESign 导入这个 IPA，用自己的 Apple ID 签名。"
