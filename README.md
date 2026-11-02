# 轻点记账 · QingDianJiZhang

**双击 iPhone 背面，2 秒记完一笔。**

一个原生 iOS 记账 App：付完钱停在支付成功页，双击手机背面 → 快捷指令把截图交给 App → Apple Vision 在本机识别金额与商户 → 弹出系统风格分类面板 → 点一下分类就入账，2 秒后自动收起回到原来的页面。

原生技术栈：Swift / SwiftUI / MVVM / SwiftData / Vision / App Intents / App Shortcuts / Share Extension / WidgetKit / Charts / LocalAuthentication。

---

## 📲 直接下载（不需要 Mac）

**下载地址：[最新版本 Releases](../../releases/latest)**

在 Releases 里找到 `QingDianJiZhang-x.x.x-sideload.ipa`，下载后按下面三步装到 iPhone：

1. 电脑装 [Sideloadly](https://sideloadly.io)（Windows / macOS 都行），iPhone 打开「设置 → 隐私与安全性 → 开发者模式」
2. Sideloadly 里选这个 IPA，填**你自己的** Apple ID，点 `Start`
3. 手机上「设置 → 通用 → VPN 与设备管理」→ 信任你的 Apple ID

> 这个 IPA 是**未签名**的，必须用你自己的 Apple ID 签一次才能装——这是 iOS 的规则，不是我们偷懒。
> 免费 Apple ID 签名 7 天过期，到期重新签一次，账单数据不会丢。
> 详细图文（含 12 条排错）：[`docs/00-最快装到手机.md`](docs/00-最快装到手机.md)

---

## 0. 先看这三条（很重要）

1. **IPA 必须用 macOS + Xcode 编译**。任何「在 Windows 上直接产出 IPA」的说法都是假的——Swift 编译器只有 Apple 工具链里有。本目录交付的是**完整可编译工程**，在 Mac 上一条命令就能出 IPA（见第 3 节）。
2. **未签名的 IPA 不能直接装进 iPhone**。iPhone 只安装「被 Apple 信任的签名」的包。所以要么你自己用 Apple ID 签名（免费 / 付费都行，见 `docs/01-安装到iPhone.md`），要么走 TestFlight / App Store（需要 99 美元/年的开发者账号）。
3. **免费 Apple ID 自签会损失两个功能**：分享扩展和桌面小组件，因为它们依赖 App Groups（付费账号才有的能力）。App 本体所有功能不受影响。自签专用打包脚本已经把这两块剥掉了，不会因此装不上。

---

## 1. 交付内容

```
简记/
├── QingDianJiZhang.xcodeproj/       # 可直接双击打开的 Xcode 工程（Xcode 16+）
├── project.yml                      # XcodeGen 备用配置（可选）
├── README.md                        # 本文件
├── Config/
│   ├── App-Info.plist               # 主 App 权限说明 / URL Scheme / 启动屏
│   ├── Share-Info.plist             # 分享扩展
│   ├── Widget-Info.plist            # 小组件
│   ├── App.entitlements             # App Groups + iCloud
│   ├── Share.entitlements
│   ├── Widget.entitlements
│   └── PrivacyInfo.xcprivacy        # 隐私清单（App Store 必需）
├── QingDianJiZhang/                 # 主 App（40+ Swift 文件）
│   ├── App/                         # 入口、路由、根视图
│   ├── Models/                      # SwiftData 模型 + 种子数据
│   ├── Design/                      # 设计系统（颜色、组件）
│   ├── Services/                    # OCR、解析、分类、查重、月报、导入导出…
│   ├── Features/                    # 8 个业务页面
│   ├── Intents/                     # App Intents + App Shortcuts
│   └── Resources/Assets.xcassets    # App 图标 + 强调色
├── QingDianJiZhangShare/            # 分享扩展
├── QingDianJiZhangWidget/           # 桌面小组件
├── QingDianJiZhangTests/            # 单元测试（60+ 断言）
├── docs/                            # 安装、上架、文案、隐私、快捷指令
└── tools/
    ├── build-ipa.sh                 # 打完整版 IPA（含扩展）
    ├── build-ipa-sideload.sh        # 打自签精简版 IPA
    ├── make_icon.py                 # 图标生成脚本（已生成，可重跑）
    └── train_text_classifier.swift  # 可选：用 CreateML 训练本地分类模型
```

---

## 2. 在 Mac 上跑起来（5 分钟）

```bash
# 1. 要求：macOS 14+，Xcode 16+，iOS 17+ 设备
xcodebuild -version

# 2. 打开工程
open QingDianJiZhang.xcodeproj
```

打开后只需改一处：

```
Xcode → 左侧点项目 → TARGETS 选 QingDianJiZhang → Signing & Capabilities
  · Team: 选择你的 Apple ID（没有就 Add an Account）
  · Bundle Identifier: 建议改成 com.你的名字.qingdianjizhang
```

> 三个 target（App / Share / Widget）的 Bundle ID 需要保持父子关系：
> `xxx.qingdianjizhang`、`xxx.qingdianjizhang.share`、`xxx.qingdianjizhang.widget`。
> 改完 App 的，记得同步改扩展的，否则会报 "doesn't match" 之类的签名错误。

然后 `⌘R` 选真机运行。第一次装完，App 会引导你配置双击背面。

**如果只想跑模拟器**：可以直接 `⌘R` 选 iPhone 16 模拟器，除了「双击背面」「拍照」之外都能测。

---

## 3. 出 IPA（三种用途，别选错）

### 3.0 没有 Mac？用 GitHub 的 macOS 机器编

`.github/workflows/build-ipa.yml` 已经写好了。把整个目录推到 GitHub，然后：

```
GitHub 仓库 → Actions → Build IPA → Run workflow → flavor 选 sideload → Run
等 2~4 分钟 → 本次运行的 Artifacts → 下载 qingdian-sideload-ipa
```

拿到 `轻点记账-sideload.ipa` 之后，用 Sideloadly / AltStore 签一下就能装（见 `docs/01-安装到iPhone.md`）。
公开仓库完全免费，私有仓库的免费额度也足够（一次构建 2–4 分钟）。

> 这条路只解决「编译」，不解决「签名」。签名必须用你自己的 Apple ID 在本机完成——
> 证书和描述文件不应该出现在任何仓库里，这是安全底线。

### 3.1 自己用 / 发给朋友自签 → `build-ipa-sideload.sh`

```bash
chmod +x tools/*.sh
./tools/build-ipa-sideload.sh
# 产物：build/轻点记账-sideload.ipa
```

这个 IPA 是**未签名**的，拿去用 Sideloadly / AltStore / ESign 导入，用你自己的 Apple ID 签一下就能装。详细步骤见 `docs/01-安装到iPhone.md`。

### 3.2 已签名、只装自己注册过的设备 → `build-ipa.sh`

```bash
SIGN=1 TEAM_ID=你的10位TeamID ./tools/build-ipa.sh
# 产物：build/export/*.ipa（development 描述文件）
```

### 3.3 TestFlight / App Store → Xcode 图形化归档

```
Xcode → Product → Archive → Distribute App → App Store Connect → Upload
```

然后去 App Store Connect 建 TestFlight 版本、加测试员、拿公开链接。完整流程见 `docs/02-TestFlight与AppStore.md`。

---

## 4. 架构

### 4.1 分层

```
Views (SwiftUI)            Features/*
   ↓ 只读 @Query、调服务
Services (无 UI 依赖)      CapturePipeline / RecordService / ReceiptParser /
                          CategoryClassifier / DuplicateDetector / MonthlyReportBuilder /
                          ExportService / ImportService / OCRService / VoiceRecorder
   ↓
Models (SwiftData)         Transaction / Category / MerchantRule / Budget
```

- **MVVM 的取舍**：识别流水线本身是纯函数式服务（`ReceiptParser.parse(lines:) -> ParsedReceipt`），天然可测，不需要 ViewModel 包一层。只有需要「输入 → 异步 → 状态机」的页面（语音、导入）才用 `@Observable` 的 model 对象。硬套 MVVM 给每个页面配一个 ViewModel 只会增加噪音。
- **`RecordService` 是唯一的写入口**：新增、修改、撤销、删除都必须走它，以保证三件事同时发生——刷新查重指纹、学习商户规则、刷新小组件快照。任何页面直接 `context.insert()` 都会漏掉后两步。

### 4.2 双击背面的完整链路

```
双击背面
  → iOS 运行快捷指令「轻点记账」
  → 快捷指令：获取图像（截图）→ 轻点记账 App Intent
  → RecordFromImageIntent.perform()   [openAppWhenRun = true]
  → CapturePipeline.process(imageData:)   ← OCR → 解析 → 分类 → 查重
  → 判定：
       智能自动模式 && 置信度达标 → 直接入账 + Toast + 撤销
       否则                      → AppRouter.presentConfirm(draft)
  → CaptureConfirmView（半屏 sheet，.ultraThinMaterial + 28pt 圆角）
  → 点分类 → RecordService.save → 面板收起 → 回到支付页
```

**平台限制（必须说清楚）**：iOS 不允许 App Intent 在其他 App 之上弹自定义 UI，所以面板出现时本 App 会短暂到前台。我们把它做成了「只显示一个半屏面板」而不是完整界面，确认完立刻消失，观感接近系统弹层。这是当前 iOS 能力边界内最好的做法。

### 4.3 识别是怎么做的

`ReceiptParser` 不是「抓第一个数字」，而是四层策略：

1. **清洗**：先用正则把日期、时间、订单号（≥9 位纯数字）、长英数字串替换成空格，避免把 `2026-11-02`、`4200002026...` 当成金额。
2. **关键词定位 + 位置约束**：按权重扫描「实付款 100 > 支付金额 95 > 交易金额 92 > 订单金额 90 > 合计 68 > 金额 52」，取**该关键词之后出现的第一个数字**——这样才能在同屏出现「订单金额 ¥45 / 优惠 -¥9 / 实付 ¥36」时正确取 36。
3. **反向排除**：命中「优惠 / 折扣 / 立减 / 返现 / 余额」的行权重直接扣 120，不会被选为实付金额。
4. **兜底**：全都没命中时，取带 ¥ 符号的最大金额；再不行取全文最大金额，并用置信度把这个不确定性传到 UI。

商户名用的是**打分制**：命中品牌词典 +2.4、含「店/餐厅/公司/酒店」等后缀 +1.3、出现在页面上半部分 +0.9，命中黑名单（「支付成功」「账单详情」「收银台」…）−10，带金额符号 −1.2，带日期/时间 −3。取最高分。

### 4.4 分类

三级优先级：

| 优先级 | 来源 | 置信度 |
|---|---|---|
| 1 | 用户历史规则（`MerchantRule`，用户改过一次就记住） | 0.97 |
| 2 | 本机 Core ML 文本模型（可选，放进去才生效） | ≤0.93 |
| 3 | 品牌关键词词典（`BrandLexicon`，约 400 个词） | 0.55 ~ 0.95 |

词典是纯数据（`BrandLexicon.entries`），改一行就能加品牌，不需要重新训练模型。
想上模型的话跑 `tools/train_text_classifier.swift`（CreateML，需 macOS），把生成的 `.mlmodelc` 拖进工程即可，代码会自动启用；不放也不影响任何功能。

### 4.5 数据模型

`Transaction` 的字段完全覆盖需求：`id / kind / amountCents / merchant / item / categoryID / categoryName / occurredAt / createdAt / updatedAt / platform / account / orderNumber / note / source / confidence / imageHash / dedupeKey / isDeleted`。

两个关键决策：

- **金额用「分」为单位的 Int**，不用 Double。财务场景下 `0.1 + 0.2 != 0.3` 是灾难。
- **不用 `@Attribute(.unique)`，所有属性都有默认值**。这是 SwiftData 开启 CloudKit 同步的硬性要求（CloudKit 不支持唯一约束、不支持非可选属性）。唯一性改由 `dedupeKey` + `RecordService` 在应用层保证。

### 4.6 查重

按证据强度加权，阈值 0.72：

| 证据 | 得分 |
|---|---|
| 订单号相同 | 1.00 |
| 图片 SHA256 相同 | 0.97 |
| 金额 + 商户 + 时间 ≤5 分钟 | 0.94 |
| 同商户 1 小时内同金额 | 0.78 |
| 2 分钟内同金额 | 0.76 |
| 感知指纹汉明距离 ≤4（截图被重新压缩） | 0.80 |

命中不直接拦截，而是提示「这笔账单可能已经记录」，让用户选「仍然记录 / 取消」。

### 4.7 月报

`MonthlyReportBuilder` 全部本地计算：总收入/支出/结余/日均、分类占比、周趋势、环比、预算进度、常去商户、固定支出（同商户≥3 次且波动<12%）、疑似订阅（连续两月同商户同金额，或命中「会员/订阅/连续包月」）、异常消费（单笔 ≥ 同类均值 3 倍且 ≥200 元）。

「AI 月报总结」是**用真实数字套模板生成**的句子，不编造数据、不调云端。想换真模型：`cloudAIEnabled` 打开后可以在 `MonthlyReportBuilder.makeSummary` 里换成网络请求，脱敏逻辑留了插入点。

### 4.8 导入导出

- **CSV**：自写 RFC 4180 解析器，支持引号、逗号、换行、BOM；编码自动尝试 UTF-8 → GB18030 → Big5（微信导出常是 GBK）。
- **Excel 读**：自己实现 ZIP 解析（中央目录 + `COMPRESSION_ZLIB` 解压）+ XMLParser 读 `sharedStrings.xml` 和 `sheet1.xml`，无第三方库。
- **Excel 写**：自己实现 ZIP 打包（stored）+ 最小 OOXML，Excel / Numbers / WPS 都能打开。
- **PDF**：`UIGraphicsPDFRenderer` 分页排版。
- **长图**：`ImageRenderer` 3x 渲染。

### 4.9 隐私实现（不是口号）

- OCR 走 Vision 本地识别，图片不出设备。
- 分类走本地词典 / 本地模型。
- 云端 AI 默认关闭，开启后才传脱敏月度统计。
- 不读剪贴板、不读其他 App 数据、不存完整卡号（只留后四位）。
- Face ID 用 `LocalAuthentication`；敏感配置可进 Keychain（见 `SettingsStore`）。
- `PrivacyInfo.xcprivacy` 声明了 UserDefaults / DiskSpace / FileTimestamp 三类必要 API 的使用理由，`NSPrivacyTracking = false`，无任何第三方 SDK。

---

## 5. 页面清单

| 页面 | 文件 | 说明 |
|---|---|---|
| 引导 | `Features/Onboarding/OnboardingView.swift` | 4 页：产品主张 → 原理 → 隐私 → 权限与双击背面配置 |
| 首页 | `Features/Home/HomeView.swift` | 本月支出/收入/结余/预算/今日 → 快捷入口 → 双击状态 → 分类占比环图 → 最近账单 |
| 识别确认 | `Features/Capture/CaptureConfirmView.swift` | 半屏面板，点分类即入账，可直接改金额/备注，重复时二次确认 |
| 账单列表 | `Features/Ledger/LedgerView.swift` | 按日分组、搜索、分类/月份/收支筛选、左滑修改删除、批量管理 |
| 编辑账单 | `Features/Ledger/TransactionEditorView.swift` | 新建 + 编辑共用 |
| 统计月报 | `Features/Stats/StatsView.swift` | 收盘趋势、分类条形图、排行、预算、环比、AI 小结、订阅、异常、导出 |
| 分类管理 | `Features/Categories/CategoryManagerView.swift` | 系统/自定义分类、图标颜色、商户规则、消费习惯 |
| 设置 | `Features/Settings/SettingsView.swift` | 记账模式与置信度、双击教程、预算、Face ID、iCloud、导入导出、隐私、清空 |
| 语音记账 | `Features/Voice/VoiceRecordView.swift` | 实时波形 + 实时解析预览 |
| 导入 | `Features/Settings/ImportView.swift` | 文件 / 批量截图，导入前逐条查重 |
| 教程 | `Features/Settings/SetupGuideView.swift` | 双击背面图文步骤 + 系统设置深链 |
| 隐私 | `Features/Settings/PrivacyPolicyView.swift` | 完整隐私说明 |

---

## 6. 已知边界（写在前面，免得你上手才发现）

| 限制 | 原因 | 影响 |
|---|---|---|
| 不能「全自动读取所有支付订单」 | iOS 沙盒，第三方 App 无权读其他 App 界面/数据库 | 必须由用户双击背面主动触发一次；拿不到截图时用分享/相册/账单导入 |
| 面板出现时 App 会短暂到前台 | App Intent 不能跨 App 弹自定义 UI | 已做成半屏面板 + 自动收起，观感接近系统弹层 |
| 免费 Apple ID 无 App Groups | Apple 账号能力限制 | 自签版没有分享扩展和小组件 |
| 免费 Apple ID 签名 7 天过期 | Apple 账号能力限制 | 到期重签一次（AltStore 可自动续） |
| iCloud 同步需要付费账号 | CloudKit 需要 iCloud Capability | 开关默认关闭；开启前请在 Xcode 里加 iCloud Capability 并创建 `iCloud.com.qingdianjizhang.app` 容器 |
| 语音识别中文准确率受环境影响 | 系统 SFSpeechRecognizer | 已做「实时解析预览」，识别不对可以直接改 |

---

## 7. 二次开发指引

- **加一个分类**：改 `SystemCategories.all`（新装用户生效），或直接在 App 里「分类管理 → +」。老用户数据不会被重置。
- **加品牌词**：`Services/Classification/BrandLexicon.swift` 的 `entries` 数组加一条。
- **调分类阈值**：`RuleBasedClassifier` 里 `0.55 + best.score * 0.12`，或设置页的「自动记账置信度」滑杆。
- **换配色**：`Design/Theme.swift` 里的语义色，深浅色都在一处。
- **改图标**：改 `tools/make_icon.py` 里的坐标/颜色后重跑，或直接替换 `AppIcon-1024.png`（1024×1024，不带透明通道）。

---

## 8. 文档索引

- `docs/01-安装到iPhone.md` —— Xcode 真机安装 / 自签 IPA（Sideloadly、AltStore、ESign）/ 常见报错
- `docs/02-TestFlight与AppStore.md` —— TestFlight 全流程 + App Store 上架检查清单
- `docs/03-AppStore文案与截图.md` —— 名称、副标题、关键词、描述、截图文案与拍摄清单
- `docs/04-隐私政策与合规.md` —— 可直接发布的隐私政策文本 + 审核答复模板
- `docs/05-快捷指令与双击背面.md` —— 快捷指令的逐步搭建说明 + 排错
