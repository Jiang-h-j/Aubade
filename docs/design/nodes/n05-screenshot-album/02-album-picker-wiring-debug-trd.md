# TRD 02 - 相册选图 + 说明卡 + 入口接线 + 状态机 + DEBUG mock

## 给用户看的摘要

这一片把切片 01 的"图片转文字"能力**接成用户真正能点、能用的截图记账**：

1. 记账页那个「📷 截图识别」按钮（现在点了弹"敬请期待"）变成**真入口**：点它先跟语音/文本一样检查有没有配 DeepSeek Key，没配就引导去填；配了就弹出一张**说明卡**。
2. 说明卡对齐原型：先讲清楚"截图记账的**主用法**是 iOS 快捷指令随手一截、后台自动入账"（那条主链路在下个节点 N06 做），给两步设置指引；卡片下方有一个**「🖼 从相册选一张图识别」**按钮——这是本节点做的**备选入口**；还有一个「演示：模拟快捷指令截图」按钮，点它弹"敬请期待"占位（属于 N06）。
3. 点「从相册选图」→ 弹系统相册选一张付款截图 → App 在**本机**把图里的字读出来（**图片不离开手机**）→ 完全复用 N03/N04 那一整套：识别中转圈 → 直接记成一笔账 → 弹出结果卡片（金额/分类可当场改、可删除撤销、可展开看识别出的原文）。账单来源记为"截图相册"、原文带 `[截图识别]` 前缀。
4. 选图时用的是 iOS 的**免授权**选图器（选完只把那一张图交给 App），所以**不会弹相册权限申请**；没读出字、这张图识别失败，都给明确提示、不崩溃、不误记，可重选。
5. 调试菜单加一个**截图 mock 开关**（成功/空结果/OCR 失败），让模拟器不用真图片也能肉眼走通整条链路。

做完这片，N05 截图·相册选图在模拟器上（mock 注入）可完整验收：选一张图 → 记成金额 88.5、分类"食"、商户星巴克、来源截图相册的账单。

## 本 TRD 负责什么

单一职责：**截图入口接线 + 说明卡 UI + PhotosPicker 选图 + OCR 状态机 + 复用 N03 成功/失败态 + DEBUG 截图 mock 开关**。

- `RecordTabView` 「📷 截图识别」入口（`:167` 占位）→ 真实说明卡，前置复用 N03 无 Key 拦截。
- 新增截图说明卡 `ScreenshotIntakeSheet`：快捷指令主入口讲解 + 两步指引 +「从相册选图」+「演示」占位按钮。
- `PhotosPicker` 选图 → 切片 01 OCR provider 出文本 → 复用 N03 成功/失败/结果卡片（经 `TextRecognitionView` 预置文本自动识别，照抄 N04 `VoiceRoute` 单一 `fullScreenCover(item:)`）。
- `RecordTabView` 注入 OCR provider（DEBUG→`MockTextRecognizer`、Release→`VisionTextRecognizer`，对齐 `makeVoiceTranscriber()` 范式）；截图场景解析注入 `.screenshotSample`。
- `DebugMenuView` 补截图 mock 行为开关。

## 当前代码事实与上下游

- **入口网格** `RecordTabView.entryGrid`（`Aubade/Features/Record/RecordTabView.swift:165-179`）：`:167` `EntryButton(emoji:"📷", title:"截图识别"){ placeholderEntryTitle = "截图识别" }`——本片把 action 换成呈现说明卡。其余三入口（语音🎤`:168`/文本📋`:176`/手动✏️`:177`）不动。
- **N04 已落地的单一 `fullScreenCover(item:)` 路由范式** `VoiceRoute`（`RecordTabView.swift:7-16`）+ 驱动（`:122-138`）：`.panel → .recognizing(spoken:)` 换 item 在同一 presentation 平滑切"面板 → 复用识别页"，规避两个 `fullScreenCover(isPresented:)` 同帧关一个开一个的 SwiftUI 竞态。**N05 相册流程照此新增一个 `ScreenshotRoute`**。
- **N04 无 Key 拦截现状**（`RecordTabView.swift:168-175`）：语音入口 action 先 `if KeychainStore.shared.isConfigured { voiceRoute = .panel } else { showVoiceKeyBlockedAlert = true }`；无 Key alert（`:151-156`）+「去填写」→ `showingVoiceKeySheet`（`:157-159`）开 `KeySetupSheet`。**截图入口照此模式新增一份等价拦截**（文案改"截图记账"）。
- **N04 provider 注入范式**（`RecordTabView.swift:60-70`）：`makeVoiceTranscriber()` DEBUG 读 `@AppStorage(DebugVoiceMockSettings.behaviorKey)` 构造 mock、Release 走真实；`voiceParser`（`:74-80`）DEBUG 固定 `.voiceSample`、Release 走 `DeepSeekClient`；`voiceRawText(spoken:)`（`:84-86`）拼 `[语音转文字]` 前缀。**OCR provider/screenshotParser/screenshotRawText 照抄这三个**。
- **`.recognizing` 复用识别页范式**（`RecordTabView.swift:128-137`）：`TextRecognitionView(parser: voiceParser, categories:, presetText: spoken, source: .voice, rawTextOverride: voiceRawText(...))`——预置文本进页 `onAppear` 自动识别（`TextRecognitionView.swift:165-170`）→ 复用识别中遮罩/入账/结果卡片/失败态。**N05 换 `source: .screenshotAlbum` + 截图前缀即复用整套**。
- **结果卡片是 private** `RecognitionResultCard`（`TextRecognitionView.swift:268` `private struct`）——跨文件不可直接实例化。**N04 已用"经 `TextRecognitionView` 预置文本复用整页"绕开，N05 照抄，不提升可见性**。
- **DEBUG mock 设置范式** `DebugVoiceMockSettings`（`Aubade/Debug/DebugMenuView.swift:13-15`）+ 语音 mock Picker Section（`:88-98`）。**照此新增 `DebugScreenshotMockSettings` + 截图 mock Picker Section**。
- **"敬请期待"占位 alert 范式**（`RecordTabView.swift:142-149`）：`placeholderEntryTitle` 非 nil 弹"XX将在后续版本提供"。**「演示」按钮复用这套**（弹"快捷指令后台入账将在后续版本提供"或等价）。
- **切片 01 交付**：`TextRecognizing`/`TextRecognizeError`（empty/failed）/`MockTextRecognizer`（三态）/`VisionTextRecognizer`/`MockTransactionParser.screenshotSample`。
- **PhotosPicker 事实**：`PhotosUI` 的 `PhotosPicker` 是**内嵌视图组件**（非独立 present 的页面），绑定 `@State selection: PhotosPickerItem?`，选中经 `.onChange` + `item.loadTransferable(type: Data.self)` 拿图片 `Data`。**免相册授权**（选图器独立进程，只交回选中图）。

## 设计方案

### 1. 入口接线 + 无 Key 拦截（改 `RecordTabView.swift`，照抄 N04 语音入口）

`:167` 截图入口 action 改为：先查 Key，无 Key 复用拦截 alert，有 Key 呈现说明卡：

```swift
// state 新增（与语音的 voiceRoute/showVoiceKeyBlockedAlert/showingVoiceKeySheet 并列）
@State private var screenshotRoute: ScreenshotRoute?     // 单一 fullScreenCover 驱动（说明卡 → 复用识别页）
@State private var showScreenshotKeyBlockedAlert = false
@State private var showingScreenshotKeySheet = false

// entryGrid :167
EntryButton(emoji: "📷", title: "截图识别") {
    if KeychainStore.shared.isConfigured {
        screenshotRoute = .intro                 // 有 Key → 呈现说明卡
    } else {
        showScreenshotKeyBlockedAlert = true     // 无 Key 拦截（对齐 demo openScreenshotSheet 前的 needKeyBlocked）
    }
}
```

> **无 Key 拦截时机**：对齐 demo——demo 里说明卡本身不拦截，`#ss-album`/`#ss-demo` 点击才 `needKeyBlocked()`（`app.js:282`）。但 N04 语音是"进面板前拦截"。**本片取"进说明卡前拦截"**（点📷即查 Key），理由：说明卡的核心可用按钮是「从相册选图」，无 Key 时整卡无意义，进卡前拦截体验更直接、与 N04 入口一致；demo 的"卡内再拦截"是纯前端演示差异，不构成约束。

无 Key alert「去填写」→ `showingScreenshotKeySheet = true` → `.sheet { KeySetupSheet() }`（`KeySetupSheet` internal，可直接复用）。

### 2. 单一 `fullScreenCover(item:)` 路由（照抄 `VoiceRoute` 避坑范式）

说明卡与"成功后复用的识别页"是**先后两个全屏页**，照抄 N04 单一 cover + enum route（不可用两个独立 `.fullScreenCover(isPresented:)`，避免关一个开一个的时序竞态）：

```swift
/// 截图入口单一 fullScreenCover 驱动（照抄 VoiceRoute 避坑范式，RecordTabView.swift:7-16）：
/// 说明卡与"OCR 出文本后复用的识别页"是先后两个全屏页，换 item 在同一 presentation 平滑切内容。
enum ScreenshotRoute: Identifiable {
    case intro                          // 截图识别说明卡（快捷指令讲解 + 相册选图）
    case recognizing(ocrText: String)   // OCR 出文本 → 复用 TextRecognitionView 自动识别 → 结果卡片
    var id: String {
        switch self {
        case .intro:                  return "intro"
        case .recognizing(let t):     return "recognizing:\(t)"
        }
    }
}

.fullScreenCover(item: $screenshotRoute) { route in
    switch route {
    case .intro:
        ScreenshotIntakeSheet(
            recognizer: makeTextRecognizer(),        // 注入 OCR provider（见 §4）
            onRecognized: { ocrText in
                screenshotRoute = .recognizing(ocrText: ocrText)   // OCR 出文本 → 切复用识别页
            })
        // 「演示」占位提示由说明卡内部自持（showDemoPlaceholder + .alert，见 §3），不经外层 placeholderEntryTitle
    case .recognizing(let ocrText):
        // 复用 N03 整套：预置 OCR 文本自动识别 → 识别中遮罩 → 入账(source=.screenshotAlbum) → 结果卡片/失败转手动。
        // 结果卡片关闭时 TextRecognitionView 调 dismiss()，fullScreenCover 随 item 归 nil 回记账页。
        TextRecognitionView(
            parser: screenshotParser,
            categories: categories,
            presetText: ocrText,
            source: .screenshotAlbum,
            rawTextOverride: screenshotRawText(ocrText: ocrText))
    }
}
```

> **「演示」按钮占位提示自洽在说明卡内部**：说明卡是 `fullScreenCover` 呈现的，而既有"敬请期待" alert（`:142-149`）挂在 `RecordTabView` 底层 `NavigationStack` 上、会被说明卡全屏盖住。**故「演示」占位提示改为在 `ScreenshotIntakeSheet` 内部弹**（自持 `@State showDemoPlaceholder` + `.alert`，见 §3），不依赖外层 `placeholderEntryTitle`、不需要 `onDemoTapped` 回调。`ScreenshotIntakeSheet` 只需 `recognizer` + `onRecognized` 两个入参。

### 3. 截图说明卡 `ScreenshotIntakeSheet`（新增 `Aubade/Features/Recognition/Screenshot/ScreenshotIntakeSheet.swift`）

对齐 demo `openScreenshotSheet`（`prototype/app/app.js:266-283`）：

```swift
import SwiftUI
import PhotosUI

/// 截图识别说明卡（原型 app.js:266 openScreenshotSheet）：
/// 快捷指令主入口讲解 + 两步指引 +「从相册选图」备选 +「演示」占位（N06）。
/// 「从相册选图」= PhotosPicker 免权限选图 → 本机 OCR → 回调 onRecognized 交出文本。
struct ScreenshotIntakeSheet: View {
    let recognizer: any TextRecognizing
    let onRecognized: (String) -> Void      // OCR 出文本 → 上层切 .recognizing 复用识别页

    @Environment(\.dismiss) private var dismiss
    @State private var pickedItem: PhotosPickerItem?
    @State private var ocrPhase: ScreenshotOCRPhase = .idle
    @State private var showDemoPlaceholder = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 快捷指令主入口讲解（app.js:270）
                    introHero
                    // 两步设置指引（app.js:273-274）
                    twoStepGuide
                    // 「演示：模拟快捷指令截图」占位（app.js:276，N06）
                    Button("▶︎ 演示：模拟收到一张快捷指令截图") { showDemoPlaceholder = true }
                        .buttonStyle(.bordered)
                    Divider().overlay(Text("或").font(.caption).foregroundStyle(.secondary))
                    // 「从相册选图」备选（app.js:278）= 本节点核心入口
                    PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                        Label("从相册选一张图识别", systemImage: "photo")
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ocrPhase == .recognizing)
                }
                .padding()
            }
            .navigationTitle("截图识别")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .overlay { if ocrPhase == .recognizing { ocrRecognizingOverlay } }   // 本机读字中遮罩
            .alert("敬请期待", isPresented: $showDemoPlaceholder) {
                Button("好", role: .cancel) { }
            } message: { Text("快捷指令截图后台入账将在后续版本提供。") }
            .alert("这张图没能识别", isPresented: ocrFailedBinding) {
                Button("好", role: .cancel) { ocrPhase = .idle }
            } message: { Text(ocrFailedMessage) }         // 空结果/OCR 失败文案（见下）
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task { await runOCR(item) }
            }
        }
    }

    // 选图 → 取 Data → 本机 OCR → 成功回调 / 失败态
    private func runOCR(_ item: PhotosPickerItem) async {
        ocrPhase = .recognizing
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                ocrPhase = .failed(.failed); return          // 取不到图片数据
            }
            let text = try await recognizer.recognizeText(in: data)
            ocrPhase = .idle
            pickedItem = nil                                  // 复位选择器，可重选
            onRecognized(text)                                // 交出 OCR 文本 → 上层切 .recognizing
        } catch let e as TextRecognizeError {
            ocrPhase = .failed(e); pickedItem = nil
        } catch {
            ocrPhase = .failed(.failed); pickedItem = nil
        }
    }
}

/// 说明卡内 OCR 局部状态机（对齐 RecognitionPhase 风格；成功不停留——交回上层复用识别页）。
enum ScreenshotOCRPhase: Equatable {
    case idle
    case recognizing                    // 本机读字中（遮罩"正在识别截图…本机读取文字"）
    case failed(TextRecognizeError)     // 空结果 / OCR 失败 → 对应提示，可重选
}
```

**失败/空结果文案**（对齐 PRD §5/验收 5）：
- `.empty`（没读出字）→ "没从这张图读出文字，换一张或手动记。"
- `.failed`（解码/OCR 失败）→ "这张图没能识别，换一张或转手动填写。"

**用户取消选图**：`PhotosPicker` 取消不触发 `.onChange`（`pickedItem` 不变），天然静默回说明卡，无需处理（对齐 PRD §5"用户取消不报错"）。

> **说明卡文案**（`introHero`/`twoStepGuide`）逐字对齐 demo：主用法讲解"在支付宝/微信/银行的付款结果页，用 iOS 快捷指令随手一截…后台识别并直接入账，只弹一条通知"（`app.js:270`）；两步"①去「快捷指令」App 新建：截屏→发送给 Aubade ②付完款触发它"（`app.js:273-274`）。

### 4. provider 注入（改 `RecordTabView.swift`，对齐 makeVoiceTranscriber 范式）

```swift
#if DEBUG
@AppStorage(DebugScreenshotMockSettings.behaviorKey) private var screenshotMockRaw = MockTextRecognizer.Behavior.success.rawValue
#endif

private func makeTextRecognizer() -> any TextRecognizing {
    #if DEBUG
    let behavior = MockTextRecognizer.Behavior(rawValue: screenshotMockRaw) ?? .success
    let m = MockTextRecognizer(); m.behavior = behavior; return m
    #else
    return VisionTextRecognizer()
    #endif
}

// 截图场景解析器：DEBUG 固定 .screenshotSample（88.5/食/星巴克），Release 走 DeepSeekClient
private var screenshotParser: TransactionParsing {
    #if DEBUG
    return MockTransactionParser(behavior: .screenshotSample)
    #else
    return DeepSeekClient()
    #endif
}

/// 截图落库原文前缀（PRD 已确认约定 11，对齐 voiceRawText/demo data.js:44）：`[截图识别]\n<OCR 文本>`。
private func screenshotRawText(ocrText: String) -> String {
    "[截图识别]\n\(ocrText)"
}
```

- 截图 DEBUG 解析固定 `.screenshotSample`，与文本 `textParser`（读 `@AppStorage`）、语音 `voiceParser`（`.voiceSample`）**三者分开**，互不污染（PRD §6）。
- `ScreenshotIntakeSheet` 接收注入的 `recognizer`；OCR 成功回调把 `ocrText` 交回 `RecordTabView` 驱动 §2 转场。

### 5. DEBUG 截图 mock 开关（改 `DebugMenuView.swift`，对齐语音 mock Section）

```swift
enum DebugScreenshotMockSettings { static let behaviorKey = "debug.screenshotMockBehavior" }
// DebugMenuView 内新增：
@AppStorage(DebugScreenshotMockSettings.behaviorKey) private var screenshotMockRaw = MockTextRecognizer.Behavior.success.rawValue
// Section("N05 调试（截图 OCR mock）") {
//   Text("模拟器无真图片：切换行为走通截图 → 入账 / 各降级")
//   Picker("mock OCR 结果", selection: $screenshotMockRaw) {
//     Text("成功（星巴克 88.5）").tag(...success)
//     Text("空结果（没读出字）").tag(...empty)
//     Text("OCR 失败").tag(...failed)
//   }
// }
```

模拟器无真图片：选"成功"→ 走通截图→入账→结果卡片（88.5/食/星巴克/截图相册）；选降级项→观察对应提示不崩溃、可重选。（DEBUG 下 PhotosPicker 仍需选一张真图触发 `.onChange`，但 mock 忽略图片内容恒返定值——见切片 01 §3。）

## 修改点

| 文件 | 改动 | 类型 |
|---|---|---|
| `Aubade/Features/Recognition/Screenshot/ScreenshotIntakeSheet.swift` | 新增：说明卡 + PhotosPicker 选图 + `ScreenshotOCRPhase` 状态机 + 本机 OCR + 失败/空/演示占位提示 | 新增文件 |
| `Aubade/Features/Record/RecordTabView.swift` | `:167` 截图入口接线（无 Key 拦截 → 说明卡）；新增 `ScreenshotRoute` + `fullScreenCover(item:)` 驱动 + OCR provider/screenshotParser/screenshotRawText 注入 + 无 Key alert + Key sheet + 成功转场 `TextRecognitionView` | 接线扩展 |
| `Aubade/Debug/DebugMenuView.swift` | 新增 `DebugScreenshotMockSettings` + 截图 mock Picker Section | DEBUG 扩展 |

（本项目 `Aubade/` 为 Xcode 16 同步文件夹 `PBXFileSystemSynchronizedRootGroup`，新增 `.swift` 放进目录**自动纳入 target，无需手改 pbxproj**；本片无工程文件改动、无 Info.plist 改动——PhotosPicker 免权限，不加 `NSPhotoLibraryUsageDescription`。）

（本片以 UI/接线为主，自动化验收靠 DEBUG mock 端到端肉眼观察 + 切片 01 单测覆盖 `source=.screenshotAlbum`/provider 分支；不新增脱 View 单测——UI 状态机与转场在模拟器 mock 下人工走查，对齐 PRD 已确认约定 8。）

## 验证点

（模拟器 + DEBUG 截图 mock 注入，对齐 PRD 验收 1/2/3/5/6/7/8/10；验收 4/9 见下说明）

- **验收 1 相册选图入账**：记账页点📷 →（有 Key）说明卡 → 点「从相册选图」选一张图（mock=成功）→ 本机读字遮罩 → 转场识别中 → 弹结果卡片：金额 88.5（Decimal 无误差）、支出、分类"食"、商户星巴克、来源截图相册（`.screenshotAlbum`）、原文=`[截图识别]\n星巴克咖啡…`。
- **验收 2/3 结果卡片**：可改金额/方向/分类/时间，「完成」后统计与剩余（N02）刷新；「删除这笔」二次确认撤销同步；可展开看识别出的原文（带 `[截图识别]` 前缀）。
- **验收 5 OCR 失败/空结果**：（mock=空结果）"没从这张图读出文字，换一张或手动记"；（mock=OCR 失败）"这张图没能识别，换一张或转手动"——均不报错、不生成脏账单，可重选。
- **验收 6 无 Key 拦截**：清除 Key → 点📷 先弹拦截提示、不进说明卡；「去填写」进 Key sheet；手动记账不受影响。
- **验收 7 说明卡形态**：呈现快捷指令主入口讲解 + 两步指引 +「从相册选图」+「演示」按钮；「演示」点击弹"敬请期待/后续版本提供"占位（不实现后台）；「从相册选图」是真实备选入口。
- **验收 8 隐私**：Release 用 `VisionTextRecognizer`（Vision 纯本机、图片不外传）；无 Key 拦截、mock 路径不发网络；`imageRef` 恒 nil。
- **验收 10 不越界**：无快捷指令/App Intents/后台/通知（「演示」仅占位）；`recognizeAndSave`/`TextRecognitionView` 零签名改动；`imageRef` 恒 nil；不改 N01/N02/N03/N04 既有行为（语音🎤/文本📋/手动✏️入口不动）。
- **验收 4（相册权限被拒降级）不适用**：PhotosPicker 免权限，无授权可拒（见 index"对 PRD 的偏离说明"）；"主流程不受影响"仍成立——选图独立进程，取消/失败均静默回说明卡，手动/文本/语音记账照常。
- **验收 9（单测）在切片 01**：`source=.screenshotAlbum` 落库 + OCR provider 分支单测已在切片 01 覆盖；本片不重复。
- **N03/N04 不回归**：文本识别（📋）、语音记账（🎤）入口行为不变（各自 mock/parser 分开）；`RecordTabView` 三套 provider/parser 互不污染。

## 不做什么

- **不提升 `RecognitionResultCard` 可见性、不重写 N03 失败分支**：照抄 N04，经 `TextRecognitionView`（预置文本自动识别）复用整套，零改其结构。
- **不做相册权限申请/被拒降级/`NSPhotoLibraryUsageDescription`**：PhotosPicker 免权限（见 index"对 PRD 的偏离说明"）。
- **不做快捷指令/App Intents/后台入账/通知**（N06）：说明卡「演示」按钮仅占位提示，不实现后台链路、不做原图临时留存。
- **不做权限统一收口 / 我的页权限状态 / 首次引导**（N07）。
- **不做真机真图片 OCR + 真实 Key 端到端作为门禁**（用户后续自测）；本片模拟器走 mock。
- **不改 N01/N02 行为、`RecognitionResultCard`/`TransactionEditor`/`LedgerStore` 签名**；文本 DEBUG mock 仍 `.success`（256/京东）、语音 `.voiceSample`（20/行）、截图专用 `.screenshotSample`（88.5/食/星巴克），三者并存。
- **不改 `recognizeAndSave`/`TextRecognitionView` 签名**（N04 已参数化，本片仅新增 `.screenshotAlbum` 调用方）。
