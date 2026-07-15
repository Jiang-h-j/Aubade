# N06 截图·快捷指令后台入账 + 通知 — TRD 索引

> 节点 PRD：`docs/prd/nodes/n06-shortcut-background-prd.md`（已评审通过）。
> 上游代码事实：N00 数据层 + N01 手动/编辑器 + N02 剩余/统计 + **N03 DeepSeek 解析 + 文本识别** + **N04 语音** + **N05 截图·相册选图（Vision 本机 OCR）**（均已完成）。
> UI 与交互事实来源：已实现原型 demo `prototype/app/`（`app.js:266/270/276` 截图说明卡 + 「演示」按钮 / `data.js:43` 截图识别契约 88.5/星巴克/食）。
> 本节点无 `.codegraph/` 索引，代码事实来自逐文件阅读，行号为写作时快照（可能 ±1 漂移）。

## 里程碑意义

N06 是 **PRD 第一主流程、也是"最省事"的记账主入口**——把 N05 已落地的"本机 OCR 能力"和 N03 已落地的"解析→归一→落库→结果卡片"链路，从**前台 UI 触发**搬到**后台 App Intent 触发**：付款页用 iOS 快捷指令随手一截，App 在后台一口气跑完 **本机 OCR → 读 Key → DeepSeek 解析 → 直接入账 → 弹一条本地通知**，全程不打断用户。

**本节点净新增的只有四样**：① App Intents 入口（主 App target 内，非扩展进程）；② 后台链路编排核心单元（脱 View、可注入、可单测）；③ UNUserNotificationCenter 本地通知（三类 + 点击深链）；④ 后台失败原图临时留存与清理。OCR、DeepSeek 解析、归一、落库、结果卡片、手动补录、无 Key 判定**全部复用 N00/N03/N05，不重写、不改签名**。

## 关键设计前提（两项用户已拍板，TRD 直接据此落地）

1. **存储共享 = in-app App Intents**：App Intent 定义在**主 App target 内**，系统后台唤醒主 App 进程执行 `perform()`，直接共享现有 `PersistenceController.makeContainer()` 的 ModelContainer 与 Keychain——**不建 App Extension、不配 App Group、不改 N00 建库、不迁移 N01~N05 数据**（对齐 `PersistenceController.swift:14-16` in-app 路线注释）。
2. **完成门禁 = 延续 N03/N04/N05 约定**：代码可编译 + DEBUG「演示」mock 后台链路端到端跑通 + 单测覆盖后台各分支即可标 done；真机（后台时间预算、快捷指令传图、后台通知交付）由用户后续自测，不阻塞节点完成。**方案 B 降级仅记录预案、本节点默认不实现**。

## 核对后确认的关键代码事实（决定 TRD 落地方式，含与 PRD 措辞的澄清）

| 事实 | 核对结论 | 对 TRD 的影响 |
|---|---|---|
| `RecognitionEntry.recognizeAndSave` 签名 | `(text, categories, parser, store, now, source=.text, rawText=nil)`，**无 `imageRef` 参数**，`now` 必传（`TextRecognitionView.swift:18-24`） | 成功入账走它、`imageRef` 恒 nil（与 N05 一致）；**失败保留原图不经 recognizeAndSave**，由后台核心单元的失败分支单独落临时文件（切片 01/02） |
| `LedgerStore.createTransaction` | 支持 `source:`（**必传**）/`rawText:`/`imageRef:`（默认 nil）（`LedgerStore.swift:48-61`） | 后台成功入账经 `recognizeAndSave` 落 `.screenshotShortcut`；无需改签名 |
| `AubadeApp.container` | 是 **实例属性**（`AubadeApp.swift:6`），**非 static**，`perform()` 后台无法直接访问 | 切片 01 新增**共享容器持有点**（`AppModelContainer` 单例，持有容器再取 context，遵守 memory 悬垂陷阱） |
| 深链承接点 | ContentView 极薄、RootTabView 用 `@State selectedTab`、**无 UNUserNotificationCenterDelegate、无深链状态**（`ContentView.swift`/`RootTabView.swift`） | 切片 02 净新建：`AppDelegate`(UNUserNotificationCenterDelegate) + 深链路由状态提升到 `RootTabView` |
| `RecognitionResultCard` | **private struct**（`TextRecognitionView.swift:268`），强依赖 `@Environment(\.modelContext)` + sheet 呈现 | 切片 02 通知点击"经 tx 打开结果卡片"**照抄 N04/N05 手法**——不碰 private 卡片，走 `TextRecognitionView` 已有的 `presetText`/成功入账通路或按 tx.id 打开编辑（详见切片 02 §设计） |
| 演示按钮 | `ScreenshotIntakeSheet.swift:26/:52-56` 现"敬请期待" alert；sheet 现注入 `recognizer` + `onRecognized` 回调（`:11-12`，`RecordTabView.swift:194` 唤起） | 切片 02 把占位替换为真实后台链路演示，需给 sheet 补注入后台核心单元所需依赖 |
| 净新增能力 | `import AppIntents`/`UNUserNotification`/App Group/深链 delegate 全项目**零命中**（`rg` 核实） | AppIntents、通知、深链均为 N06 首次引入；复用的是 N03~N05 的能力与**范式**，非现成后台/通知代码 |
| pbxproj 权限键 | `GENERATE_INFOPLIST_FILE=YES` + N04 已加麦克风/语音 `INFOPLIST_KEY_NS*UsageDescription`；**无 extension target** | 通知/后台若需 Info.plist 键，照 N04 用 `INFOPLIST_KEY_*` build setting 落地（切片 02） |

## 切片划分与顺序

N06 拆成 **2 个单一职责切片**，按"先脱 View 纯逻辑底座、后 UI/系统接线闭环"排序，每片可独立编译：

| 切片 | 名称 | 单一职责 | 依赖 | 覆盖 PRD 验收 |
|---|---|---|---|---|
| 01 | 后台链路核心单元 + App Intent 入口 + 通知协议抽象 + 共享容器 | **脱 View、脱真系统通知、可注入单测的地基**：`BackgroundIntakeService`（编排 OCR→读 Key→解析入账→发通知，注入 OCR provider/parser/store/通知器/now）+ `NotificationSending` 协议 + `IntakeNotification` 三类值 + `RecordAubadeScreenshotIntent`(AppIntent)+`AubadeShortcuts`(AppShortcutsProvider)+ `AppModelContainer` 共享容器持有点 + 后台各分支全单测（成功落 `.screenshotShortcut`/无 Key/OCR 空/OCR 失败/超时/无网/无金额） | N03/N05 | 验收 6/9，为 1/4/5/8 提供底座 |
| 02 | 真实通知发送 + 权限 + 点击深链路由 + 演示接线 + 原图留存清理 + DEBUG 端到端 | `UNUserNotificationCenterNotifier`（实现 `NotificationSending`，构造三类真实通知）+ 权限申请与被拒降级 + `AppDelegate`(UNUserNotificationCenterDelegate)+ 深链路由（成功→结果卡片 / 失败→补录带原文原图 / 无 Key→Key 配置）+ 演示按钮接后台核心单元 + 原图临时留存与清理 + Info.plist 键 + DEBUG 端到端 | 切片 01 | 验收 1/2/3/4/5/7/8/10 |

### 为什么这样拆

- **切片 01 是脱 View 纯逻辑底座**：后台链路的编排顺序、无 Key/OCR/解析各失败分支的"不落脏账"不变量、`source=.screenshotShortcut` 落库、通知**该发哪一类**（用 mock 通知器断言），全部可脱真图片/真网络/真系统通知单测（PRD 验收 6/9）。App Intent 只是 `perform()` 里薄薄调一次核心单元，`AppShortcutsProvider` 暴露动作——**入口壳零业务逻辑**。共享容器持有点也在此片落地（后台 `perform()` 拿 context 的唯一合法通道）。风险最低，切片 02 直接消费。
- **切片 02 接成可用闭环**：把切片 01 的"通知协议"用真实 `UNUserNotificationCenter` 实现、把点击路由接到复用的结果卡片/补录/Key 配置、把「演示」按钮接后台核心单元。**核心接缝与 N04/N05 同构**——通知点击"打开结果卡片"复用 N04/N05 已验证的"经 `TextRecognitionView` 预置文本/成功入账通路"绕开 `RecognitionResultCard` 是 private 的手法。DEBUG「演示」+ N05 `DebugScreenshotMockSettings` 支撑模拟器无真图片/真网络肉眼验收全路径与各分支通知。

## 切片文件

- `01-background-intake-intent-trd.md`
- `02-notification-deeplink-demo-trd.md`

## 全节点共用的关键约束（两片都遵守）

1. **OCR 后的链路 100% 复用 N03/N05，不重写**（PRD 已确认约定 3）：不重做 `TextRecognizing`/`VisionTextRecognizer` OCR、`DeepSeekClient` 解析（含 20s 超时）、`RecognitionNormalizer` 归一、`RecognitionError`、`recognizeAndSave` 落库编排、结果卡片、无 Key 判定 `KeychainStore`。N06 只新增"App Intent 后台触发 + 通知 + 原图留存"外壳与编排。
2. **对 N03/N04/N05 零签名改动**（PRD 已确认约定 5、核心论证）：`recognizeAndSave`（`:18-24` 已有 `source=.text`/`rawText=nil` 默认值）、`TextRecognizing`、`DeepSeekClient`、`LedgerStore.createTransaction`（已支持 `source`/`rawText`/`imageRef`）、`ManualEntryView(prefillNote:)`（`:16` 已带默认值）签名均不改；N06 只**新增 `source: .screenshotShortcut` 调用方**。若通知失败补录需给 `ManualEntryView` 加"原图引用"入参，照 `prefillNote` 范式加**带默认值**参数做零破坏扩展。
3. **不误记脏账是红线**（PRD 已确认约定 6、验收 6、技术基线 §7.3）：复用 `recognizeAndSave` "任何失败都在 `createTransaction` 之前" 不变量（`TextRecognitionView.swift:6-7`）；后台任一失败分支（无 Key/OCR 空/OCR 失败/超时/无网/无金额/非法响应）不留半条账单、后台任务及时结束（不悬挂）。单测覆盖各分支"未落库"断言。
4. **超时兜底复用 `DeepSeekClient` 已内置 20s 超时**（PRD 已确认约定 4，`DeepSeekClient.swift:14`）：N06 不新造超时，复用既有超时 + 可区分 `RecognitionError`；**是否再加后台总时间预算保护——本节点默认不加**（真机数据决定，见切片 01 §不做什么）。
5. **账单来源落 `.screenshotShortcut`、原文带 `[快捷指令]` 前缀**（PRD 已确认约定 5，`Enums.swift:13` 已有枚举、当前零调用方）：后台入账 `source=.screenshotShortcut`；`rawText` = `[快捷指令]\n<OCR 出的文字>`（对齐 N05 `[截图识别]`/N04 `[语音转文字]` 前缀范式与 demo `data.js`）。parse 收纯 OCR 文本、落库 rawText 带前缀，二者经 `recognizeAndSave` 的 `text`/`rawText` 分离。
6. **图片本机 OCR、不外传**（全局 PRD 业务规则 12、验收 7）：复用 N05 `VisionTextRecognizer`（Vision 纯本机、无上云路径）；只有 OCR 出的**文本**经 N03 链路发 DeepSeek，无图片上传、无录音。
7. **存储共享靠 in-app 同进程 + 共享容器持有点**（PRD 已确认约定 1）：**不自建 `ModelContainer`**、禁链式 `container().mainContext`（N00 SIGTRAP 陷阱，见 memory `swiftdata-dangling-context-crash`）；后台 `perform()` 经切片 01 的 `AppModelContainer` 共享单例拿到与主 App 同一容器的 context，`LedgerStore(context)` 落库。分类模型类型名一律 `LedgerCategory`（非裸 `Category`，见 memory `aubade-model-category-naming`）。
8. **后台失败保留原图、成功/放弃清理**（PRD 已确认约定 7，`Transaction.imageRef:16` 注释"清理逻辑在 N06/M9"）：失败分支把原图写本机临时目录、`imageRef` 记引用供补录；成功入账（`imageRef` 恒 nil，不留存）或用户放弃补录后清理。临时目录/清理触发点见切片 02 §设计。
9. **通知本节点只做自身必需申请，统一收口留 N07**（PRD 已确认约定 9、DAG N07 范围）：通知权限申请时机见切片 02；被拒时后台仍完成 OCR→解析→入账（成功仍落账），仅不发通知、不崩溃、不误记。
10. **可测性：核心单元脱 View、脱 App Intent 框架、脱真系统通知，可注入 + mock**（PRD 已确认约定 10）：`BackgroundIntakeService` 注入 OCR provider/parser/store/`NotificationSending`/now；通知发送抽象成 `NotificationSending` 协议以便单测断言"发了哪类通知"而非真弹通知；「演示」按钮 + N05 `DebugScreenshotMockSettings` 支撑无真图片/真网络端到端。
11. **不越界**：不做独立扩展进程/App Group/数据迁移（in-app 路线）；不做权限统一收口/我的页设置/首次引导/通知开关（留 N07）；不碰 N05 相册流程与其它入口既有行为；不重写 N03/N05 OCR/解析层/结果卡片/Key；不默认实现方案 B 降级（仅记录预案）。
