#!/usr/bin/env bash
#
# build-ipa-sideload.sh —— 打包「自签精简版」IPA
#
# 为什么需要单独的脚本：
#   免费 Apple ID（个人团队）不支持 App Groups / iCloud 这两个 entitlement，
#   也不方便给内嵌的 app extension 单独申请描述文件。
#   所以自签版会：
#     · 不带任何 entitlements（去掉 App Groups / iCloud）
#     · 移除 PlugIns 里的分享扩展和小组件
#   结果是：主 App 的所有功能都能用（双击背面 / 拍照识别 / 相册导入 /
#   语音 / 手动记账 / 图表月报 / 导入导出），只有「从别的 App 分享截图过来」
#   和「桌面小组件」这两项不可用 —— 因为它们在系统层面依赖 App Group。
#
# 用法：
#   ./tools/build-ipa-sideload.sh
#   产物：build/轻点记账-sideload.ipa
#
set -euo pipefail

PROJECT_NAME="QingDianJiZhang"
SCHEME="${SCHEME:-QingDianJiZhang}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="build"
ARCHIVE_PATH="${BUILD_DIR}/${PROJECT_NAME}-sideload.xcarchive"

cd "$(dirname "$0")/.."
echo "==> 工程目录: $(pwd)"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "!! 找不到 xcodebuild。这个脚本必须在 macOS 上运行。"
  exit 1
fi

rm -rf "$ARCHIVE_PATH"
mkdir -p "$BUILD_DIR"

echo "==> 归档（无签名、无 entitlements）"
xcodebuild \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_ENTITLEMENTS="" \
  archive

APP_PATH="${ARCHIVE_PATH}/Products/Applications/${PROJECT_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "!! 没找到构建产物：$APP_PATH"
  exit 1
fi

# IPA 规范要求压缩包里必须有一个「名字就叫 Payload」的目录。
# 所以在 staging 目录里造 Payload/，再 cd 进 staging 打包，
# 保证 zip 里第一条路径是 Payload/，不是 Payload-sideload/。
STAGE="${BUILD_DIR}/sideload-stage"
rm -rf "$STAGE"
mkdir -p "${STAGE}/Payload"
cp -R "$APP_PATH" "${STAGE}/Payload/"

APP_IN_STAGE="${STAGE}/Payload/${PROJECT_NAME}.app"

echo "==> 移除内嵌扩展（自签环境不支持带 entitlements 的 appex）"
rm -rf "${APP_IN_STAGE}/PlugIns"

echo "==> 清理旧签名残留"
rm -rf "${APP_IN_STAGE}/_CodeSignature"
rm -f  "${APP_IN_STAGE}/embedded.mobileprovision"

echo "==> 打包"
rm -f "${BUILD_DIR}/轻点记账-sideload.ipa"
(cd "$STAGE" && zip -qry "${BUILD_DIR}/轻点记账-sideload.ipa" Payload)

echo "==> 校验包结构"
FIRST_ENTRY="$(unzip -Z1 "${BUILD_DIR}/轻点记账-sideload.ipa" | head -1)"
echo "    首条路径: ${FIRST_ENTRY}"
if [ "${FIRST_ENTRY#Payload/}" = "${FIRST_ENTRY}" ]; then
  echo "!! 包结构不对：顶层目录必须是 Payload/，实际是 ${FIRST_ENTRY}"
  exit 1
fi
if ! unzip -Z1 "${BUILD_DIR}/轻点记账-sideload.ipa" | grep -q "^Payload/${PROJECT_NAME}.app/Info.plist$"; then
  echo "!! 包结构不对：缺少 Payload/${PROJECT_NAME}.app/Info.plist"
  exit 1
fi
echo "    结构 OK"

echo "==> 完成：${BUILD_DIR}/轻点记账-sideload.ipa"
echo ""
echo "下一步（任选一种自签工具）："
echo "  1. Sideloadly   https://sideloadly.io      —— Windows / macOS 都能用，最省事"
echo "  2. AltStore     https://altstore.io        —— 手机上自签，7 天续签一次"
echo "  3. ESign / 轻松签                          —— 手机上直接签，需自备证书"
echo "  4. TrollStore（仅特定 iOS 版本）           —— 永久签名"
echo ""
echo "注意：免费 Apple ID 签出来的 App 有效期 7 天，到期需要重新签。"
