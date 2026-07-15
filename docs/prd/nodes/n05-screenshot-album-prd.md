# N05 截图·相册选图

> 本节点是 Aubade v1 开发 DAG 的第六个节点，依赖 **N03 DeepSeek 解析 + 文本识别**（已完成）。对应技术基线模块 **M2.4 截图·相册选图（备选）**。
>
> 里程碑意义：**第二个"本机系统能力 → 文本 → 复用解析层"的识别入口**（第一个是 N04 语音）。N03 已把"取文本 → DeepSeek 解析 → 直接入账 → 结果卡片 → 失败转手动"整条链路跑通；N04 已验证"本机识别 → 文本 → 复用 N03"范式（语音）。N05 **只替换"文本从哪来"**——在这条链路前面加一段 **iOS Vision 本机 OCR**（从相册选一张付款截图 → 本机读字 → 识别中 → 结果卡片）。图片不外传，只有 OCR 出的文本才交给 DeepSeek。**本节点产出的 Vision OCR 能力供 N06（快捷指令后台入账）复用。**
>
> 上游事实来源：全局 PRD `docs/prd/aubade-v1-prd.md`（主流程 A 截图识别 `:32-39`、备选路径相册选图 `:39`、业务规则 12 本地优先 `:106`、来源字段 `:78`、验收点 2 `:111`、验收点 13 `:122`）、开发 DAG `docs/design/aubade-v1-dev-dag.md`（N05 小节 `:191-202`）、技术基线 `docs/design/aubade-v1-technical-baseline.md`（M2.4 `:80`、统一状态机 `:175-178`、隐私边界 `:43/:214`、Vision 协议抽象 `:270/:293`、来源枚举 `:234`、imageRef `:236`）、**已实现的原型 demo `prototype/app/`（`app.js:267` `openScreenshotSheet` 截图识别说明卡 + 相册选图流程 / `data.js:43-44` 截图识别契约 —— UI 形态与交互以此 demo 为准）**。
> 代码事实来源：直接阅读 N03/N04 已落地源码（本仓库无 `.codegraph/` 索引，逐文件阅读，行号为本 PRD 写作时快照，可能有 ±1 漂移）。
>
> **N03/N04 复用锚点（本节点直接复用，不新造）**：落库编排入口 `RecognitionEntry.recognizeAndSave(text:categories:parser:store:now:source:rawText:)`（`enum RecognitionEntry` 与该方法在 `Aubade/Features/Recognition/TextRecognitionView.swift:12-40`，注释明写"注入以便单测与 N04~N06 复用"）串起 `parser.parse` → 归一 → `store.createTransaction`，**N04 已把 `source`/`rawText` 参数化**（`:23-24` 带默认值 `.text`/`nil`），N05 直接传 `.screenshotAlbum` + 带前缀原文即可，**无需再改签名**；识别页 `TextRecognitionView`（`TextRecognitionView.swift:46-260`），**N04 已扩展 `presetText`/`source`/`rawTextOverride`**（`:50-52` 均带默认值），传预置文本即"进入自动识别一次 → 复用整套识别中/结果卡片/失败态"；结果卡片 `RecognitionResultCard`（`TextRecognitionView.swift:268-298`，private，是 N01 `TransactionEditor` 薄封装，含折叠原文/完成回写/删除撤销二次确认）；识别状态机 `RecognitionPhase`（`Aubade/Features/Recognition/RecognitionState.swift`：idle/recognizing/failed）；错误类型 `RecognitionError`；DeepSeek 解析协议 `TransactionParsing`（`Aubade/Features/Recognition/Parsing/TransactionParsing.swift`）与 mock `MockTransactionParser`；**N04 已落地的单一 `fullScreenCover(item:)` 路由范式** `VoiceRoute`（`Aubade/Features/Record/RecordTabView.swift:7-16`：`.panel` → `.recognizing(text)` 换 item 复用识别页，规避"关一个开一个"的 SwiftUI 时序竞态）——N05 相册流程照此范式；解析器/provider 注入范式 `RecordTabView`（`RecordTabView.swift:51-80` DEBUG 走 mock、Release 走真实）。

## 给用户看的摘要

做完这个节点，你的记账 App 迎来**第三个 AI 入口**——事后补录截图账单：**在 App 内选一张之前存下的付款截图，就能记一笔**：

1. **记账页「截图识别」入口真正可用**：打开「记账」Tab，点「📷 截图识别」（现在还是"敬请期待"占位），弹出一张**说明卡**——先讲清楚"截图记账的主用法是 **iOS 快捷指令**随手一截、后台自动入账"（那条主链路在下个节点 N06 做），并给你两步设置指引；卡片下方有一个**「🖼 从相册选一张图识别」**按钮，这就是本节点做的**备选入口**。
2. **从相册选图 → 本机读字 → 复用已有识别链路**：点「从相册选图」，选一张付款截图，App 先在**本机**用 iPhone 自己的文字识别（iOS Vision）把图里的字读出来（**图片不会离开手机**），再把这段**文字**（只有文字，不含图片）交给 DeepSeek 解析出**金额、支出还是收入、时间、分类**，**直接记成一笔正式账单**——和 N03 文本识别、N04 语音记账走的是同一套"识别中 → 入账 → 结果卡片"。
3. **弹出结果卡片，可当场改**：入账后立刻弹出结果卡片（和文本/语音识别一模一样的那张）——金额多少、归到哪类，还能展开看"从图里识别到的原始文字"。识别得不对当场改；不想记点「删除这笔」（二次确认）撤销。改完剩余金额和统计（N02）立刻跟着变。
4. **第一次用会请求相册权限**：首次从相册选图，系统会弹窗问你是否允许访问**照片**。**同意**才能选图；**拒绝**也不会卡死——会给一句明确提示告诉你去哪打开，且**手动记账、文本识别、语音记账照常用**。
5. **没配 DeepSeek Key 时给明确提示**：和文本/语音识别一样，还没填 Key 就点相册选图，会先弹提示引导去填（复用 N03 已做好的拦截与 Key 填写入口）；没填 Key 不影响手动记账。

**这一节点不做什么**（都在后面节点）：**快捷指令 App Intents 后台入账 + 通知**（N06——说明卡里的"▶︎ 演示：模拟收到一张快捷指令截图"按钮属于 N06 后台链路，本节点仅作占位提示保留，不实现）；相册/麦克风/语音/通知权限的**统一收口与"我的页"设置**、首次引导（N07——本节点只做相册选图**自己必需**的那次相册权限申请与被拒提示）。DeepSeek 解析层、结果卡片、无 Key 拦截、Key 填写 sheet、`recognizeAndSave`/`TextRecognitionView` 的参数化复用能力 **已在 N03/N04 做好，本节点直接复用、不重做、不改签名**。

## 目标

1. **iOS Vision 本机 OCR（M2.4 净新增）**：用 `VNRecognizeTextRequest` 把用户从相册选中的图片**在本机**识别成文本，**中文识别语言** `recognitionLanguages = ["zh-Hans", "zh-Hant"]`（识别精度 `recognitionLevel`、`usesLanguageCorrection` 具体取值留 TRD）。**图片不外传**——只有 OCR 出的文本才进入 N03 解析链路。OCR 出空文本（没读出字）不当报错崩溃，给轻提示（见需求范围 §5）。
2. **相册选图 + 相册权限申请与被拒降级（M2.4 净新增，本节点必需部分）**：从记账页说明卡的「从相册选图」进入系统相册选图（`PHPickerViewController`/SwiftUI `PhotosPicker`，具体留 TRD）；相册访问权限申请（`PHPhotoLibrary`；`PhotosPicker` 走系统受限选择器时权限模型的差异留 TRD 确认）；权限被拒/受限时给**明确降级提示**（复用 N03/N04 "前置 guard → 弹 alert 引导 → 主流程不受影响"范式），**不阻塞手动/文本/语音记账**。新增 `NSPhotoLibraryUsageDescription`（项目走 `GENERATE_INFOPLIST_FILE`，无独立 .plist，见当前理解）。**权限的统一收口与"我的页"设置留 N07**；本节点只做相册选图自身必需的一次申请与被拒提示。
3. **OCR 文本复用 N03 解析入账链路（M2.4 复用，不重做、不改签名）**：本机 OCR 出的文字 **喂给 `RecognitionEntry.recognizeAndSave`**（`TextRecognitionView.swift:18`，**N04 已参数化 `source`/`rawText`**），复用其"DeepSeek 解析 → 归一/兜底 → `createTransaction` 落库"整条链路。**账单来源须落 `TransactionSource.screenshotAlbum`**（枚举已存在 `Aubade/Models/Enums.swift:14`），原文 `rawText` 落 OCR 出的文字并**加 `[截图识别]` 前缀**（用户已拍板）——供结果卡片折叠原文区标识来源与回溯。**`recognizeAndSave` 与 `TextRecognitionView` 的 `source`/`rawText`/`presetText` 参数化 N04 已完成，N05 只是新增一个 `.screenshotAlbum` 的调用方，不再改任何签名。**
4. **复用结果卡片与失败转手动（M2.4 复用，不重做）**：识别成功 → 复用 `RecognitionResultCard`（`TextRecognitionView.swift:268`）弹结果卡片（完成回写/删除撤销二次确认/折叠原文）；OCR 出文本但无金额/网络失败/超时/非法响应 → 复用 N03 失败分支（保留原文、转手动、可重试）。**不新造结果卡片、不改其签名。**
5. **截图识别入口接线 + 说明卡 + 相册流程状态机（M2.4 净新增接线）**：把 `RecordTabView` 四入口网格的「📷 截图识别」（现为占位 `placeholderEntryTitle = "截图识别"`，`RecordTabView.swift:167`）接成真实入口，呈现**截图识别说明卡**（对齐 demo `openScreenshotSheet`：快捷指令主入口讲解 + 两步设置指引 + 「从相册选图」备选按钮 + 「演示：模拟快捷指令截图」占位按钮）；「从相册选图」串起 **选图 → 本机 OCR → 交给识别页复用 N03 识别中/入账/结果卡片** 的状态机（照抄 N04 `VoiceRoute` 单一 `fullScreenCover(item:)` 范式）。OCR 空结果（没读出字）不当报错崩溃，给轻提示可重选（见 §5）。
6. **Vision OCR provider 可注入 + DEBUG mock（可测性，对齐 N03/N04 注入范式）**：把"图片 → 本机 OCR 文本"抽成**可注入、脱 View 的 provider 协议 + 真实实现 + mock 实现**（对齐 `TransactionParsing` 与 N04 `VoiceTranscribing` 协议注入范式）；在 `DebugMenuView`（`Aubade/Debug/DebugMenuView.swift`，仅 DEBUG）补一个**OCR mock 开关**（模拟"成功读出付款截图文本 / 空结果 / 权限被拒 / 本机 OCR 失败"），使模拟器无需真图片也能肉眼走通相册选图 → 入账 → 结果卡片全路径。**本 provider 是 N06 后台链路复用的 OCR 能力，须脱 View、脱相册 UI 可独立调用。**

## 当前理解

### N03/N04 已交付、本节点直接复用的链路（本节点不重做、不改签名）

- **落库编排入口** `RecognitionEntry.recognizeAndSave(text:categories:parser:store:now:source:rawText:)`（`enum RecognitionEntry`，`Aubade/Features/Recognition/TextRecognitionView.swift:12-40`）：`@MainActor static`，串 `parser.parse(text:categories:)` → `RecognitionNormalizer`（金额/时间/分类归一）→ `store.createTransaction(...)`，返回落库后的 `Transaction`。**N04 已把 `source`（默认 `.text`）与 `rawText`（默认 `nil` = 沿用 `text`）参数化**（`:23-24`、`:37-38`）——**N05 传 `source: .screenshotAlbum` + `rawText:` 带前缀原文即可，无需再改签名**。
- **识别页** `TextRecognitionView`（`TextRecognitionView.swift:46-260`）：**N04 已扩展 `presetText`/`source`/`rawTextOverride` 三入参（均带默认值）**（`:50-52`）——传 `presetText = OCR文本` 时，`onAppear` 自动识别一次（`:165-170`，`hasAutoRecognized` 防重入），复用其识别中遮罩（`:176-194`）、成功入账弹结果卡片（`:152-154`）、失败 alert 转手动/重试（`:137-145`）整套。**N05 相册 OCR 出文本后，用 `presetText`/`source: .screenshotAlbum`/`rawTextOverride` 进入此页即复用全链路，零改 N03/N04 结构**（与 N04 语音 `.recognizing` 分支 `RecordTabView.swift:128-137` 同构）。
- **识别结果卡片** `RecognitionResultCard`（`TextRecognitionView.swift:268-298`，private struct）：输入 = **已入账的 `Transaction` + `categories`**，内部是 N01 `TransactionEditor(.edit)` 薄封装，注入 `rawText` 渲染折叠原文；「完成」= `EditorActions.makeUpdate`，「删除这笔」= `confirmationDialog` 二次确认 → `EditorActions.makeDelete`。**它是 private，但 N04 已用"经 `TextRecognitionView` 预置文本复用整页"绕开可见性问题，N05 照此复用，不提升其可见性、不新造卡片。**
- **识别状态机与错误** `RecognitionPhase`（idle/recognizing/failed）、`RecognitionError`（无 Key/网络/超时/无金额/非法响应，`isRetryable` 决定是否给重试）、识别中全屏遮罩范式——**"本机 OCR 出文本之后"的识别中态/失败态可 100% 复用**。
- **DeepSeek 解析层** 协议 `TransactionParsing`、真实 `DeepSeekClient`、mock `MockTransactionParser`——相册 OCR 复用同一 parser 注入，不新建解析层。
- **无 Key 拦截 + Key 填写** N03 已做（前置 guard `KeychainStore.shared.isConfigured` → alert「需要先配置 DeepSeek」→ 最小 Key sheet `KeySetupSheet`）；N04 语音入口已在 `RecordTabView` 前置这套拦截（`RecordTabView.swift:169-175`、`:151-159`）——相册选图入口**同样前置这套拦截**（对齐 demo `openScreenshotSheet` 相册按钮 `app.js:282` 的 `needKeyBlocked()`），复用不重做。
- **单一 `fullScreenCover(item:)` 路由范式** `VoiceRoute`（`RecordTabView.swift:7-16`、`:122-138`）：N04 用 `.panel → .recognizing(spoken:)` 换 item 在同一 presentation 内平滑切"面板 → 复用识别页"，规避两个 `fullScreenCover(isPresented:)` 同帧关一个开一个的 SwiftUI 竞态。**N05 相册流程照此范式**（选图/OCR → `.recognizing(ocrText)` 复用识别页）。
- **解析器/provider 注入范式** `RecordTabView`（`RecordTabView.swift:51-80`）：DEBUG 读 `@AppStorage` 构造 mock、Release 走真实（`DeepSeekClient` / `SpeechVoiceTranscriber`）——OCR provider 照抄这套注入 + DEBUG mock 开关模式。

### 数据底座已就绪（N00 交付，本节点消费，无需改 Schema）

- **`TransactionSource.screenshotAlbum`** 枚举值**已存在**（`Aubade/Models/Enums.swift:14`，N00 已预置 `screenshotShortcut`/`screenshotAlbum` 区分快捷指令 vs 相册，对齐全局 PRD `:78`、技术基线 `:234`），相册入账即用 `.screenshotAlbum`，无需新增枚举。
- **`LedgerStore.createTransaction(...)`**（`Aubade/Store/LedgerStore.swift`）已支持 `source:`/`rawText:` 入参（N03 已用、N04 已透传 `.voice`），相册落库无需改签名——只需 `recognizeAndSave` 把 `.screenshotAlbum` 透传下去（N04 已参数化，直接调用即可）。
- 分类兜底/归一（`RecognitionNormalizer`、`PresetCategories`）N03 已实现，相册复用同一归一（OCR 文本里的商户/品类 → 分类由 DeepSeek 分类名匹配 `LedgerCategory`，与文本/语音同机制）。
- **`Transaction.imageRef`**（技术基线 `:236`，可空、仅截图来源、成功/放弃后清理）：**N05 前台相册选图不涉及原图长期留存**——图片仅在选图那一刻本机 OCR，OCR 后即释放，`imageRef` 在本节点**恒为 nil**。原图临时留存/清理是 N06 快捷指令后台"失败保留原图供补录"才需要的能力（技术基线 `:208`、DAG N06 范围），留 N06/N07 定。

### 相册与 Vision OCR 脚手架现状（N05 首次引入）

- **项目当前无任何相册/Vision 相关代码**（`import Vision`/`VNRecognizeText`/`import Photos`/`PHPicker`/`PhotosPicker` 在 `Aubade/` 下零命中）——相册选图、相册权限、Info.plist `NSPhotoLibraryUsageDescription`、Vision OCR 都是**本节点首次引入**。可复用的是 N03/N04 的交互**范式**（无 Key 拦截 alert、权限被拒降级 alert、单一 `fullScreenCover(item:)` 路由、provider 协议注入 + DEBUG mock），不是现成的相册/OCR 代码。
- **N04 已引入的权限申请范式可参考**（麦克风/语音识别，`Aubade/Features/Recognition/Voice/SpeechVoiceTranscriber.swift`）：首次触发时申请、被拒抛可区分错误、上层 alert 降级——N05 相册权限照此范式（申请时机见 §5）。
- **Info.plist 走 `GENERATE_INFOPLIST_FILE = YES`**（`Aubade.xcodeproj/project.pbxproj`，N04 已以 `INFOPLIST_KEY_*` build setting 加过麦克风/语音 UsageDescription）——新增 `NSPhotoLibraryUsageDescription` 照 N04 方式落地（`INFOPLIST_KEY_*` build setting，具体键名留 TRD）。
- **真实 Vision OCR 与相册选图在代码与原型里都不存在**——是本节点净新增；原型 demo 只到"本地读字→DeepSeek"的**文案层**（`app.js:282` 相册按钮触发 `recognizeFlow('screenshot', ...)` 是用 `MOCK_RECOGNIZE.screenshot` 定值模拟，非真实选图 OCR）。故**"相册选图 → 本机 OCR"这段是真实新增，其后链路全复用 N03**。

### 可测性（对齐 N03/N04/技术基线 §10 口径）

- 测试框架 **XCTest**（`AubadeTests/` 平铺）；N03/N04 已有 `RecognitionEntryTests`（编排入口 mock 注入落库断言）、`RecognitionEntryVoiceTests`（`source=.voice` 落库断言）、`VoiceProviderTests`（provider 分支）、`ResultCardActionsTests`、`MockParserTests`。**相册复用 `recognizeAndSave`，`RecognitionEntryVoiceTests` 的 `source=.voice` 断言范式可直接照搬**（补一条 `source=.screenshotAlbum` 落库断言）。
- OCR 特有逻辑（OCR provider 的成功/空结果/权限被拒/OCR 失败分支、`source=.screenshotAlbum` 的编排）应抽成**脱 View、脱相册 UI 可注入单元**测试，脱离真图片与网络（用 mock OCR provider + mock parser + `PersistenceController.makeInMemoryContainer()`）。

## 涉及的现有链路

- **被扩展/接线**：
  - `RecordTabView` 「📷 截图识别」入口（`RecordTabView.swift:167`，现 `placeholderEntryTitle` 占位）→ 触发真实截图识别说明卡；其余三入口（语音/文本/手动）与结构不动。
  - `RecordTabView` 新增相册路由（照抄 `VoiceRoute` 单一 `fullScreenCover(item:)` 范式）：说明卡「从相册选图」→ 选图 → OCR → `.recognizing(ocrText)` 复用 `TextRecognitionView`。
  - `DebugMenuView`（DEBUG）→ 新增 OCR mock 开关（其余不动）。
  - `Info.plist` 生成配置（pbxproj `INFOPLIST_KEY_*`）→ 新增相册 `NSPhotoLibraryUsageDescription`。
- **被复用（只读消费，不改签名）**：
  - `RecognitionEntry.recognizeAndSave`（**N04 已参数化 `source`/`rawText`，N05 直接传 `.screenshotAlbum`，不再改签名**）。
  - `TextRecognitionView`（**N04 已扩展 `presetText`/`source`/`rawTextOverride`，N05 直接传入复用整页**，不再改签名）。
  - `RecognitionResultCard`（结果卡片，private）、`RecognitionPhase`/`RecognitionError`（状态机与错误）、识别中遮罩范式。
  - `TransactionParsing`/`DeepSeekClient`/`MockTransactionParser`（解析层）、`RecognitionNormalizer`（归一兜底）。
  - N03 无 Key 拦截 alert + 最小 Key 填写 sheet `KeySetupSheet` + `KeychainStore.isConfigured`。
  - `LedgerStore.createTransaction/updateTransaction/delete`、`PersistenceController.makeInMemoryContainer()`、`Transaction`/`LedgerCategory` 模型与 `TransactionSource.screenshotAlbum`。
- **本节点新增**：
  - **Vision OCR provider**（协议 + 真实 `VNRecognizeTextRequest` 实现 + mock 实现）：本机图片转中文文本、中文识别语言、图片不外传；**脱 View 可独立调用（供 N06 复用）**。
  - **相册选图 + 相册权限申请与被拒降级**（本节点必需部分；统一收口留 N07）。
  - **截图识别说明卡 UI**（快捷指令主入口讲解 + 两步指引 + 「从相册选图」+ 「演示」占位按钮）+ 相册选图/OCR 状态机（衔接 N03 识别中态）。
  - Info.plist 相册 `NSPhotoLibraryUsageDescription`。
- **无既有调用方冲突**：OCR provider/说明卡/相册权限为全新代码；**`recognizeAndSave`/`TextRecognitionView` 的参数化 N04 已带默认值完成，N05 不做任何签名改动，仅新增 `.screenshotAlbum` 调用方**；除给截图入口接线、`DebugMenuView` 补开关、加 `NSPhotoLibraryUsageDescription` 外，不改 N01/N02/N03/N04 的模型字段、`LedgerStore`/`TransactionEditor`/`RecognitionResultCard`/语音相关签名与既有行为。

## 需求范围

### 1. 截图识别入口接线 + 说明卡（M2.4，对齐 demo `openScreenshotSheet`）
- 把 `RecordTabView` 「📷 截图识别」入口（`:167` 占位）接成真实入口，呈现**截图识别说明卡**（sheet 留 TRD）。
- 说明卡对齐 demo `openScreenshotSheet`（`app.js:267-283`）：
  - **快捷指令主入口讲解**（`app.js:271`）："主用法是在支付宝/微信/银行付款结果页用 iOS 快捷指令随手一截、后台识别直接入账、只弹一条通知"——**讲解文案保留**（让用户知道主入口是 N06，本节点做的是备选）。
  - **两步设置指引**（`app.js:274-275`）：①去「快捷指令」App 新建"截屏→发送给 Aubade"；②付完款触发它。**指引文案保留。**
  - **「▶︎ 演示：模拟收到一张快捷指令截图」按钮**（`app.js:277`）：**该按钮模拟的是快捷指令后台入账，属于 N06 范畴。本节点保留此按钮占位（对齐 demo 布局），点击弹"敬请期待/N06 提供"占位提示**（复用 `RecordTabView` 已有 `placeholderEntryTitle` "敬请期待" alert 范式 `:142-149`），不实现后台链路。
  - **「🖼 从相册选一张图识别」按钮**（`app.js:279`）：**这是本节点的核心备选入口**（见 §2/§3）。
- 「从相册选图」点击**先复用 N03/N04 无 Key 拦截**（对齐 demo 相册按钮 `app.js:282` 的 `needKeyBlocked()`）——未配 Key 弹 N03 已有拦截 alert + 「去填写」开 N03 已有 Key sheet，不重做。

### 2. 相册选图 + iOS Vision 本机 OCR（M2.4 净新增）
- **从相册选图**：`PHPickerViewController` / SwiftUI `PhotosPicker`（具体留 TRD）选一张付款截图/账单图。
- **本机 Vision OCR**：`VNRecognizeTextRequest` 把选中图片在本机识别成文本，`recognitionLanguages = ["zh-Hans", "zh-Hant"]`（中文，DAG N05 范围 `:200` 明列）；`recognitionLevel`（`.accurate` vs `.fast`）、`usesLanguageCorrection` 取值留 TRD。**`requiresOnDeviceRecognition`（若可用则置 true）/ 无网络依赖——图片不外传**（隐私边界：只有 OCR 文本进 DeepSeek）。
- **OCR 空结果**（图里没读出字/读出空白）→ 不静默失败、不误记，给轻提示可重选（见 §5）。
- 是否展示所选图片缩略图、OCR 中的过渡态细节 → **留 TRD**；PRD 约束"本机 OCR、可观察转出文本、图片不外传、空结果轻提示"。

### 3. OCR 文本入账（M2.4，复用 `recognizeAndSave`，N04 已参数化）
- 本机 OCR 出的文字 → 经识别页 `TextRecognitionView`（`presetText = OCR文本` 自动识别）调 `RecognitionEntry.recognizeAndSave`（`TextRecognitionView.swift:18`），复用 DeepSeek 解析 → 归一 → 落库整条链路。
- **账单落 `TransactionSource.screenshotAlbum`**（`Enums.swift:14`）：经 `TextRecognitionView(source: .screenshotAlbum)` 透传（N04 已参数化，无需改签名）。
- **`rawText` 加 `[截图识别]` 前缀**（用户已拍板）：落库原文 = OCR 出的文字带 `[截图识别]` 前缀（`rawTextOverride` 传入），供结果卡片折叠原文区标识来源、供回溯；确切格式（换行/包裹）留 TRD，但"带 `[截图识别]` 前缀"已定。
- 空 OCR 文本（没读出字）不进 `recognizeAndSave`，走 §5 空结果提示。

### 4. 识别成功/失败复用 N03（M2.4，不重做）
- **成功** → 复用 `RecognitionResultCard`（`TextRecognitionView.swift:268`）弹结果卡片：金额/方向/分类/时间/商户/备注 + 折叠原文（OCR 文字）+ 「完成」回写 / 「删除这笔」二次确认撤销。改删后列表/剩余/统计（N01/N02）自动刷新。
- **失败**（OCR 出文本但无金额/网络/超时/非法响应）→ 复用 N03 失败分支（`RecognitionError` 分支、保留原文、转手动、`isRetryable` 决定重试）。无金额场景保留 OCR 出的文字、可转手动填写（对齐全局 PRD 验收点 13 前台部分）。
- 不新造结果卡片/失败 UI，不改其签名。

### 5. 相册权限与 OCR 特有降级（M2.4 净新增，本节点必需部分）
- **权限申请时机 = 首次"点从相册选图"时才申请**（对齐 N04 "首次触发时申请"范式，与 N07 首次引导集中申请不重复）：仅"看一眼说明卡"不弹权限，用户点「从相册选图」才触发系统相册授权。
- **被拒/受限降级**（复用 N03/N04 alert 范式）：相册权限 denied/restricted → 明确提示（说明需要相册权限、去"设置"开启的引导），**不崩溃、不卡死**，**手动/文本/语音记账不受影响**。
- **本机 OCR 失败**（Vision 请求失败/图片无法解码）→ 提示"这张图没能识别，换一张或转手动"，不外传、不误记。
- **OCR 空结果**（授权成功、选了图但没读出字）→ 轻提示"没从这张图读出文字，换一张或手动记"，可重选，不报错、不误记。
- 新增 Info.plist `NSPhotoLibraryUsageDescription`（文案留 TRD，须说明用途=从相册选付款截图记账、本机识别）。
- **权限统一收口（我的页权限状态、首次引导集中申请、被拒后的统一设置引导）明确留 N07**；本节点只做相册选图自身跑通所必需的一次申请与被拒提示。

### 6. Vision OCR provider 可注入 + DEBUG mock（可测性 + 供 N06 复用）
- 把"图片 → 本机 OCR 文本"抽成**可注入的 provider 协议 + 真实实现 + mock 实现**（对齐 `TransactionParsing` / N04 `VoiceTranscribing` 注入范式）。**协议须脱 View、脱相册 UI，可用图片数据独立调用**——这是 N06 快捷指令后台链路"接收图片 → 后台 OCR"要复用的能力（技术基线 `:274`、DAG N06 "复用 OCR 能力" `:209`）。
- `DebugMenuView`（DEBUG）补 **OCR mock 开关**：模拟 成功读出付款截图文本 / 空结果 / 本机 OCR 失败（相册权限被拒可用真机或 mock 表达，具体留 TRD），使模拟器无真图片也能肉眼走通相册选图 → 入账 → 结果卡片 / 各降级路径。
- ⚠️ **验收所需的解析定值**：mock OCR 成功须产出一段**能被 parser 解出验收定值**的文本。对齐 demo `MOCK_RECOGNIZE.screenshot`（`data.js:43-44`：金额 88.5 / 支出 / 分类"食" / 商户星巴克）——**具体是新增 `MockTransactionParser` 的截图样例 Behavior、还是 mock OCR 产出可被现有 parser 解出的文本，留 TRD**；PRD 层明确：**验收成功链路的定值来自 N05 为截图场景准备的 mock 定值**（对齐 demo 截图契约），mock 恒返回样例定值以验收字段落库正确性，真实 OCR 准确性由用户后续真机自测。

### 7. 单元测试（对齐技术基线 §10、N03/N04 范式）
- **`source=.screenshotAlbum` 落库**：以 mock OCR 文本 + mock parser 注入 `recognizeAndSave`，断言落库 `source=.screenshotAlbum`、`rawText` 保留 OCR 文本（带 `[截图识别]` 前缀）、金额 `Decimal` 无浮点误差（照搬 `RecognitionEntryVoiceTests` 范式补一条）。
- **OCR provider 分支**：mock OCR provider 的 成功/空结果/OCR 失败（及权限被拒，若以错误表达）各分支返回可区分、上层据此走对应路径（脱 View、脱真图片、脱相册 UI）。
- **N04 参数化不回归**：确认 N05 新增 `.screenshotAlbum` 调用不影响 `.text`/`.voice` 既有落库行为（复核既有 `RecognitionEntryTests`/`RecognitionEntryVoiceTests`）。

## 不做什么

以下均属其他节点，本节点**不实现**：
- **快捷指令 App Intents 后台入账 + 通知**（N06）：说明卡的"▶︎ 演示：模拟快捷指令截图"按钮**仅作占位提示保留**（点击弹"敬请期待/N06 提供"），不实现 App Intents、后台 OCR→解析→入账链路、本地通知、后台超时兜底、原图临时留存/清理、App Group 共享容器判定。本节点只做**App 内前台相册选图**这一条备选链路。
- **语音记账**（N04，已完成）：本节点不碰语音入口/`VoiceTranscribing`/语音权限。
- **权限统一收口与设置界面**（N07）：我的页权限状态展示、首次启动引导里的集中权限申请、被拒后的统一"去设置"收口、相册/麦克风/语音/通知的统一策略——本节点只做相册选图**自身必需**的一次相册权限申请与被拒降级提示。
- **重做 N03/N04 已交付部分**：DeepSeek 解析层、归一/兜底、错误类型、结果卡片 `RecognitionResultCard`、无 Key 拦截、Key 填写 sheet、Keychain 封装、`recognizeAndSave`/`TextRecognitionView` 的参数化能力（N04 已带默认值完成）——**全部复用，不重写、不改签名**。
- **真实 DeepSeek Key 联网 + 真机真图片端到端作为本节点门禁**：可观察验收以 **mock OCR + mock parser 注入端到端** + 单测为准（对齐 N03/N04 已确认约定）；真实 Key + 真机真图片 OCR 的端到端由用户后续自测，不阻塞节点完成。
- **原图长期留存/图库管理**（v1 不做，全局 PRD `:105/:127`）：`imageRef` 在本节点恒 nil；相册选图 OCR 后即释放，不做原图落库或附件管理。
- 不改 N00/N01/N02/N03/N04 的模型字段、`LedgerStore`/`TransactionEditor`/`RecognitionResultCard`/语音相关签名与既有行为、N01 记账/账单/编辑、N02 统计/剩余、N03 文本识别、N04 语音记账既有行为。

## 验收标准

（对齐 DAG 中 N05 的"退出标准（可观察）"`:201` 与全局 PRD 验收点 2。可用模拟器 + DEBUG OCR mock 开关注入肉眼观察，`source=.screenshotAlbum` 落库与 provider 分支另以单元测试佐证；真机真图片 OCR + 真实 Key 端到端为用户后续自测。）

1. **相册选图入账（PRD 验收点 2，mock 注入观察）**：记账页点「📷 截图识别」弹说明卡，点「🖼 从相册选一张图识别」（DEBUG OCR mock = 成功）选一张图 → 本机 OCR 出文本 → 经识别中 → **直接生成一笔已入账账单**并弹结果卡片：金额/方向/分类/商户按 mock 截图定值落库（对齐 demo `data.js:43` 星巴克 88.5/支出/"食"）、金额 `Decimal` 无浮点误差、**来源=截图相册（`TransactionSource.screenshotAlbum`）**、原文保留 OCR 出的文字（带 `[截图识别]` 前缀）。（此定值由 **N05 为截图场景准备的 mock 定值**产出；mock 恒返样例定值，验收链路与字段落库正确性；真实 OCR 准确性由用户后续真机自测。）
2. **结果卡片可改/撤销（复用 N03）**：结果卡片可改金额/方向/分类/时间/商户/备注，「完成」后改动生效、统计与剩余（N02）自动刷新；「删除这笔」二次确认后撤销入账、列表/剩余/统计同步。
3. **识别原文可见**：结果卡片可展开查看"从图里识别到的原始文字"（`rawText`，带 `[截图识别]` 前缀）。
4. **相册权限被拒降级（本节点必需部分）**：（真机拒绝相册授权，或 DEBUG 以对应 mock/表达）点「从相册选图」时给**明确降级提示**（说明需要相册权限、去设置开启），**不崩溃、不卡死**，且**手动记账、文本识别、语音记账照常可用**。
5. **本机 OCR 失败/空结果不误记**：（DEBUG OCR mock = 空结果 / OCR 失败）给"没读出文字/这张图没识别，换一张或转手动"提示，**不报错、不生成脏账单**，可重选。
6. **无 Key 拦截（复用 N03）**：Keychain 无 Key 时点「从相册选图」，先弹 N03 已有拦截提示且不进行选图/识别；「去填写」进入 N03 已有 Key sheet；全程手动记账不受影响。
7. **说明卡形态（对齐 demo）**：说明卡呈现快捷指令主入口讲解 + 两步设置指引 + 「从相册选图」+ 「演示：模拟快捷指令截图」按钮；「演示」按钮点击弹"敬请期待/N06 提供"占位（不实现后台链路）；「从相册选图」是本节点真实备选入口。
8. **隐私边界（PRD 业务规则 12）**：图片识别用 Vision 本机 OCR（图片不外传）；只有 OCR 出的**文本**经 N03 链路发 DeepSeek；无图片上传、无录音。`imageRef` 恒 nil（本节点不留存原图）。
9. **`source=.screenshotAlbum` 与 provider 单测**：单测覆盖——相册 OCR 文本经 `recognizeAndSave` 落库 `source=.screenshotAlbum`、`rawText` 保留（带前缀）、金额 Decimal 无误差；OCR provider 成功/空/失败分支可区分；N04 既有 `.text`/`.voice` 落库不回归；均 mock 注入、脱真图片与网络。
10. **不越界**：无快捷指令/App Intents/后台/通知（留 N06）；不做权限统一收口/我的页设置/首次引导（留 N07）；不重写 N03/N04 解析层/结果卡片/Key/语音相关；不改 N01/N02/N03/N04 既有行为；`recognizeAndSave`/`TextRecognitionView` 零签名改动（N04 已参数化）；`imageRef` 恒 nil。

## 已确认约定

（以下由上游 PRD/原型 demo/技术基线/DAG 定死或由 N03/N04 既有实现约束，作为既定实现约束，非待确认项。TRD 直接据此落地。）

1. **图片识别 = iOS Vision 本机 OCR、图片不外传**（全局 PRD 业务规则 12 `:106`、技术基线隐私边界 `:43/:214`、DAG N05 范围 `:200`）：`VNRecognizeTextRequest` + `recognitionLanguages = ["zh-Hans","zh-Hant"]`，本机识别；只有 OCR 出的文本进 DeepSeek，图片本身不出机。
2. **OCR 出文本后的链路 100% 复用 N03**（DAG N05 "复用 N03 解析链路与结果卡片" `:200`）：不重写解析层、结果卡片、无 Key 拦截、Key sheet；相册只新增"选图 → 本机 OCR"这段前置。
3. **账单来源落 `.screenshotAlbum`**（全局 PRD 来源字段 `:78`、技术基线 `:234`、`Enums.swift:14` 已有枚举）：相册入账 `source=.screenshotAlbum`；**`recognizeAndSave`/`TextRecognitionView` 的 `source`/`rawText`/`presetText` 参数化 N04 已完成，N05 零签名改动、只新增 `.screenshotAlbum` 调用方**。
4. **截图识别 UI 形态以 demo 为准**（`app.js:267` `openScreenshotSheet`、`data.js:43-44`）：说明卡含快捷指令主入口讲解 + 两步指引 + 「从相册选图」备选 + 「演示」按钮；**「演示：模拟快捷指令截图」属 N06 后台链路，本节点仅占位提示保留、不实现**；「从相册选图」是本节点真实备选入口，流程 = 本机 OCR → 复用 N03 解析入账 → 结果卡片。
5. **`imageRef` 恒 nil、不做原图留存**（全局 PRD `:105/:127` v1 不做图库管理、技术基线 `:236` imageRef 仅截图来源）：前台相册选图 OCR 后即释放图片，本节点不落 `imageRef`、不做原图临时留存；原图留存/清理是 N06 后台失败补录才需要的能力，留 N06/N07。
6. **权限收口切分：N05 只做相册选图自身必需的申请 + 被拒降级，统一收口留 N07**（DAG N07 范围 `:227` 明列"相册/… 权限申请时机与被拒降级的统一收口"）：本节点不做我的页权限状态、首次引导集中申请，只保证相册选图能申请到权限、被拒有明确降级且不卡死主流程。
7. **权限申请时机 = 首次"点从相册选图"时**（对齐 N04 首次触发申请范式）：看说明卡不弹权限，用户点「从相册选图」才触发相册授权；与 N07 首次引导集中申请不重复。
8. **验收深度 = mock 端到端 + 单测**（对齐 N03/N04 已确认约定）：DEBUG OCR mock 开关 + mock parser 注入下相册链路完整跑通 + `source=.screenshotAlbum`/OCR provider 分支单测为准；真机真图片 OCR + 真实 Key 端到端为用户后续自测，不阻塞节点完成。
9. **Vision OCR provider 协议抽象 + mock 注入，且脱 View 供 N06 复用**（对齐 N03 `TransactionParsing`/N04 `VoiceTranscribing` 注入范式、技术基线 §10 可测口径 `:293`、DAG N06 "复用 OCR 能力" `:209`）：图片转文本抽成可注入、脱 View、脱相册 UI 的单元，DEBUG mock 支撑无真图片肉眼验收与单测；真实实现须可用图片数据独立调用，为 N06 后台链路复用铺路。
10. **Info.plist 走 `GENERATE_INFOPLIST_FILE`**（`project.pbxproj` 现状、N04 已用此方式加麦克风/语音键）：相册 `NSPhotoLibraryUsageDescription` 以 `INFOPLIST_KEY_*` build setting 落地（键名/文案留 TRD），文案须说明用途=从相册选付款截图记账、本机识别。
11. **`rawText` 加 `[截图识别]` 前缀**（用户已拍板）：相册入账原文落库带 `[截图识别]` 前缀（对齐 demo `data.js:44` raw 语义），标识来源、供结果卡片折叠原文回溯；确切格式（换行/包裹）留 TRD。
