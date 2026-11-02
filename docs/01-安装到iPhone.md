# 01 · 安装到真实 iPhone

三种方式，按你的账号情况选：

| 你有 | 推荐方式 | 有效期 | 能用的功能 |
|---|---|---|---|
| 只有免费 Apple ID | Xcode 真机调试 / 自签 IPA | 7 天（可续签） | 全部 App 功能；无分享扩展、无小组件 |
| 付费开发者账号（¥688/年） | TestFlight / Xcode 真机 | 90 天 / 1 年 | 全部功能 |
| 付费账号 + 想上架 | App Store | 永久 | 全部功能 |

---

## 方案一：Xcode 真机安装（最稳，推荐第一次用）

### 步骤

1. **Mac 上装 Xcode**（App Store 搜 Xcode，或 developer.apple.com 下载）。打开一次，同意协议，等它装完组件。
2. **iPhone 用数据线连 Mac**，手机上点「信任此电脑」。
3. **iPhone 打开开发者模式**：设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启手机。
4. **打开工程**：双击 `QingDianJiZhang.xcodeproj`。
5. **配签名**：
   - 左侧点项目图标 → TARGETS 选 `QingDianJiZhang` → `Signing & Capabilities`
   - 勾 `Automatically manage signing`
   - Team 选你的 Apple ID（没有就 `Add an Account`，用 Apple ID 登录，免费即可）
   - Bundle Identifier 改成 `com.你的名字.qingdianjizhang`
6. **同步改两个扩展的 Bundle ID**（如果保留了扩展）：
   - `QingDianJiZhangShare` → `com.你的名字.qingdianjizhang.share`
   - `QingDianJiZhangWidget` → `com.你的名字.qingdianjizhang.widget`
7. **免费账号要先删掉两个 Capability**：在 `Signing & Capabilities` 里把 `App Groups` 和 `iCloud` 两项点 `−` 删掉（三个 target 都要）。否则会报：
   ```
   Provisioning profile doesn't support the App Groups capability
   ```
   删掉后 App 仍然能用，只是分享扩展和小组件不工作（代码里已做降级：`AppGroup.containerURL` 返回 nil 时自动回落到 App 沙盒目录）。
8. **选设备**：Xcode 顶部设备栏选你的 iPhone（不要选模拟器）。
9. **⌘R 运行**。第一次会报「不受信任的开发者」：
   - iPhone → 设置 → 通用 → VPN 与设备管理 → 点你的 Apple ID → 信任
10. **再运行一次**，装好了。

### 免费账号的 3 个限制

- 一个账号最多同时装 3 个自签 App
- 描述文件 7 天过期，过期后 App 打不开，需要重新 ⌘R（或重新签 IPA）
- 不能推送、不能用 App Groups / iCloud / HealthKit 等需要付费能力的功能

---

## 方案二：自签 IPA（不用 Mac 也能装，Windows 用户看这里）

前提：**IPA 文件本身仍然要用 Mac 编译出来**（见 README 第 3.1 节）。编译完之后，签名和安装可以在 Windows 或 iPhone 上完成。

### 2.1 产出 IPA（Mac，一次性）

```bash
chmod +x tools/*.sh
./tools/build-ipa-sideload.sh
# → build/轻点记账-sideload.ipa
```

这个包已经做了三件事，专为自签准备：
- 不带任何 entitlements（不会有 App Groups 签名失败）
- 移除了 `PlugIns` 里的分享扩展和小组件
- 清掉了旧签名残留

### 2.2 用 Sideloadly 签名（Windows / macOS 都能用，最推荐）

1. 下载 <https://sideloadly.io>（Windows 版直接 exe）
2. iPhone 连电脑，打开 Sideloadly
3. `IPA File` 选 `轻点记账-sideload.ipa`
4. `Apple ID` 填你的 Apple ID（会用来生成免费描述文件，只在本机使用，不会上传到第三方）
5. 点 `Start`，输入 Apple ID 密码（如果开了双重认证，需要在 appleid.apple.com 生成一个**App 专用密码**填进去）
6. 装完后，iPhone → 设置 → 通用 → VPN 与设备管理 → 信任你的 Apple ID
7. 打开 App

> 7 天后过期：重新插上线点一次 `Start` 即可，账单数据不会丢（在 App 沙盒里，重签覆盖安装保留数据）。

### 2.3 用 AltStore 签名（iPhone 上自助，可自动续签）

1. 电脑装 AltServer（<https://altstore.io>），iPhone 装 AltStore
2. AltStore → `My Apps` → 左上角 `+` → 选 IPA 文件
3. 输入 Apple ID / 密码
4. AltStore 会在同一 Wi-Fi 下每 7 天自动帮你续签（需要电脑上的 AltServer 在运行）

### 2.4 用 ESign / 轻松签（已有证书的情况）

如果你手上已有企业证书或共享证书：
1. 把 IPA 传到 iPhone（AirDrop / 文件 App / 网盘）
2. 打开 ESign → `导入` → 选 IPA
3. `签名` → 选证书 → 填 Bundle ID（可改）→ 签名 → 安装
4. 装完信任证书：设置 → 通用 → VPN 与设备管理

> 注意：企业证书签的 App 随时可能被吊销，且分发他人使用涉及合规风险，仅建议自用。

### 2.5 TrollStore（永久签名，但受系统版本限制）

TrollStore 利用 CoreTrust 漏洞，可以实现永久签名不expire。仅支持特定 iOS 版本（大致 14.0–17.0 的部分版本），且需要先安装 TrollStore 本身。如果你的系统版本正好在支持范围内，这是最省事的方式。

---

## 方案三：TestFlight

见 `docs/02-TestFlight与AppStore.md`。简单说：付费账号 → Xcode Archive → 上传 App Store Connect → 建 TestFlight 版本 → 加测试员 → 测试员装 TestFlight App 输入邀请码下载。

---

## 常见报错对照表

| 报错 | 原因 | 解决 |
|---|---|---|
| `No signing certificate "iOS Development" found` | 没有开发者证书 | Xcode → Settings → Accounts → 登录 Apple ID → Manage Certificates → `+` iOS Development |
| `Provisioning profile doesn't support the App Groups capability` | 免费账号没有 App Groups | 删掉三个 target 的 App Groups / iCloud Capability，或改用 `build-ipa-sideload.sh` |
| `Failed to register bundle identifier` | Bundle ID 被别人占了 | 换成 `com.你的名字.qingdianjizhang` |
| `The application-identifier entitlement does not match` | 扩展和主 App 的 Bundle ID 前缀不一致 | 统一改成 `xxx.qingdianjizhang` / `.share` / `.widget` |
| `Untrusted Developer` | 没信任证书 | 设置 → 通用 → VPN 与设备管理 → 信任 |
| 装完打不开、闪退 | 描述文件过期 / 证书被吊销 | 重新签一次 |
| `Unable to install "轻点记账"` | 设备 iOS 低于 17.0 | 工程最低支持 iOS 17（SwiftData 要求），或把 `IPHONEOS_DEPLOYMENT_TARGET` 提到你设备的版本以上再编译 |
| 双击背面没反应 | 快捷指令没绑到「轻点两下」 | 设置 → 辅助功能 → 触控 → 轻点背面 → 轻点两下 → 选「轻点记账」 |

---

## 装机后第一件事

1. 打开 App，走完 4 页引导（最后一页有「开启权限」和「查看图文教程」）
2. 打开微信/支付宝，随便找一张支付截图，双击手机背面
3. 看到半屏面板 + 识别出的金额，点一下分类
4. 回到首页，应该已经有这一笔了

如果识别不准，在面板里点金额可以改，点分类可以换——改一次，App 就记住一次。
