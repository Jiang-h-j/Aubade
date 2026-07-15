# N05 截图·相册选图 — TRD 索引

> 节点 PRD：`docs/prd/nodes/n05-screenshot-album-prd.md`（已评审通过）。
> 上游代码事实：N00 数据层 + N01 手动记账/编辑器 + N02 剩余/统计 + **N03 DeepSeek 解析 + 文本识别** + **N04 语音记账**（均已完成）。
> UI 与交互事实来源：已实现原型 demo `prototype/app/`（`app.js:266` `openScreenshotSheet` 截图说明卡 + 相册选图 / `data.js:42-44` 截图识别契约）。
> 本节点无 `.codegraph/` 索引，代码事实来自逐文件阅读，行号为写作时快照（可能 ±1 漂移）。

## 里程碑意义

N05 是**第二个"本机系统能力 → 文本 → 复用 N03 解析层"的识别入口**（第一个是 N04 语音）。N03 已把"取文本 → DeepSeek 解析 → 直接入账 → 结果卡片 → 失败转手动"整条链路跑通；N04 已验证"本机识别 → 文本 → 复用 N03"范式（语音）并把 `recognizeAndSave`/`TextRecognitionView` 参数化。N05 **只替换"文本从哪来"**——在这条链路前面加一段 **iOS Vision 本机 OCR**（相册选图 → 本机读字 → 识别中 → 结果卡片）。图片不外传，只有 OCR 出的文本才交给 DeepSeek。**本节点产出的 Vision OCR provider 供 N06（快捷指令后台入账）复用**。

## 关键设计前提（相册选图实现方式）

**相册选图用 SwiftUI `PhotosPicker`（基于 PHPicker，用户已拍板）**，非 `PHPhotoLibrary` 全库授权：

- `PhotosPicker` 的选图器跑在**独立系统进程**，用户选完只把那一张图交还 App——**根本不需要相册权限、不弹授权、不需要 `NSPhotoLibraryUsageDescription`**（Apple 隐私设计）。
- 因此 PRD §5 原文的"相册权限申请 + 被拒/受限降级 alert"、验收点 4、Info.plist `NSPhotoLibraryUsageDescription` **在本实现下无从触发**，本 TRD **不实现相册权限申请与被拒降级**（对应调整见下"对 PRD 的偏离说明"）。
- 前台降级只剩三类：**用户取消选图**（不报错、静默回说明卡）、**OCR 空结果**（没读出字 → 轻提示可重选）、**本机 OCR 失败**（图片无法解码/Vision 请求失败 → 提示换一张或转手动）。

### 对 PRD 的偏离说明（PhotosPicker 免权限带来的调整）

PRD §2/§5/验收点 4/已确认约定 10 假设走"相册权限申请"路径；用户拍板改用 `PhotosPicker` 免权限后，以下 PRD 条目**在本节点降为不适用**（不是遗漏，是实现方式使其无从发生）：

| PRD 条目 | 原文 | 本 TRD 处理 |
|---|---|---|
| §2/§5 相册权限申请与被拒降级 | 首次点选图申请相册权限、denied/restricted 降级 alert | **不实现**——PhotosPicker 免权限，无授权弹窗、无被拒态 |
| 验收点 4 相册权限被拒降级 | 拒绝授权时明确降级提示、不卡死 | **不适用**——无授权可拒；主流程不受影响这一保证仍然成立（选图独立进程） |
| §5/已确认约定 10 Info.plist `NSPhotoLibraryUsageDescription` | `INFOPLIST_KEY_*` 加相册用途文案 | **不新增**——PhotosPicker 无需此 key |

**其余 PRD 目标/验收全部落地**：Vision 本机 OCR、图片不外传、OCR 空/失败降级、`source=.screenshotAlbum` 入账、`[截图识别]` 前缀 rawText、复用结果卡片/失败转手动、无 Key 拦截、说明卡形态、OCR provider 可注入 + DEBUG mock、`imageRef` 恒 nil、单测。

## 切片划分与顺序

N05 拆成 **2 个单一职责切片**，按"先纯逻辑底座、后 UI 接线闭环"排序，每片可独立编译：

| 切片 | 名称 | 单一职责 | 依赖 | 覆盖 PRD 验收 |
|---|---|---|---|---|
| 01 | Vision OCR provider 底座 + 截图 mock 定值 | **纯逻辑地基，零 UI、脱真图片**：`TextRecognizing` 协议 + `TextRecognizeError` + 真实 `VisionTextRecognizer`（`VNRecognizeTextRequest` 中文本机识别）+ `MockTextRecognizer`（三态：成功/空/失败）+ `MockTransactionParser.screenshotSample`（88.5/食/星巴克）+ 全分支单测 + `source=.screenshotAlbum` 落库单测 | N03/N04 | 验收 9（单测）、为 1/8 提供底座 |
| 02 | 相册选图 + 说明卡 + 入口接线 + 状态机 + DEBUG mock | `RecordTabView`📷 接线（无 Key 拦截前置）+ 截图说明卡 `ScreenshotIntakeSheet`（快捷指令讲解 + 两步指引 + 「从相册选图」+「演示」占位）+ `PhotosPicker` 选图 → OCR → `.recognizing(ocrText)` 复用 N03（照抄 `VoiceRoute` 单一 `fullScreenCover(item:)`）+ OCR provider 注入 + DebugMenu 截图 mock 开关 | 切片 01 | 验收 1/2/3/5/6/7/8/10 |

### 为什么这样拆

- **切片 01 是纯逻辑底座**：OCR provider 协议/真实实现/mock、截图 mock 定值、`source=.screenshotAlbum` 落库全无 UI 与相册 UI 依赖，可完全脱环境单测（PRD 验收 9）。先把"图片 → 文本"契约与"记成 `.screenshotAlbum` 账单"落库焊死，风险最低，切片 02 直接消费。**真实 `VNRecognizeTextRequest` 是一次性请求（喂 `CGImage`/`Data` → 回文本），可用测试图片数据独立驱动，脱 View、脱相册 UI——这正是 N06 后台链路要复用的能力。本切片对 N03/N04 已落地代码零签名改动**（`recognizeAndSave`/`TextRecognitionView` 的 `source`/`rawText`/`presetText` N04 已带默认值完成），仅新增 `.screenshotAlbum` 调用方与截图 mock 定值。
- **切片 02 接成可用闭环**：入口接线 + 说明卡 + `PhotosPicker` 选图 + OCR + 复用 N03 成功/失败态 + DEBUG mock。**核心接缝与 N04 同构**——复用 N04 已落地的 `VoiceRoute` 单一 `fullScreenCover(item:)` 范式（`RecordTabView.swift:7-16`）与"经 `TextRecognitionView` 预置文本复用整页"绕开 `RecognitionResultCard` 是 private 的手法，N05 照抄。DEBUG 截图 mock 支撑模拟器无真图片肉眼验收全路径。

## 切片文件

- `01-ocr-provider-source-trd.md`
- `02-album-picker-wiring-debug-trd.md`

## 全节点共用的关键约束（两片都遵守）

1. **OCR 出文本后的链路 100% 复用 N03，不重写**（DAG N05 "复用 N03 解析链路与结果卡片"、PRD 已确认约定 2）：不重做 DeepSeek 解析层、`RecognitionNormalizer` 归一、`RecognitionError`、结果卡片 `RecognitionResultCard`、无 Key 拦截、Key sheet、Keychain。相册只新增"选图 → 本机 OCR"前置段。
2. **对 N03/N04 零签名改动**（PRD 已确认约定 3、核心论证）：`recognizeAndSave`（`TextRecognitionView.swift:18-24` 已有 `source: = .text`/`rawText: = nil`）与 `TextRecognitionView`（`:50-52` 已有 `presetText`/`source`/`rawTextOverride`）N04 已参数化完成，N05 **只新增 `source: .screenshotAlbum` 调用方**，不改任何签名；不改 `LedgerStore.createTransaction`（已支持 `source`/`rawText`）、`RecognitionResultCard`、`TransactionEditor` 签名。
3. **图片本机 OCR、不外传**（全局 PRD 业务规则 12、PRD 已确认约定 1、验收 8）：`VNRecognizeTextRequest` + `recognitionLanguages = ["zh-Hans","zh-Hant"]`。**Vision 文本识别是纯本机能力、无上云路径**（区别于 N04 Speech 需显式 `requiresOnDeviceRecognition`——`VNRecognizeTextRequest` 无此属性，识别一律在设备本地进行），图片天然不外传；只有 OCR 出的**文本**经 N03 链路发 DeepSeek，无图片上传、无录音。`imageRef` 恒 nil（本节点不留存原图）。
4. **OCR provider 协议抽象 + mock 注入，且脱 View 供 N06 复用**（PRD 已确认约定 9、对齐 N03 `TransactionParsing`/N04 `VoiceTranscribing` 范式）：图片转文本经 `TextRecognizing` 协议注入；真实 `VisionTextRecognizer` 与 `MockTextRecognizer` 同契约，均可用图片数据独立调用（脱 View、脱相册 UI）。**可观察验收以 DEBUG mock 端到端 + 单测为准**，真机真图片 OCR + 真实 Key 为用户后续自测，不阻塞节点（PRD 已确认约定 8）。
5. **账单来源落 `.screenshotAlbum`、原文带 `[截图识别]` 前缀**（PRD 已确认约定 3/11）：相册入账 `source=.screenshotAlbum`（`Enums.swift:14` 已有枚举）；`rawText` = `[截图识别]\n<OCR 出的文字>`（对齐 N04 `[语音转文字]` 前缀范式与 demo `data.js:44`）。parse 收纯 OCR 文本、落库 rawText 带前缀，二者经 `recognizeAndSave` 的 `text`/`rawText` 分离。
6. **验收定值来自新增截图 mock，不复用 N03/N04 定值**（PRD §6/验收 1）：截图成功定值 = 金额 88.5 / 支出 / 分类"食" / 商户星巴克（新增 `MockTransactionParser.screenshotSample`），与 N03 `.success`（256/京东/其他）、N04 `.voiceSample`（20/行）并存不替换。归一命中预置支出分类"食"（`PresetCategories`）。
7. **相册选图用 PhotosPicker 免权限，无权限收口**（用户拍板、见上"关键设计前提"）：不实现相册权限申请、被拒降级、`NSPhotoLibraryUsageDescription`。前台降级只有：用户取消选图 / OCR 空结果 / OCR 失败。权限统一收口与我的页设置全部留 N07（本节点因 PhotosPicker 免权限，连"相册选图自身必需的一次申请"都不需要）。
8. **不自建 `ModelContainer`**：一律注入 `ModelContext`/`LedgerStore(context)`，禁链式 `container().mainContext`（N00 SIGTRAP 陷阱，见 memory）。相册入账仍走 `recognizeAndSave` → `LedgerStore.createTransaction`。
9. **不越界**：快捷指令 App Intents 后台入账 + 通知 → N06（说明卡「演示」按钮仅占位提示保留，不实现后台链路）；权限统一收口/我的页/首次引导 → N07。本节点只做 **App 内前台相册选图**这一条备选链路；不改 N01/N02/N03/N04 既有行为，`imageRef` 恒 nil。
