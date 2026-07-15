# TRD 03 - 语音面板 UI + 状态机 + 入口接线 + 结果卡片复用 + DEBUG mock

## 给用户看的摘要

这一片把前两片的能力**接成用户真正能点、能用的语音记账**:

1. 记账页那个"🎤 语音记账"按钮(现在点了弹"敬请期待")变成**真入口**:点它先跟文本识别一样检查有没有配 DeepSeek Key,没配就引导去填;配了就弹出**语音面板**。
2. 语音面板对齐原型:大麦克风图标 + 「按住说话」按钮 + 示例「打车花了 20 块」。**按住录音、松手结束**,最长 60 秒;录音中、转文字中都有清楚的状态显示。
3. 转出文字后,**完全复用 N03 文本识别那一整套**:识别中转圈 → 直接记成一笔账 → 弹出结果卡片(金额/分类/时间可当场改、可删除撤销、可展开看原始语音文字);识别失败也复用 N03 的转手动/重试。账单来源记为"语音"、原文带 `[语音转文字]` 前缀。
4. 权限被拒、本机不支持、没说话,分别给明确提示,不崩溃;手动记账、文本识别不受影响。
5. 调试菜单加一个**语音 mock 开关**(成功/空结果/权限被拒/本机不可用),让模拟器没有麦克风也能肉眼走通整条链路。

做完这片,N04 语音记账在模拟器上(mock 注入)可完整验收:说一句 → 记成金额 20、分类"行"、来源语音的账单。

## 本 TRD 负责什么

单一职责:**语音入口接线 + 语音面板 UI + 录音/转文字状态机 + 复用 N03 成功/失败态 + DEBUG 语音 mock 开关**。

- `RecordTabView` 「🎤 语音记账」入口(`:92` 占位)→ 真实语音面板,前置复用 N03 无 Key 拦截。
- 新增语音面板 `VoiceCaptureView`:按住说话手势 + 录音中/转文字中状态 + 空结果/被拒/不可用降级提示。
- 转出文本 → 复用 N03 成功/失败/结果卡片(经扩展 `TextRecognitionView` 支持预置文本自动识别,避开 `RecognitionResultCard` 是 private 的接缝)。
- `RecordTabView` 注入 voice provider(DEBUG→`MockVoiceTranscriber`、Release→`SpeechVoiceTranscriber`,对齐 `textParser` 范式);语音场景解析注入 `.voiceSample`。
- `DebugMenuView` 补语音 mock 行为开关。

## 当前代码事实与上下游

- **入口网格** `RecordTabView.entryGrid`（`Aubade/Features/Record/RecordTabView.swift:89-96`）:`:92` `EntryButton(emoji:"🎤", title:"语音记账"){ placeholderEntryTitle = "语音记账" }`——本片把 action 换成呈现语音面板。四入口其余三个(`:91/93/94`)不动。
- **无 Key 拦截现状**:在 `TextRecognitionView.recognize()` **页内**（`TextRecognitionView.swift:184-187` `guard KeychainStore.shared.isConfigured`），文本识别是"先进页、点识别才拦截"。语音需在**进面板前或按录音前**拦截(对齐 demo `startEntry` `app.js:262`)——`KeychainStore.shared.isConfigured`（`Aubade/Persistence/KeychainStore.swift:54`）可直接读。
- **结果卡片是 private** `RecognitionResultCard`（`TextRecognitionView.swift:249` `private struct`）——**跨文件不可直接实例化**。这是本片核心接缝(见设计方案 §3)。
- **N03 成功/失败态** 都在 `TextRecognitionView` 内:成功 `resultTx` 弹卡（`:143-145/197`）、失败 alert 转手动/重试（`:128-136`）、识别中遮罩（`:159-177`）。语音要 100% 复用这套,最省的方式是**复用整个 `TextRecognitionView`**,而非把卡片提 public。
- **`recognizeAndSave` 已参数化**（切片 01）:`source: = .text`、`rawText: = nil`。语音传 `.voice` + 带前缀 rawText。
- **provider 注入范式** `RecordTabView.textParser`（`:32-39`）+ `@AppStorage(DebugMockSettings.behaviorKey)`（`:27`，`DebugMockSettings.behaviorKey` 定义于 `Aubade/Debug/DebugMenuView.swift:8`）。语音照抄:加 `voiceTranscriber` 计算属性 + 语音专属 mock key。
- **DebugMenu mock picker**（`DebugMenuView.swift:71-77`）:N03 文本 mock 的 Picker。本片在同一 `DebugMenuView` 补语音 provider mock Picker。
- **切片 01/02 交付**:`VoiceTranscribing`/`VoiceTranscribeError`/`MockVoiceTranscriber`（Behavior 五态）/`SpeechVoiceTranscriber`/`MockTransactionParser.voiceSample`。

## 设计方案

### 1. 入口接线 + 无 Key 拦截（改 `RecordTabView.swift`）

`:92` 语音入口 action 改为:先查 Key,无 Key 复用 N03 拦截 alert（`RecordTabView` 现无此 alert，需新增一份等价的，文案同 `TextRecognitionView.swift:121-126`），有 Key 呈现语音面板：

```swift
// state 新增
@State private var voiceRoute: VoiceRoute?       // 单一 fullScreenCover 驱动（见下"呈现驱动"）
@State private var showVoiceKeyBlockedAlert = false
@State private var showingKeySheet = false

// entryGrid :92
EntryButton(emoji: "🎤", title: "语音记账") {
    if KeychainStore.shared.isConfigured {
        voiceRoute = .panel                 // 有 Key → 呈现语音面板
    } else {
        showVoiceKeyBlockedAlert = true     // 无 Key 拦截（对齐 demo startEntry）
    }
}
```

无 Key alert「去填写」→ `showingKeySheet = true` → `.sheet { KeySetupSheet() }`（`KeySetupSheet` 是 internal，`Aubade/Features/Recognition/KeySetupSheet.swift:6`，可直接复用）。

**呈现驱动 = 单一 `.fullScreenCover(item:)` enum route(避坑)**:语音面板与"成功后复用的文本识别页"是**先后两个全屏页**,不可用两个独立 `.fullScreenCover(isPresented:)`——同一事件里关一个(`showingVoiceCapture=false`)、开另一个(`showingTextRecognition=true`),SwiftUI 同一时刻只允许一个 presentation,第二个常常不弹(会卡住验收 1)。改用**单一 `.fullScreenCover(item: $voiceRoute)`** + enum route 驱动:

```swift
enum VoiceRoute: Identifiable { case panel; case recognizing(spoken: String); var id: String { ... } }
@State private var voiceRoute: VoiceRoute?
// 点🎤(有 Key) → voiceRoute = .panel
// 面板成功回调 → voiceRoute = .recognizing(spoken:)   // 同一 cover 换 item，SwiftUI 平滑切内容
// .fullScreenCover(item: $voiceRoute) { route in switch route { case .panel: VoiceCaptureView(...); case .recognizing(let s): TextRecognitionView(..., presetText: s, source: .voice, rawTextOverride:...) } }
```

`item:` 换值时 SwiftUI 在**同一** presentation 内切换内容,避免"关一个开一个"的时序竞态。文本识别页的结果卡片关闭 → `voiceRoute = nil` 回记账页。

### 2. 语音面板 `VoiceCaptureView`（新增 `Aubade/Features/Recognition/Voice/VoiceCaptureView.swift`）

对齐 demo `openVoiceCapture`（`prototype/app/app.js:310-320`）:🎤 图标 + 「按住说话」+ 示例「打车花了 20 块」。真实交互=按住录音、松手结束。

**语音面板局部状态机**（视图 `@State`，不引框架，对齐 `RecognitionPhase` 风格）:

```swift
enum VoicePhase: Equatable {
    case idle            // 待按住
    case recording       // 按住录音中（显示"正在聆听…松手结束" + 可选计时到 60s）
    case transcribing    // 松手后本机转文字中
    case failed(VoiceTranscribeError)   // 权限被拒/本机不可用/空结果 → 对应提示
    // 成功 → 不在本机停留：转出文本交给 TextRecognitionView 复用 N03 识别中→结果卡片
}
```

流程:
- **按下**（`DragGesture(minimumDistance: 0).onChanged` 首次）→ `phase = .recording`，`Task { try await transcriber.start() }`;`start()` 抛权限/不可用错 → `phase = .failed(err)`。
- **松手**（`.onEnded`）→ `phase = .transcribing`，`Task { let text = try await transcriber.finish() }`;`.empty` → `phase = .failed(.empty)`;成功 → **回调把纯口语文本抛给上层**（见 §3）。
- **60s 自动收尾**:provider 到点已停采音（切片 02）;面板用一个 60s 计时(`Timer`/`Task.sleep`)在 UI 到点自动触发与"松手"等价的 `finish()` 流转,避免用户一直按不松。
- **`.failed` 分支文案**(对齐 PRD §5/验收 4/5/6):
  - `microphoneDenied`/`speechDenied` → "需要麦克风和语音识别权限。请到 设置 开启后再试;手动记账、文本识别不受影响。"
  - `onDeviceUnavailable` → "当前设备/语言暂不支持本机语音识别,可改用文本识别或手动记账。"
  - `empty` → "没听清,请再说一次。"(可重按录音,不报错、不记账)
  - `failed` → "录音出错了,请重试。"
- 面板 `cancel`(取消按钮/下滑关闭)→ `transcriber.cancel()`，丢弃录音。

### 3. 复用 N03 成功/失败态（核心接缝：扩展 `TextRecognitionView`，不提升 private 卡片）

**问题**:`RecognitionResultCard` 是 `TextRecognitionView.swift` 内 `private struct`（`:249`），语音面板无法直接弹它;N03 失败转手动/重试逻辑也都在 `TextRecognitionView` 内。

**方案**:给 `TextRecognitionView` 增加"**预置文本 + 进入即自动识别 + source/rawText**"能力,语音转出文本后**呈现一个预置好文本的 `TextRecognitionView`**,由它复用既有识别中→入账→结果卡片/失败全套。零改结果卡片可见性、零重写失败分支。

`TextRecognitionView` 新增带默认值的可选入参（向后兼容，N03 现有 `RecordTabView.swift:71` 调用不变）:

```swift
struct TextRecognitionView: View {
    let parser: TransactionParsing
    let categories: [LedgerCategory]
    var presetText: String? = nil          // 新增：非 nil 时进入即填入并自动识别（语音用）
    var source: TransactionSource = .text  // 新增：落库来源
    var rawTextOverride: String? = nil     // 新增：落库原文（语音带 [语音转文字] 前缀）
    // ...
    // .onAppear：presetText 非 nil → text = presetText; 自动触发 recognize()
    // recognize() 内 recognizeAndSave 调用改为传 source: source, rawText: rawTextOverride
}
```

- `recognize()`（`:193-195`）调用 `recognizeAndSave` 时传入 `source`/`rawTextOverride`(切片 01 已支持这两个参数)。**默认值保证 N03 文本识别行为不变**。
- **自动识别防重入**:`onAppear` 触发 `recognize()` 前置 `@State hasAutoRecognized` 标志(`recognize()` 内已有 `phase != .recognizing` 防护,再加此标志防 onAppear 多次触发重复识别);`recognize()` 直接读 `presetText ?? trimmed`,不依赖"写 `text` 后同步读"。
- 语音成功链路:`VoiceCaptureView` 转出纯口语 `spoken` → 成功回调置 `voiceRoute = .recognizing(spoken:)`(同一 `fullScreenCover` 换 item)→ 呈现 `TextRecognitionView(parser: 语音专属parser, categories:, presetText: spoken, source: .voice, rawTextOverride: "[语音转文字]\n\"\(spoken)\"")` → 该页 `onAppear` 自动识别 → 复用识别中遮罩 → 入账 `source=.voice` → 弹 `RecognitionResultCard`(N03 原样) → 折叠原文显示带前缀 rawText → 结果卡片关闭 → `voiceRoute = nil` 回记账页。
- **rawText 前缀**（PRD 已确认约定 11）:格式 `[语音转文字]\n"打车花了 20 块"`(前缀 + 换行 + 引号包裹口语),对齐 demo `data.js:45`。parse 收纯口语 `spoken`(不含前缀),落库 rawText 用带前缀串——切片 01 的 `rawText ?? text` 正好支持二者分离。

> **接线选择记录**:让语音"转出文本 → 复用 `TextRecognitionView`"而非"提升 `RecognitionResultCard` 为 public 各自弹卡",是为**最大化复用 N03、零改其结构与失败分支**。代价是语音成功后经历一次"语音面板 dismiss → 文本识别页(自动识别遮罩)"的转场;视觉上仍是"识别中→结果卡片",对齐原型 `recognizeFlow`(demo 亦是语音入口走同一 recognizeFlow)。

### 4. provider 注入（改 `RecordTabView.swift`，对齐 textParser 范式）

```swift
#if DEBUG
@AppStorage(DebugVoiceMockSettings.behaviorKey) private var voiceMockRaw = MockVoiceTranscriber.Behavior.success.rawValue
#endif

private func makeVoiceTranscriber() -> any VoiceTranscribing {
    #if DEBUG
    let behavior = MockVoiceTranscriber.Behavior(rawValue: voiceMockRaw) ?? .success
    let m = MockVoiceTranscriber(); m.behavior = behavior; return m
    #else
    return SpeechVoiceTranscriber()
    #endif
}

// 语音场景的解析器：DEBUG 固定注入 .voiceSample（20/行），Release 走 DeepSeekClient
private var voiceParser: TransactionParsing {
    #if DEBUG
    return MockTransactionParser(behavior: .voiceSample)
    #else
    return DeepSeekClient()
    #endif
}
```

- 语音 DEBUG 解析固定 `.voiceSample`,与文本 DEBUG 的 `textParser`(读 `@AppStorage`,默认 `.success`=256/京东)**分开**,互不污染(PRD §6)。
- `VoiceCaptureView` 接收注入的 `transcriber`;成功回调把 `spoken` 交回 `RecordTabView` 驱动 §3 转场。

### 5. DEBUG 语音 mock 开关（改 `DebugMenuView.swift`）

新增设置键 + Picker（与 N03 文本 mock Picker `:71-77` 并列一个 Section）:

```swift
enum DebugVoiceMockSettings { static let behaviorKey = "debug.voiceMockBehavior" }
// DebugMenuView 内新增：
@AppStorage(DebugVoiceMockSettings.behaviorKey) private var voiceMockRaw = MockVoiceTranscriber.Behavior.success.rawValue
// Section("N04 调试（语音 mock）") { Picker(...) { 成功/空结果/麦克风被拒/语音被拒/本机不可用 } }
```

模拟器无真麦克风:选"成功"→ 走通语音→入账→结果卡片(20/行/语音);选降级项→观察对应提示不崩溃。

## 修改点

| 文件 | 改动 | 类型 |
|---|---|---|
| `Aubade/Features/Recognition/Voice/VoiceCaptureView.swift` | 新增：语音面板 + `VoicePhase` 状态机 + 按住手势 + 降级提示 | 新增文件 |
| `Aubade/Features/Record/RecordTabView.swift` | `:92` 语音入口接线（无 Key 拦截 → 面板）；新增 voice provider/voiceParser 注入 + 无 Key alert + Key sheet + 成功转场 `TextRecognitionView` | 接线扩展 |
| `Aubade/Features/Recognition/TextRecognitionView.swift` | `TextRecognitionView` 加 `presetText`/`source`/`rawTextOverride`（默认值向后兼容）；`onAppear` 自动识别；`recognize()` 传 source/rawText | 扩展(向后兼容) |
| `Aubade/Debug/DebugMenuView.swift` | 新增 `DebugVoiceMockSettings` + 语音 mock Picker Section | DEBUG 扩展 |

（本项目 `Aubade/` 为 Xcode 16 同步文件夹 `PBXFileSystemSynchronizedRootGroup`，新增 `.swift` 文件放进目录**自动纳入 target，无需手改 pbxproj**；本片无工程文件改动。）

（本片以 UI/接线为主,自动化验收靠 DEBUG mock 端到端肉眼观察 + 切片 01 单测覆盖 `source=.voice`/provider 分支;不新增脱 View 单测——UI 状态机与转场在模拟器 mock 下人工走查,对齐 PRD 已确认约定 6。）

## 验证点

（模拟器 + DEBUG 语音 mock 注入，对齐 PRD 验收 1-8）

- **验收 1 语音入账**:记账页点🎤 →(有 Key)语音面板 → 按住松手(mock=成功)→ 转场识别中 → 弹结果卡片:金额 20(Decimal 无误差)、支出、分类"行"、来源语音、原文=`[语音转文字]\n"打车花了 20 块"`。
- **验收 2/3 结果卡片**:可改金额/方向/分类/时间,「完成」后统计与剩余(N02)刷新;「删除这笔」二次确认撤销同步;可展开看原始语音文字。
- **验收 4 权限被拒**:(mock=麦克风被拒/语音被拒)按录音给明确降级提示,不崩溃;返回后手动记账、文本识别照常。
- **验收 5 本机不可用**:(mock=本机不可用)明确提示可改文本/手动,不静默失败。
- **验收 6 空结果**:(mock=空结果)"没听清,请再说一次"轻提示,不报错、不生成账单,可重按。
- **验收 7 无 Key 拦截**:清除 Key → 点🎤 先弹拦截提示、不进面板;「去填写」进 Key sheet;手动记账不受影响。
- **验收 8 隐私**:Release provider 用 `requiresOnDeviceRecognition=true`(切片 02);无 Key 拦截、mock 路径不发网络。
- **N03 不回归**:文本识别入口(📋)行为不变(presetText=nil、source 默认 .text);`RecordTabView` 文本 mock Picker 仍走 `.success`。

## 不做什么

- **不提升 `RecognitionResultCard` 可见性、不重写 N03 失败分支**:经扩展 `TextRecognitionView`(预置文本自动识别)复用整套,零改其结构。
- **不做真机录音链路**（真实 provider 已在切片 02；本片模拟器走 mock）。
- **不做实时转写 UI**（partial results）：面板只有 录音中 / 转文字中 两态，最终文本出后转场。
- **不做权限统一收口 / 我的页权限状态 / 首次引导**（N07）。
- **不做截图/相册入口**（N05）：📷 入口保持占位不动。
- **不改 N01/N02 行为、`RecognitionResultCard`/`TransactionEditor`/`LedgerStore` 签名**;文本识别 DEBUG mock 仍 `.success`（256/京东），语音专用 `.voiceSample`（20/行）。
