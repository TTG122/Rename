# 02 · TestFlight 与 App Store

> 前提：**付费 Apple Developer Program 账号**（个人 688 元/年 或 公司账号）。TestFlight 和 App Store 都必须用它，免费 Apple ID 做不到。

---

## 一、上传前的一次性配置

### 1.1 App Store Connect 建 App

1. 登录 <https://appstoreconnect.apple.com>
2. 我的 App → `+` → 新建 App
   - 平台：iOS
   - 名称：**轻点记账**（App Store 上不能重名，被占了就在名字里加后缀，例如「轻点记账 - 双击记一笔」）
   - 主要语言：简体中文
   - 套装 ID：选你在 Xcode 里注册的 `com.xxx.qingdianjizhang`
   - SKU：随意唯一字符串，例如 `qingdianjizhang001`
3. 记住这个 App 的 **Apple ID（一串数字）**

### 1.2 Xcode 工程配置

在 `Signing & Capabilities` 里确认：

- [x] 三个 target 的 Team 都是付费团队
- [x] Bundle ID 前缀一致（`.app` / `.share` / `.widget`）
- [x] 主 App 添加了 **App Groups** → `group.com.qingdianjizhang.app`（三个 target 都要勾）
- [x] 主 App 添加了 **iCloud** → CloudKit → 容器 `iCloud.com.qingdianjizhang.app`
- [x] 版本号 `MARKETING_VERSION = 1.0.0`、`CURRENT_PROJECT_VERSION = 1`

### 1.3 隐私清单与权限文案

- `QingDianJiZhang/PrivacyInfo.xcprivacy` 已在 target 内（`NSPrivacyTracking = false`，声明了 UserDefaults / DiskSpace / FileTimestamp 的使用理由）
- 六条权限文案在 `Config/App-Info.plist`，每条都要说清「为什么需要」，不能只写「需要相册权限」

### 1.4 图标

`AppIcon-1024.png` 必须是 1024×1024、**不带透明通道**、**不带圆角**（圆角由系统裁）。想换图标：改 `tools/make_icon.py` 重跑。

---

## 二、归档上传

```
Xcode → 顶部设备选「Any iOS Device (arm64)」
     → Product → Archive
     → Organizer 弹出 → Distribute App
     → App Store Connect → Upload
     → 一路 Next（勾 Upload your app's symbols 便于看崩溃日志）
```

上传成功后等 5–15 分钟（Apple 会做一次自动化检查）。

---

## 三、TestFlight

1. App Store Connect → 你的 App → **TestFlight** 标签
2. 首次会问「出口合规信息」：选 **App 不使用加密**（我们的 Info.plist 已声明 `ITSAppUsesNonExemptEncryption = false`）
3. 构建版本处理完成后，填 **Test Information**：
   - 测试版描述：`双击手机背面 2 秒记一笔。请先按引导配置快捷指令和「轻点背面」。`
   - 反馈邮箱
4. **内部测试**（最多 100 人，无需审核）：`Internal Testing` → `+` 建组 → 加人（必须是团队成员的 Apple ID）→ 立刻可测
5. **外部测试**（最多 10000 人，首次需要审核，一般 1–2 天）：
   - `External Testing` → 建组 → 勾选构建版本 → 提交审核
   - 审核通过后，测试员会收到邮件邀请；你也可以生成 **公开链接**（Public Link），任何人点开都能装上
6. 测试员在 iPhone 上装 **TestFlight** App → 打开邀请链接 → 安装
7. 每次上传新构建，TestFlight 版本自动更新；构建 90 天过期

---

## 四、正式上架检查清单

### 4.1 功能与稳定性

- [ ] 冷启动不闪退，首次引导能完整走完
- [ ] 双击背面 → 面板 → 入账 → 撤销，全链路可用
- [ ] 手动记账、编辑、删除、批量删除都正常
- [ ] 相册导入、分享导入、CSV/XLSX 导入都跑通（至少测一遍微信真实账单）
- [ ] 语音记账授权 → 识别 → 入账
- [ ] CSV / Excel / PDF / 长图导出都能生成并被其他 App 打开
- [ ] Face ID 打开/关闭都正常
- [ ] 深色模式、动态字体（最大字号）下不截断、不重叠
- [ ] 无数据时每个页面都有空状态，不是空白页
- [ ] 删除全部数据后 App 不崩，能重新开始

### 4.2 审核高风险点（重点看）

- [ ] **不能宣传「自动读取微信/支付宝订单」**。App 内文案、App Store 描述、截图文案都不能出现这种表述。我们统一表述为「双击背面，用截图识别」。
- [ ] **不能伪装成系统功能**。面板是 App 自己的界面，用了系统风格的毛玻璃，但没有使用系统图标的误导性组合，也没有用「Apple」「官方」等字样。
- [ ] **权限请求必须出现在有上下文的时机**（引导第 4 页 / 首次使用语音时），不能一启动就弹。
- [ ] **不能要求登录才能用**。我们没有账号体系，符合要求。
- [ ] **订阅/内购**：本版本无内购。如果后续加，必须接 StoreKit 且提供恢复购买。
- [ ] **隐私政策链接**必须可访问（用 `docs/04-隐私政策与合规.md` 的内容挂到你自己的域名或 GitHub Pages）。
- [ ] **App 隐私**问卷：在 App Store Connect 里如实勾选「不收集数据」——因为我们确实不上传。若开启 iCloud 同步，仍然算「不收集」（数据在用户自己的 iCloud）。
- [ ] **演示账号**：不需要，因为无需登录。审核备注里写清「无需登录，双击背面需先配置快捷指令，可在设置页查看图文教程」。
- [ ] **审核备注**建议附一段说明：
  ```
  本 App 无登录、无内购。核心功能「双击背面」依赖系统「轻点背面」手势 + 快捷指令，
  这是 iOS 官方能力，App 内「设置 → 双击背面设置教程」有完整图文说明。
  测试路径：打开 App → 完成 4 页引导 → 首页点「记一笔」可手动记账；
  或在相册里选一张支付截图，通过分享菜单发送到本 App，可直接体验 OCR 识别与分类。
  ```

### 4.3 元数据

- [ ] 名称 ≤30 字，副标题 ≤30 字（见 `docs/03-AppStore文案与截图.md`）
- [ ] 关键词 ≤100 字符，逗号分隔，不堆砌竞品名
- [ ] 描述：首行就讲清价值，不要写「最好的记账软件」
- [ ] 截图 6.7"（1290×2796）和 6.1"（1179×2556）各至少 3 张，最多 10 张
- [ ] 年龄分级：4+
- [ ] 主分类：财务；次分类：效率
- [ ] 版权：你的名字或公司名
- [ ] 支持 URL：可指向 GitHub Issues 或你的邮箱页

### 4.4 首次提交被拒的常见原因（对照自检）

| 被拒理由 | 我们的情况 | 建议 |
|---|---|---|
| 4.2 功能太少（Minimum Functionality） | 功能完整：OCR、分类、图表、导入导出、语音、小组件 | 描述里强调「双击背面」这个差异化能力 |
| 2.5.1 使用非公开 API | 未使用 | 我们只用了公开框架 |
| 5.1.1 权限说明不清 | 六条文案都写明了用途 | 保持 |
| 2.3.1 隐藏功能 | 无 | — |
| 3.1.1 绕过内购 | 无内购 | — |
| 4.3 模板化/重复 | 设计是原创的 | 截图别用模板 |

---

## 五、上线之后

- **崩溃**：Xcode → Organizer → Crashes，或 App Store Connect → 分析
- **评分**：不要做「给五星解锁功能」这类诱导，会被拒；可以用 `SKStoreReviewController` 在用户记满 20 笔后询问一次
- **版本迭代**：改 `CURRENT_PROJECT_VERSION`（build 号必须递增），`MARKETING_VERSION` 按语义化版本改
- **回滚**：App Store 不支持回滚，只能发新版本；TestFlight 可以随时停掉某个构建
