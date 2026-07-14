# TRD 01 - 语音转文字 provider 底座 + recognizeAndSave 参数化

## 给用户看的摘要

这一片是语音记账的**纯逻辑地基,没有任何界面、也不碰真麦克风**——所以能靠单元测试完全验证。它做三件事:

1. 定义"把一段话录下来、在本机转成文字"这个能力的**抽象契约**(协议)与一个**假实现**(mock),假实现能模拟"成功转出『打车花了 20 块』/没说话/权限被拒/本机不支持"四种情况,让后续在模拟器上无需真麦克风也能走通全流程。
2. 给 N03 已有的落库入口 `recognizeAndSave` **加两个带默认值的可选参数**(账单来源、原文),让语音能把账单记成"来源=语音"、原文带 `[语音转文字]` 前缀,而 **N03 文本识别的调用行为一个字都不变**。
3. 为语音准备一份**独立的假解析结果**(金额 20 / 支出 / 分类"行"),对齐原型 demo,供验收点 1 肉眼观察——不污染 N03 文本识别那份(256 / 京东)定值。

做完这片,语音"录音转文字"的可测单元、"记成语音账单"的落库能力就位;真实的 iOS 语音识别在切片 02、界面在切片 03。

## 本 TRD 负责什么

单一职责:**语音链路的可注入、脱 View、可单测的纯逻辑底座**。

- 新增语音转文字 provider 协议 `VoiceTranscribing` + 可区分错误 `VoiceTranscribeError`(对齐 N03 `TransactionParsing`/`RecognitionError` 范式)。
- 新增 mock 实现 `MockVoiceTranscriber`(behavior 驱动四态,供 DEBUG/预览/单测)。
- `RecognitionEntry.recognizeAndSave` **向后兼容参数化** `source`(默认 `.text`)与 `rawText`(默认 `nil` = 沿用 `text`)。
- `MockTransactionParser` 增加 `.voiceSample` 行为(金额 20 / 支出 / 分类"行"),作为语音验收定值。
- 单元测试覆盖上述所有分支。

不含真实 `SFSpeechRecognizer`/`AVAudioEngine`(切片 02)、不含任何 UI 与接线(切片 03)。

## 当前代码事实与上下游

（行号为写作时快照，可能 ±1 漂移；本仓库无 `.codegraph/`，逐文件阅读所得。）

- **落库编排入口** `RecognitionEntry.recognizeAndSave(text:categories:parser:store:now:)`（`Aubade/Features/Recognition/TextRecognitionView.swift:16-35`，`enum RecognitionEntry` 标 `@MainActor`，`:11-12`）：
  - `:21` `parser.parse(text:categories:)` → `:22` `RecognitionNormalizer.amount`（无金额抛 `.noAmount`）→ `:23` `occurredAt` → `:24` `category` → `:26-34` `store.createTransaction(...)`。
  - ⚠️ `:33` `source: .text` **硬编码**；`:34` `rawText: text`（parse 输入与落库原文是**同一个 `text`**）。本片要拆开这两处。
  - 现有唯一调用方 `TextRecognitionView.recognize()`（`TextRecognitionView.swift:193-195`），不传 `source`/`rawText`。
- **解析协议** `TransactionParsing.parse(text:categories:) async throws -> ParsedTransaction`（`Aubade/Features/Recognition/Parsing/TransactionParsing.swift:15-19`）；`ParsedTransaction`（`:5-12`：`amountText`/`direction`/`occurredAt?`/`merchant?`/`cardTail?`/`categoryName?`，**无 note 字段**）。
- **mock 解析** `MockTransactionParser`（`Aubade/Features/Recognition/Parsing/MockTransactionParser.swift`）：`Behavior: String, CaseIterable { success, noAmount, network, timeout, invalidResponse }`（`:8`）；`.success` 返回 256.00 / 京东商城 / 尾号1234 / 分类"其他"（`:29-36`）；`sampleOccurredAt` = 2026-07-10 15:22（`:12-20`）。
- **可区分错误** `RecognitionError`（`Aubade/Features/Recognition/Parsing/RecognitionError.swift:9-23`）：`noKey/network/timeout/noAmount/invalidResponse` + `isRetryable`（`:17-22`）。语音转文字错误**语义不同**（麦克风/语音授权/本机不可用/空结果），故**新建 `VoiceTranscribeError`**，不塞进 `RecognitionError`。
- **落库** `LedgerStore.createTransaction(amount:direction:occurredAt:category:merchant:note:cardTail:source:rawText:imageRef:)`（`Aubade/Store/LedgerStore.swift:47-61`）：`source: TransactionSource` 必填、`rawText: String? = nil`。**已支持语音落库，不改签名。**
- **来源枚举** `TransactionSource.voice`（`Aubade/Models/Enums.swift:15`）**已存在**。
- **归一** `RecognitionNormalizer.amount/occurredAt/category`（`Aubade/Features/Recognition/Parsing/RecognitionNormalizer.swift:9/18/26`，`enum` 静态方法）；分类按 name+direction 匹配库，预置支出含 **"行"**（`Aubade/Persistence/PresetCategories.swift:7`）——语音定值 categoryName="行" 可归一命中，验收 1 成立。
- **demo 语音契约** `prototype/app/data.js:45`：`voice: { amount: 20, dir: 'expense', cat: '行', note: '打车', raw: '[语音转文字]\n"打车花了 20 块"' }`。
- **N03 注入范式**（供对齐）：`RecordTabView.textParser`（`Aubade/Features/Record/RecordTabView.swift:32-39`）DEBUG 读 `@AppStorage(DebugMockSettings.behaviorKey)` 构造 mock、Release 走真实。

## 设计方案

### 1. 语音转文字契约（新增文件 `Aubade/Features/Recognition/Voice/VoiceTranscribing.swift`）

```swift
import Foundation

/// 语音转文字的可区分失败（入口层据此分支降级；对齐 RecognitionError 范式）。
enum VoiceTranscribeError: Error, Equatable {
    case microphoneDenied      // 麦克风权限被拒/受限
    case speechDenied          // 语音识别权限被拒/受限
    case onDeviceUnavailable   // supportsOnDeviceRecognition == false 或识别器不可用（隐私边界：不回退云端）
    case empty                 // 授权成功但没说话 / 没转出文字
    case failed                // 其他运行时失败（音频引擎/识别器错误）
}

/// "按住说话 → 本机转中文文字" 的能力抽象。真实（SFSpeech）与 mock 同契约，注入以便单测脱真麦克风。
/// @MainActor：真实实现涉 AVAudioSession/SFSpeechRecognizer，须主线程；mock 亦标注保持一致。
@MainActor
protocol VoiceTranscribing {
    /// 起录音+本机识别：内部先申请麦克风+语音识别权限、check on-device。
    /// 权限被拒/本机不可用 → 抛对应 VoiceTranscribeError（不起录音）。
    func start() async throws
    /// 结束录音并返回最终转出文本（trim 后）；无文字 → 抛 .empty。
    func finish() async throws -> String
    /// 取消并丢弃当前录音（松手前放弃 / 面板关闭）。
    func cancel()
}
```

`start()/finish()/cancel()` 三时点对应"按下→松手/60s→出文字"与"中途放弃"，权限申请封装进真实实现的 `start()`（PRD 已确认约定 9：首次按下录音才申请）。**MVP 不做实时转写**（见"不做什么"），只在 `finish()` 出最终文本，协议无实时回调。

### 2. mock 实现（新增文件 `Aubade/Features/Recognition/Voice/MockVoiceTranscriber.swift`）

```swift
import Foundation

@MainActor
final class MockVoiceTranscriber: VoiceTranscribing {
    /// String rawValue：供 DEBUG 调试菜单经 @AppStorage 持久化（切片 03）。
    enum Behavior: String, CaseIterable {
        case success            // 转出"打车花了 20 块"
        case empty              // 空结果
        case microphoneDenied
        case speechDenied
        case onDeviceUnavailable
    }
    var behavior: Behavior = .success

    /// 语音成功样例口语（纯口语，不含前缀；前缀在入口层拼，见切片 03 §rawText）。
    static let sampleSpokenText = "打车花了 20 块"

    func start() async throws {
        switch behavior {
        case .microphoneDenied:   throw VoiceTranscribeError.microphoneDenied
        case .speechDenied:       throw VoiceTranscribeError.speechDenied
        case .onDeviceUnavailable: throw VoiceTranscribeError.onDeviceUnavailable
        case .success, .empty:    return   // 起录音成功
        }
    }

    func finish() async throws -> String {
        switch behavior {
        case .empty:   throw VoiceTranscribeError.empty
        case .success: return Self.sampleSpokenText
        default:       throw VoiceTranscribeError.failed   // 已在 start 抛错，防御
        }
    }

    func cancel() {}
}
```

### 3. `recognizeAndSave` 向后兼容参数化（改 `TextRecognitionView.swift:16-35`）

新增 `source`（默认 `.text`）与 `rawText`（默认 `nil`，nil 时落 `text`，与 N03 现状等价）两个尾部带默认值参数，**拆开 parse 输入与落库原文**：

```swift
@discardableResult
static func recognizeAndSave(text: String,
                             categories: [LedgerCategory],
                             parser: TransactionParsing,
                             store: LedgerStore,
                             now: Date,
                             source: TransactionSource = .text,   // 新增：语音传 .voice
                             rawText: String? = nil) async throws -> Transaction {  // 新增：nil=落 text
    let parsed = try await parser.parse(text: text, categories: categories)   // parse 用纯口语 text
    let amount = try RecognitionNormalizer.amount(parsed.amountText)
    let occurredAt = RecognitionNormalizer.occurredAt(parsed.occurredAt, now: now)
    let category = RecognitionNormalizer.category(name: parsed.categoryName,
                                                  direction: parsed.direction, in: categories)
    return try store.createTransaction(
        amount: amount, direction: parsed.direction, occurredAt: occurredAt,
        category: category, merchant: parsed.merchant, cardTail: parsed.cardTail,
        source: source,                     // 原 .text 硬编码 → 参数
        rawText: rawText ?? text)           // 原 rawText: text → rawText ?? text
}
```

- **N03 调用方零改动**：`TextRecognitionView.recognize()` 不传新参数 → `source=.text`、`rawText=text`，与现状逐字节等价。
- **语音调用**（切片 03）：`recognizeAndSave(text: 纯口语, ..., source: .voice, rawText: "[语音转文字]\n\"\(纯口语)\"")`——parse 收纯口语（真实 DeepSeek 不必吞前缀），落库 `source=.voice`、`rawText` 带前缀。

### 4. 语音 mock 解析定值（改 `MockTransactionParser.swift`）

`Behavior` 增加 `.voiceSample`（`:8` 枚举追加 case），`parse` switch 增加分支（对齐 demo `data.js:45`）：

```swift
enum Behavior: String, CaseIterable { case success, voiceSample, noAmount, network, timeout, invalidResponse }
// ...
case .voiceSample:
    return ParsedTransaction(
        amountText: "20", direction: .expense,
        occurredAt: Self.sampleOccurredAt,     // 复用样例时间
        merchant: nil, cardTail: nil, categoryName: "行")
```

- 与 `.success`（256/京东/其他）**并存不替换**：文本识别 DEBUG 仍用 `.success`，语音 DEBUG 用 `.voiceSample`（切片 03 语音场景固定注入）。归一后金额 `Decimal(20)`、分类命中预置"行"。
- 复用 `sampleOccurredAt`，避免再造时间。

## 修改点

| 文件 | 改动 | 类型 |
|---|---|---|
| `Aubade/Features/Recognition/Voice/VoiceTranscribing.swift` | 新增：`VoiceTranscribing` 协议 + `VoiceTranscribeError` | 新增文件 |
| `Aubade/Features/Recognition/Voice/MockVoiceTranscriber.swift` | 新增：`MockVoiceTranscriber`（Behavior 五态） | 新增文件 |
| `Aubade/Features/Recognition/TextRecognitionView.swift` | `recognizeAndSave` 尾加 `source: = .text`、`rawText: = nil`；`:33` `source: source`、`:34` `rawText: rawText ?? text` | 改签名(向后兼容) |
| `Aubade/Features/Recognition/Parsing/MockTransactionParser.swift` | `Behavior` 加 `.voiceSample`；`parse` 加分支（20/支出/"行"） | 改枚举(追加) |
| `AubadeTests/VoiceProviderTests.swift` | 新增：mock provider 四/五态断言 | 新增文件 |
| `AubadeTests/RecognitionEntryVoiceTests.swift` | 新增：`source=.voice` 落库 + `rawText` 前缀 + 向后兼容默认 `.text` | 新增文件 |

（本项目 `Aubade/`、`AubadeTests/` 为 Xcode 16 同步文件夹 `PBXFileSystemSynchronizedRootGroup`，新增 `.swift` 文件放进对应目录**自动纳入 target/测试 target，无需手改 `project.pbxproj`**。）

## 验证点

- **单测 `MockVoiceTranscriber`**：`behavior=.success` → `start()` 不抛、`finish()` 返 "打车花了 20 块"；`.empty` → `finish()` 抛 `.empty`；`.microphoneDenied`/`.speechDenied`/`.onDeviceUnavailable` → `start()` 抛对应 error。各分支可区分（对齐 PRD 验收 9 provider 分支）。
- **单测 `recognizeAndSave` 语音路径**（照搬 N03 `RecognitionEntryTests` 范式，`PersistenceController.makeInMemoryContainer()` + `MockTransactionParser(.voiceSample)` 注入）：落库 `source == .voice`、`amount == Decimal(20)`（无浮点误差）、`category?.name == "行"`、`rawText == "[语音转文字]\n\"打车花了 20 块\""`（前缀保留）。
- **单测 向后兼容**：`recognizeAndSave` 不传 `source`/`rawText`（`MockTransactionParser(.success)`）→ `source == .text`、`rawText == 输入 text`，N03 行为不回归。
- **编译**：`RecognitionEntry` 仍 `@MainActor`；新协议 `@MainActor` 与 mock 一致，无 Sendable 告警。

## 不做什么

- **不做真实 `SFSpeechRecognizer`/`AVAudioEngine`**（切片 02）——本片 provider 只有协议 + mock。
- **不做任何 UI / 接线 / 权限申请代码**（切片 02 权限、切片 03 面板与 `RecordTabView` 接线、DEBUG 开关）。
- **不做实时转写**（partial result 流式显示）：MVP 只在 `finish()` 出最终文本，`VoiceTranscribing` 无实时回调；如需为 N04 后续增强。
- **不改 `RecognitionError`**：语音错误另立 `VoiceTranscribeError`，语义不混。
- **不动 `LedgerStore.createTransaction` 签名**（`:47` 已支持 `source`/`rawText`）、不改 `TextRecognitionView` 的 UI 与 `recognize()` 行为（仅 `recognizeAndSave` 加带默认值参数）。
- **不替换 `MockTransactionParser.success`**：语音定值走**新增** `.voiceSample`，256/京东 文本定值保留。
