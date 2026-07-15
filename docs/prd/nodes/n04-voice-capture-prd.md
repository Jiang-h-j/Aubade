# N04 语音记账

> 本节点是 Aubade v1 开发 DAG 的第五个节点，依赖 **N03 DeepSeek 解析 + 文本识别**（已完成）。对应技术基线模块 **M2.3 语音记账入口**。
>
> 里程碑意义：**第一个"本机系统能力 → 文本 → 复用解析层"的识别入口**。N03 已把"取文本 → DeepSeek 解析 → 直接入账 → 结果卡片 → 失败转手动"整条链路跑通；N04 **只替换"文本从哪来"**——在这条链路前面加一段 **iOS Speech 本机语音转文字**（按住说话 → 识别中 → 结果卡片）。语音不外传，只有转出的文本才交给 DeepSeek。它也是 N05（截图 OCR）"本机识别 → 文本 → 复用解析层"范式的先行验证。
>
> 上游事实来源：全局 PRD `docs/prd/aubade-v1-prd.md`（主流程 B 语音记账 `:43-46`、业务规则 1/12、验收点 3、来源字段 `:78`）、原型 markdown `docs/design/aubade-v1-prototype.md`（§4 语音入口 `:51/:56/:120`、§4.3 结果卡片共用 `:163-184`、明确不做真实语音 `:31/:339`）、**已实现的原型 demo `prototype/app/`（`app.js:310` `openVoiceCapture` 语音流程 / `data.js:45` 语音识别契约 —— UI 形态与交互以此 demo 为准）**、开发 DAG `docs/design/aubade-v1-dev-dag.md`（N04 小节 `:178-189`）。
> 代码事实来源：直接阅读 N03 已落地源码（本仓库无 `.codegraph/` 索引，逐文件阅读，行号为本 PRD 写作时快照，可能有 ±1 漂移）。
>
> **N03 复用锚点（本节点直接复用，不新造）**：落库编排入口 `RecognitionEntry.recognizeAndSave(text:categories:parser:store:now:)`（`enum RecognitionEntry` 与该方法在 `Aubade/Features/Recognition/TextRecognitionView.swift:12-38`，注释明写"注入以便单测与 N04~N06 复用"）串起 `parser.parse` → 归一 → `store.createTransaction`；结果卡片 `RecognitionResultCard`（`Aubade/Features/Recognition/TextRecognitionView.swift:249-279`，是 N01 `TransactionEditor` 的薄封装，含折叠原文/完成回写/删除撤销二次确认/失败转手动）；识别状态机 `RecognitionPhase`（`Aubade/Features/Recognition/RecognitionState.swift:7-11`：idle/recognizing/failed）；错误类型 `RecognitionError`（`Aubade/Features/Recognition/Parsing/RecognitionError.swift`）；DeepSeek 解析协议 `TransactionParsing`（`Aubade/Features/Recognition/Parsing/TransactionParsing.swift:15-19`）与 mock `MockTransactionParser`；解析器注入范式 `RecordTabView.textParser`（`Aubade/Features/Record/RecordTabView.swift:32-39`，DEBUG 走 mock、Release 走真实）。
>
> **原型 demo 关键实现事实（本节点 UI 与交互直接对齐）**：语音入口卡片 `app.js:212`（🎤 语音记账 / 副标题「说一句话」）；`openVoiceCapture()` `app.js:310-320`（底部 sheet：🎤 大图标 + 「按住下面按钮说话」+ 「按住说话」按钮 + 示例「打车花了 20 块」，触发 `recognizeFlow('voice','正在识别语音…','本地转文字 → DeepSeek 解析')`）；入口前置无 Key 拦截 `startEntry()` `app.js:262`（`needKeyBlocked` 语音同样拦截）；识别中/成功/失败流转 `recognizeFlow` `app.js:350-368`（成功切账单 Tab 弹结果卡片、失败 `recognizeFailed` 保留原文转手动）；语音识别结果契约 `data.js:45`（amount 20 / expense / 分类"行" / raw 带 `[语音转文字]` 前缀 + 引号原句）。

## 给用户看的摘要

做完这个节点，你的记账 App 迎来**第二个 AI 入口，也是第一个"张口就记"的入口**——不用打字，**说一句话就能记一笔**：

1. **记账页「语音记账」入口真正可用**：打开「记账」Tab，点「🎤 语音记账」（现在还是"敬请期待"占位），弹出一个语音面板——**按住按钮说话**（比如"打车花了 20 块"），松手结束。说话时用的是 **iPhone 自己的语音识别**，**你的声音不会离开手机**。
2. **本机转文字 → 复用已有识别链路**：松手后，App 先在**本机**把你说的话转成文字，再把这段**文字**（只有文字，不含录音）交给 DeepSeek 解析出**金额、支出还是收入、时间、分类**，**直接记成一笔正式账单**——和 N03 文本识别走的是同一套"识别中 → 入账 → 结果卡片"。
3. **弹出结果卡片，可当场改**：入账后立刻弹出结果卡片（和文本识别一模一样的那张）——金额多少、归到哪类，还能展开看"识别到的原始语音文字"。识别得不对当场改；不想记点「删除这笔」（二次确认）撤销。改完剩余金额和统计（N02）立刻跟着变。
4. **第一次用会请求麦克风和语音识别权限**：首次进语音记账，系统会弹窗问你是否允许**麦克风**和**语音识别**。**同意**才能录音识别；**拒绝**也不会卡死——会给一句明确提示告诉你去哪打开，且**手动记账、文本识别照常用**。
5. **没配 DeepSeek Key 时给明确提示**：和文本识别一样，还没填 Key 就点语音记账，会先弹提示引导去填（复用 N03 已做好的拦截与 Key 填写入口）；没填 Key 不影响手动记账。

**这一节点不做什么**（都在后面节点）：截图/相册选图识别（N05）、快捷指令后台入账 + 通知（N06）；麦克风/语音/相册/通知权限的**统一收口与"我的页"设置**、首次引导（N07——本节点只做语音记账**自己必需**的那次权限申请与被拒提示）。DeepSeek 解析层、结果卡片、无 Key 拦截、Key 填写 sheet **已在 N03 做好，本节点直接复用、不重做**。

## 目标

1. **iOS Speech 本机语音转文字（M2.3 净新增）**：用 `SFSpeechRecognizer` + `AVAudioEngine` 实现"按住说话 → 录音 → 松手结束 → 转出中文文字"，**强制本机识别**（`requiresOnDeviceRecognition = true`）；识别器语言用中文（`zh-CN`）。**先检查 `supportsOnDeviceRecognition`**，本机中文识别不可用时降级/提示（见需求范围 §5），不静默失败。
2. **麦克风 + 语音识别权限申请与被拒降级（M2.3 净新增，本节点必需部分）**：首次进语音记账申请**麦克风**（`AVAudioSession.requestRecordPermission` / iOS17+ `AVAudioApplication.requestRecordPermission`）与**语音识别**（`SFSpeechRecognizer.requestAuthorization`）权限；任一被拒/受限，给**明确降级提示**（复用 N03 "前置 guard → 弹 alert 引导 → 主流程不受影响"范式，见涉及链路），并**不阻塞手动记账/文本识别**。新增 `NSMicrophoneUsageDescription` 与 `NSSpeechRecognitionUsageDescription`（项目走 `GENERATE_INFOPLIST_FILE`，无独立 .plist，见当前理解）。**权限的统一收口与"我的页"设置留 N07**；本节点只做语音记账自身必需的一次申请与被拒提示。
3. **转出文本复用 N03 解析入账链路（M2.3 复用，不重做）**：本机转出的文字 **喂给 `RecognitionEntry.recognizeAndSave`**（`TextRecognitionView.swift:16`），复用其"DeepSeek 解析 → 归一/兜底 → `createTransaction` 落库"整条链路。**账单来源须落 `TransactionSource.voice`**（枚举已存在 `Aubade/Models/Enums.swift:15`），原文 `rawText` 落转出的语音文字（对齐 demo `data.js:45` 带 `[语音转文字]` 语义前缀，具体前缀格式留 TRD）。⚠️ **接缝**：`recognizeAndSave` 现将 `source` 硬编码为 `.text`（`TextRecognitionView.swift:33`），需**参数化 `source`**（或语音走等价编排）以落 `.voice`——见需求范围 §3。
4. **复用结果卡片与失败转手动（M2.3 复用，不重做）**：识别成功 → 复用 `RecognitionResultCard`（`TextRecognitionView.swift:249`）弹结果卡片（完成回写/删除撤销二次确认/折叠原文）；无金额/网络失败/超时/非法响应 → 复用 N03 失败分支（保留原文、转手动、可重试）。**不新造结果卡片、不改其签名。**
5. **语音入口接线 + 语音状态机（M2.3 净新增接线）**：把 `RecordTabView` 四入口网格的「🎤 语音记账」（现为占位 `placeholderEntryTitle = "语音记账"`，`RecordTabView.swift:92`）接成真实入口，呈现语音面板；语音面板串起 **录音/识别本机转文字的状态**（空闲 → 录音中 → 本机转文字中 → 交给 `recognizeAndSave` 走 N03 识别中态 → 结果卡片 / 失败）。语音特有的空结果（没说话/没转出字）不当报错崩溃，给轻提示可重说（见 §5）。
6. **语音转文字 provider 可注入 + DEBUG mock（可测性，对齐 N03 注入范式）**：把"录音 → 本机转文字"抽成**可注入、脱 View 的 provider 协议 + 真实实现 + mock 实现**（对齐 `TransactionParsing` 协议 `:15` 与 `RecordTabView.textParser` `:32` 的注入范式）；在 `DebugMenuView`（`Aubade/Debug/DebugMenuView.swift`，仅 DEBUG）补一个**语音转文字 mock 开关**（模拟"成功转出'打车花了 20 块'/权限被拒/空结果/本机不可用"），使模拟器无需真麦克风也能肉眼走通语音 → 入账 → 结果卡片全路径。

## 当前理解

### N03 已交付、本节点直接复用的链路（本节点不重做、不改签名）

- **落库编排入口** `RecognitionEntry.recognizeAndSave(text:categories:parser:store:now:)`（`enum RecognitionEntry`，`Aubade/Features/Recognition/TextRecognitionView.swift:12-38`）：`@MainActor static`（`enum RecognitionEntry` 标 `@MainActor`），串 `parser.parse(text:categories:)` → `RecognitionNormalizer`（金额/时间/分类归一） → `store.createTransaction(...)`，返回落库后的 `Transaction`。注释明写"注入以便单测与 **N04~N06 复用**"——**语音把本机转出的文字当 `text` 传入即可**。⚠️ 但其 `store.createTransaction(... source: .text ...)` 的 `source` **当前硬编码 `.text`**（`TextRecognitionView.swift:33`），语音要落 `.voice` 须先参数化（见需求范围 §3）。
- **识别结果卡片** `RecognitionResultCard`（`TextRecognitionView.swift:249-279`）：输入 = **已入账的 `Transaction` + `categories`**（`:250-251`，即链路上位于"入账之后"），内部是 N01 `TransactionEditor(.edit)` 的薄封装，注入 `rawText` 渲染折叠原文；「完成」= `EditorActions.makeUpdate`（`Aubade/Features/Editor/EditorActions.swift:11`），「删除这笔」= `confirmationDialog` 二次确认 → `EditorActions.makeDelete`（`:26`）。**语音成功后与文本识别同样：先 `recognizeAndSave` 落库拿 tx，再拿 tx 弹此卡。**
- **识别状态机与错误** `RecognitionPhase`（`RecognitionState.swift:7-11`：idle/recognizing/failed）、`RecognitionError`（`RecognitionError.swift`，含无 Key/网络/超时/无金额/非法响应，`isRetryable` 决定是否给重试）、识别中全屏遮罩范式（`TextRecognitionView.swift:159-177`）——**"本机转出文字之后"的识别中态/失败态可 100% 复用**。
- **DeepSeek 解析层** 协议 `TransactionParsing`（`TransactionParsing.swift:15-19`）、真实 `DeepSeekClient`、mock `MockTransactionParser`（`MockTransactionParser.swift:6-39`，success 返定值）——语音复用同一 parser 注入，不新建解析层。
- **无 Key 拦截 + Key 填写** N03 已做（`TextRecognitionView.swift:184-187` 前置 guard `KeychainStore.shared.isConfigured` → alert「需要先配置 DeepSeek」`:121-126` → 最小 Key sheet）——语音入口**同样前置这套拦截**（对齐 demo `startEntry` `app.js:262`），复用不重做。
- **解析器注入范式** `RecordTabView.textParser`（`RecordTabView.swift:32-39`）：DEBUG 读 `@AppStorage(DebugMockSettings.behaviorKey)` 构造 `MockTransactionParser`、Release 走 `DeepSeekClient()`——语音的转文字 provider 建议照抄这套注入 + DEBUG mock 开关模式。

### 数据底座已就绪（N00 交付，本节点消费，无需改 Schema）

- **`TransactionSource.voice`** 枚举值**已存在**（`Aubade/Models/Enums.swift:15`），语音入账即用 `.voice`，无需新增枚举。
- **`LedgerStore.createTransaction(...)`**（`Aubade/Store/LedgerStore.swift:48-60`）已支持 `source:`/`rawText:` 入参，语音落库无需改签名——只需 `recognizeAndSave` 把 `.voice` 透传下去（§3 接缝）。
- 分类兜底/归一（`RecognitionNormalizer`、`PresetCategories`）N03 已实现，语音复用同一归一（"打车" → 分类"行"由 DeepSeek 分类名匹配 `LedgerCategory`，与文本同机制）。

### 权限与语音识别脚手架现状（N04 首次引入）

- **项目当前无任何 OS 权限申请代码**（`import Speech`/`SFSpeech`/`AVAudioSession`/`requestAccess`/`authoriz` 在 `Aubade/` 下零命中）——麦克风、语音识别授权与 Info.plist UsageDescription 都是**本节点首次引入**。可复用的只是 N03"无 Key 拦截"的 alert 交互**范式**（前置 guard → 弹 alert 引导 → 主流程不受影响），不是现成权限代码。
- **Info.plist 走 `GENERATE_INFOPLIST_FILE = YES`**（`Aubade.xcodeproj/project.pbxproj`，无独立 .plist，已有键以 `INFOPLIST_KEY_*` build setting 形式存在）——新增 `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription` 以 `INFOPLIST_KEY_*` build setting 或改自定义 Info.plist 方式落地（具体方式留 TRD）。
- **真实 iOS Speech 状态机（按住说话/松手结束/超时/空结果）在代码与原型里都不存在**——是本节点净新增；原型 demo 只到"本地转文字→DeepSeek"的**文案层**（`app.js:310` `openVoiceCapture` 是点一下模拟，非真实录音），且原型文档明确"真实语音识别不覆盖、demo 用假数据"（`docs/design/aubade-v1-prototype.md:31/:339`）。故**"按住说话 → 本机转文字"这段是真实新增，其后链路全复用 N03**。

### 可测性（对齐 N03/技术基线 §10 口径）

- 测试框架 **XCTest**（`AubadeTests/` 平铺，无 Swift Testing）；N03 已有 `RecognitionEntryTests`（编排入口 mock 注入落库断言）、`ResultCardActionsTests`（结果卡片动作脱 View 测）、`MockParserTests`。**语音复用 `recognizeAndSave`，`RecognitionEntryTests` 的断言范式可直接照搬**（补一条 `source=.voice` 落库断言）。
- 语音特有逻辑（转文字 provider 的成功/空结果/权限被拒/本机不可用分支、`source=.voice` 的编排）应抽成**脱 View 可注入单元**测试，脱离真麦克风与网络（用 mock provider + `PersistenceController.makeInMemoryContainer()`）。

## 涉及的现有链路

- **被扩展/接线**：
  - `RecordTabView` 「🎤 语音记账」入口（`RecordTabView.swift:92`，现 `placeholderEntryTitle` 占位）→ 触发真实语音面板；其余三入口（截图/文本/手动）与结构不动。
  - `RecognitionEntry.recognizeAndSave`（`TextRecognitionView.swift:16-38`）→ **参数化 `source`**（默认 `.text` 保持 N03 行为不变，语音传 `.voice`），是本节点唯一对 N03 已落地代码的签名级改动（§3）；归一/落库内部逻辑不动。
  - `DebugMenuView`（DEBUG）→ 新增语音转文字 mock 开关（其余不动）。
  - `Info.plist` 生成配置（pbxproj `INFOPLIST_KEY_*` 或自定义 plist）→ 新增麦克风/语音识别 UsageDescription。
- **被复用（只读消费，不改签名）**：
  - `RecognitionResultCard`（结果卡片）、`RecognitionPhase`/`RecognitionError`（状态机与错误）、识别中遮罩范式。
  - `TransactionParsing`/`DeepSeekClient`/`MockTransactionParser`（解析层）、`RecognitionNormalizer`（归一兜底）。
  - N03 无 Key 拦截 alert + 最小 Key 填写 sheet + `KeychainStore.isConfigured`。
  - `LedgerStore.createTransaction/updateTransaction/delete`、`PersistenceController.makeInMemoryContainer()`、`Transaction`/`LedgerCategory` 模型与 `TransactionSource.voice`。
- **本节点新增**：
  - **语音转文字 provider**（协议 + 真实 `SFSpeechRecognizer`/`AVAudioEngine` 实现 + mock 实现）：本机录音转中文文字、强制 on-device、check `supportsOnDeviceRecognition`。
  - **麦克风 + 语音识别权限申请与被拒降级**（本节点必需部分；统一收口留 N07）。
  - **语音面板 UI + 语音录音/转文字状态机**（按住说话/松手/录音中/转文字中/空结果，衔接 N03 识别中态）。
  - **`recognizeAndSave` 的 `source` 参数化**（使语音落 `.voice`）。
  - Info.plist 麦克风/语音识别 UsageDescription。
- **无既有调用方冲突**：语音 provider/面板/权限为全新代码；`recognizeAndSave` 参数化 `source` **给默认值 `.text`**，N03 现有调用方（`TextRecognitionView.recognize()` `:197`）行为不变；除给语音入口接线、`DebugMenuView` 补开关、加 UsageDescription 外，不改 N01/N02/N03 的模型字段、`LedgerStore`/`TransactionEditor`/`RecognitionResultCard` 签名与既有行为。

## 需求范围

### 1. 语音入口接线（M2.3，对齐 demo `openVoiceCapture`）
- 把 `RecordTabView` 「🎤 语音记账」入口（`:92` 占位）接成真实入口，呈现**语音面板**（sheet/cover 留 TRD）。
- 入口点击**先复用 N03 无 Key 拦截**（对齐 demo `startEntry` `app.js:262`：`needKeyBlocked` 语音同样拦截）——未配 Key 弹 N03 已有拦截 alert + 「去填写」开 N03 已有 Key sheet，不重做。
- 语音面板对齐 demo `openVoiceCapture`（`app.js:310`）：🎤 图标 + 「按住说话」按钮 + 示例提示「打车花了 20 块」。**真实交互是"按住录音、松手结束"**（原型是点一下模拟，真实实现为按住手势）。

### 2. iOS Speech 本机语音转文字（M2.3 净新增）
- **按住说话 → 录音 → 松手结束 → 本机转中文文字**：`SFSpeechRecognizer(locale: zh-CN)` + `AVAudioEngine` 采音；`SFSpeechAudioBufferRecognitionRequest.requiresOnDeviceRecognition = true`（**强制本机、语音不外传**）。
- **先检查 `supportsOnDeviceRecognition`**：本机中文识别不可用 → 降级提示（见 §5），不静默失败、不回退到需要联网的云端识别（隐私边界：语音不外传）。
- **最长录音时长 = 60s**（用户已拍板）：单次按住录音到 60s 自动结束并转文字，防超长录音/误触长按。是否展示实时转写、松手到出文字的处理细节 → **留 TRD**；PRD 约束"本机、可观察转出文字、不外传、≤60s 自动收尾"。

### 3. 转出文本入账（M2.3，复用 `recognizeAndSave` + `source` 参数化）
- 本机转出的文字 → 调 `RecognitionEntry.recognizeAndSave`（`TextRecognitionView.swift:16`），复用 DeepSeek 解析 → 归一 → 落库整条链路。
- **`recognizeAndSave` 参数化 `source`**：新增 `source` 入参**默认 `.text`**（N03 调用方行为不变），语音调用传 `.voice`。账单落 `TransactionSource.voice`（`Enums.swift:15`）。**`rawText` 加 `[语音转文字]` 前缀**（用户已拍板，对齐 demo `data.js:45` 的 raw 语义）——落库形如 `[语音转文字]\n"<口语原句>"`，供结果卡片折叠原文区标识来源与回溯；前缀确切格式（是否带引号包裹）留 TRD，但"带 `[语音转文字]` 前缀"已定。
- 空文本（没转出字）不进 `recognizeAndSave`，走 §5 空结果提示。

### 4. 识别成功/失败复用 N03（M2.3，不重做）
- **成功** → 复用 `RecognitionResultCard`（`TextRecognitionView.swift:249`）弹结果卡片：金额/方向/分类/时间/商户/备注 + 折叠原文（语音文字）+ 「完成」回写 / 「删除这笔」二次确认撤销。改删后列表/剩余/统计（N01/N02）自动刷新。
- **失败**（无金额/网络/超时/非法响应）→ 复用 N03 失败分支（`RecognitionError` 分支、保留原文、转手动、`isRetryable` 决定重试）。无金额场景保留转出的语音文字、可转手动填写。
- 不新造结果卡片/失败 UI，不改其签名。

### 5. 权限与语音特有降级（M2.3 净新增，本节点必需部分）
- **权限申请时机 = 首次"按下录音"时才申请**（用户已拍板）：麦克风（`AVAudioApplication.requestRecordPermission` / iOS17 前 `AVAudioSession.requestRecordPermission`）+ 语音识别（`SFSpeechRecognizer.requestAuthorization`）。**仅"看一眼语音面板"不弹权限**，用户真正按下录音键才触发系统授权弹窗（避免打扰、与 N07 首次引导集中申请不重复）。
- **被拒/受限降级**（复用 N03 alert 范式）：任一权限 denied/restricted → 明确提示（说明需要麦克风/语音识别权限、去"设置"开启的引导），**不崩溃、不卡死**，**手动记账/文本识别不受影响**。
- **本机识别不可用**（`supportsOnDeviceRecognition == false` 或识别器不可用）→ 提示"当前设备/语言暂不支持本机语音识别，可改用文本识别或手动记账"，不外传。
- **空结果**（授权成功但没说话/没转出字）→ 轻提示"没听清，请再说一次"，可重说，不报错、不误记。
- 新增 Info.plist `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription`（文案留 TRD，须说明用途=语音记账、本机识别）。
- **权限统一收口（我的页权限状态、首次引导集中申请、被拒后的统一设置引导）明确留 N07**；本节点只做语音记账自身跑通所必需的一次申请与被拒提示。

### 6. 语音转文字 provider 可注入 + DEBUG mock（可测性）
- 把"录音 → 本机转文字"抽成**可注入的 provider 协议 + 真实实现 + mock 实现**（对齐 `TransactionParsing`/`RecordTabView.textParser` 注入范式）。
- `DebugMenuView`（DEBUG）补**语音转文字 mock 开关**：模拟 成功转出「打车花了 20 块」/ 权限被拒 / 空结果 / 本机不可用，使模拟器无真麦克风也能肉眼走通语音 → 入账 → 结果卡片 / 各降级路径。
- ⚠️ **验收所需的解析定值需新增，不能直接复用 N03 的 `MockTransactionParser.success`**：N03 现有 `MockTransactionParser.success` 返回的是文本样例定值（256 / 京东商城 / 尾号 1234 / 分类"其他"，`MockTransactionParser.swift:28-36`），**不会**输出验收点 1 期望的 20 / 支出 / 分类"行"。要让"语音 mock 成功 → 金额 20 / 行"这条链路肉眼可观察，需为语音场景提供一份**独立的 mock 解析定值**（20 / 支出 / "行"，对齐 demo `data.js:45`）——具体是给 `MockTransactionParser` 增加语音样例 Behavior、还是语音 provider mock 直接产出可被现有 parser 解出的文本，留 TRD 定；但 PRD 层明确：**验收 1 的 20/行 来自 N04 新增的语音 mock 定值，不是 N03 现有 success 定值**。

### 7. 单元测试（对齐技术基线 §10、N03 范式）
- **`source=.voice` 落库**：以 mock 转文字 + mock parser 注入 `recognizeAndSave`，断言落库 `source=.voice`、`rawText` 保留语音文字、金额 `Decimal` 无浮点误差（照搬 `RecognitionEntryTests` 范式补一条）。
- **`recognizeAndSave` 参数化不回归**：默认 `source=.text` 时 N03 行为不变（补断言或复核既有 `RecognitionEntryTests`）。
- **语音 provider 分支**：mock provider 的 成功/空结果/权限被拒/本机不可用 各分支返回可区分、上层据此走对应路径（脱 View、脱真麦克风）。

## 不做什么

以下均属其他节点，本节点**不实现**：
- **截图·相册选图 + Vision OCR**（N05）；**快捷指令 App Intents 后台入账 + 通知**（N06）。本节点只做**语音**入口。
- **权限统一收口与设置界面**（N07）：我的页权限状态展示、首次启动引导里的集中权限申请、被拒后的统一"去设置"收口、麦克风/语音/相册/通知的统一策略——本节点只做语音记账**自身必需**的一次麦克风+语音识别申请与被拒降级提示。
- **重做 N03 已交付部分**：DeepSeek 解析层、归一/兜底、错误类型、结果卡片 `RecognitionResultCard`、无 Key 拦截、Key 填写 sheet、Keychain 封装——**全部复用，不重写、不改签名**（仅对 `recognizeAndSave` 做向后兼容的 `source` 参数化）。
- **真实 DeepSeek Key 联网端到端作为本节点门禁**：可观察验收以 **mock 转文字 + mock parser 注入端到端** + 单测为准（对齐 N03 已确认约定）；真实 Key + 真机真麦克风的端到端由用户后续自测，不阻塞节点完成。
- 不改 N00/N01/N02/N03 的模型字段、`LedgerStore`/`TransactionEditor`/`RecognitionResultCard` 签名与既有行为、N01 记账/账单/编辑、N02 统计/剩余、N03 文本识别既有行为。

## 验收标准

（对齐 DAG 中 N04 的"退出标准（可观察）"`:188` 与全局 PRD 验收点 3。可用模拟器 + DEBUG 语音 mock 开关注入肉眼观察，`source=.voice` 落库与 provider 分支另以单元测试佐证；真机真麦克风 + 真实 Key 端到端为用户后续自测。）

1. **语音入账（PRD 验收点 3，mock 注入观察）**：记账页点「🎤 语音记账」进入语音面板，（DEBUG 语音 mock = 成功）触发一次录音识别，本机转出「打车花了 20 块」→ 经识别中 → **直接生成一笔已入账账单**并弹结果卡片：金额=20（`Decimal` 无浮点误差）、方向=支出、分类="行"、**来源=语音（`TransactionSource.voice`）**、原文保留转出的语音文字。（此处 20/支出/"行" 由 **N04 新增的语音 mock 解析定值**产出，非 N03 现有 `MockTransactionParser.success` 的 256/京东定值，见需求范围 §6；mock 恒返回样例定值，验收链路与字段落库正确性；真实语音解析准确性由用户后续真机自测。）
2. **结果卡片可改/撤销（复用 N03）**：结果卡片可改金额/方向/分类/时间/商户/备注，「完成」后改动生效、统计与剩余（N02）自动刷新；「删除这笔」二次确认后撤销入账、列表/剩余/统计同步。
3. **识别原文可见**：结果卡片可展开查看"识别到的原始语音文字"（`rawText`）。
4. **权限被拒降级（本节点必需部分）**：（DEBUG 语音 mock = 权限被拒，或真机拒绝授权）点语音记账时给**明确降级提示**（说明需要麦克风/语音识别权限），**不崩溃、不卡死**，且**手动记账、文本识别照常可用**。
5. **本机识别不可用降级**：（DEBUG mock = 本机不可用）给明确提示可改用文本/手动，不静默失败、不外传语音。
6. **空结果不误记**：（DEBUG mock = 空结果，或真机不说话松手）给"没听清、请再说一次"轻提示，**不报错、不生成脏账单**，可重说。
7. **无 Key 拦截（复用 N03）**：Keychain 无 Key 时点语音记账，先弹 N03 已有拦截提示且不进行识别；「去填写」进入 N03 已有 Key sheet；全程手动记账不受影响。
8. **隐私边界（PRD 业务规则 12）**：语音转文字用 `SFSpeechRecognizer` 且 `requiresOnDeviceRecognition = true`（**本机识别、语音不外传**）；只有转出的**文本**经 N03 链路发 DeepSeek；无录音上传、无图片。
9. **`source=.voice` 与向后兼容单测**：单测覆盖——语音经 `recognizeAndSave` 落库 `source=.voice`、`rawText` 保留、金额 Decimal 无误差；`recognizeAndSave` 默认 `source=.text` 时 N03 行为不回归；语音 provider 成功/空/被拒/本机不可用分支可区分；均 mock 注入、脱真麦克风与网络。
10. **不越界**：无截图/相册入口；不做权限统一收口/我的页设置/首次引导（留 N07）；不重写 N03 解析层/结果卡片/Key 相关；不改 N01/N02/N03 既有行为（`recognizeAndSave` 仅做带默认值的 `source` 参数化）。

## 已确认约定

（以下由上游 PRD/原型 demo/技术基线/DAG 定死或由 N03 既有实现约束，作为既定实现约束，非待确认项。TRD 直接据此落地。）

1. **语音转文字 = iOS Speech 本机、强制 on-device、不外传**（全局 PRD 业务规则 12、DAG N04 范围 `:187`）：`requiresOnDeviceRecognition = true`，先 check `supportsOnDeviceRecognition`，中文本机不可用则降级/提示，不回退云端。
2. **转出文本后的链路 100% 复用 N03**（DAG N04 "复用 N03 解析链路与结果卡片"）：不重写解析层、结果卡片、无 Key 拦截、Key sheet；语音只新增"按住说话 → 本机转文字"这段前置。
3. **账单来源落 `.voice`**（全局 PRD 来源字段 `:78`、`Enums.swift:15` 已有枚举）：语音入账 `source=.voice`；为此对 `recognizeAndSave` 做**向后兼容的 `source` 参数化**（默认 `.text`），是本节点唯一对 N03 已落地代码的签名改动。
4. **语音 UI 形态以 demo 为准**（`app.js:310` `openVoiceCapture`、`data.js:45`）：🎤 面板 + 「按住说话」+ 示例「打车花了 20 块」+ 复用结果卡片；**真实交互为"按住录音、松手结束"**（原型点一下是模拟）。识别中/成功/失败复用 N03 视觉。
5. **权限收口切分：N04 只做自身必需的申请 + 被拒降级，统一收口留 N07**（DAG N07 范围 `:227` 明列"麦克风/语音/… 权限申请时机与被拒降级的统一收口"）：本节点不做我的页权限状态、首次引导集中申请，只保证语音记账自己能申请到权限、被拒有明确降级且不卡死主流程。
6. **验收深度 = mock 端到端 + 单测**（对齐 N03 已确认约定）：DEBUG 语音 mock 开关 + mock parser 注入下语音链路完整跑通 + `source=.voice`/provider 分支单测为准；真机真麦克风 + 真实 Key 端到端为用户后续自测，不阻塞节点完成。
7. **Info.plist 走 `GENERATE_INFOPLIST_FILE`**（`project.pbxproj` 现状）：麦克风/语音识别 UsageDescription 以 `INFOPLIST_KEY_*` build setting 或改自定义 Info.plist 落地（方式留 TRD），文案须说明用途与本机识别。
8. **语音转文字 provider 协议抽象 + mock 注入**（对齐 N03 `TransactionParsing` 注入范式与技术基线 §10 可测口径）：录音转文字抽成可注入、脱 View 单元，DEBUG mock 支撑无真麦克风肉眼验收与单测。
9. **权限申请时机 = 首次"按下录音"时**（用户已拍板）：进语音面板不弹权限，用户按下录音键才触发麦克风+语音识别授权弹窗；避免打扰、与 N07 首次引导集中申请不重复。
10. **最长录音时长 = 60s**（用户已拍板）：单次按住录音达 60s 自动结束并转文字，防超长/误触长按。
11. **`rawText` 加 `[语音转文字]` 前缀**（用户已拍板）：语音入账原文落库带 `[语音转文字]` 前缀（对齐 demo `data.js:45`），标识来源、供结果卡片折叠原文回溯；确切格式（引号包裹与否）留 TRD。

