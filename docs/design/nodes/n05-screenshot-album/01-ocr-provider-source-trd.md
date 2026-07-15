# TRD 01 - Vision OCR provider 底座 + 截图 mock 定值

## 给用户看的摘要

这一片打**没有界面的地基**——把"一张图片 → 本机读出里面的文字"这件事做成一个**可单独调用、可测试**的能力，还没接到任何按钮上：

1. 定义"图片转文字"的统一接口，真实实现用 iPhone 自带的 **iOS Vision** 文字识别（中文、**全程在手机本地、图片不上传**）。
2. 配一个假实现（mock），让模拟器不用真图片也能模拟"成功读出星巴克付款截图 / 图里没字 / 这张图识别失败"三种情况——下一片接界面时靠它肉眼验收。
3. 准备好截图场景的验收定值（金额 88.5、支出、分类"食"、商户星巴克，对齐原型），并写单元测试证明：这段文字走已有的记账链路，能记成一笔来源标记为"截图相册"、原文带 `[截图识别]` 前缀的正确账单。

做完这片，"图片→文字→记账"的核心逻辑已被测试焊死；下一片只需把它接到「从相册选图」按钮上。

## 本 TRD 负责什么

单一职责：**OCR provider 协议 + 真实 Vision 实现 + mock 实现 + 截图 mock 解析定值 + 全分支单测**。零 UI、零相册 UI、脱真图片可测。

- 新增 `TextRecognizing` 协议 + `TextRecognizeError`（对齐 N04 `VoiceTranscribing`/`VoiceTranscribeError` 范式）。
- 新增真实 `VisionTextRecognizer`：`VNRecognizeTextRequest` 中文本机 OCR，输入图片数据、输出识别文本；脱 View、脱相册 UI，可独立调用（供 N06 复用）。
- 新增 `MockTextRecognizer`：三态（成功/空/失败），供 DEBUG / 预览 / 单测。
- 新增 `MockTransactionParser.screenshotSample`：截图成功解析定值（88.5/支出/食/星巴克），与 `.success`/`.voiceSample` 并存。
- 单测：OCR provider 三态可区分；截图 OCR 文本经 `recognizeAndSave` 落库 `source=.screenshotAlbum`、`rawText` 带 `[截图识别]` 前缀、金额 Decimal 无误差；N03/N04 既有落库不回归。

## 当前代码事实与上下游

- **`recognizeAndSave` 已参数化**（N04 交付，`Aubade/Features/Recognition/TextRecognitionView.swift:18-24`）：`static func recognizeAndSave(text:categories:parser:store:now:source: TransactionSource = .text, rawText: String? = nil)`。`source` 默认 `.text`、`rawText` 默认 `nil`（`= text`）。**N05 传 `source: .screenshotAlbum` + `rawText:` 带前缀原文即可，零签名改动**。落库 `rawText ?? text`（`:38`）保证 parse 输入（纯 OCR 文本）与落库原文（带前缀）分离——与 N04 语音同机制。
- **`TransactionSource.screenshotAlbum`** 枚举值已存在（`Aubade/Models/Enums.swift:14`，N00 预置）。相册入账即用，无需新增枚举。
- **解析协议** `TransactionParsing`（`Aubade/Features/Recognition/Parsing/TransactionParsing.swift:15-19`）：`func parse(text:categories:) async throws -> ParsedTransaction`。`ParsedTransaction`（`:5-12`）字段：`amountText`/`direction`/`occurredAt`/`merchant`/`cardTail`/`categoryName`。
- **`MockTransactionParser`**（`Aubade/Features/Recognition/Parsing/MockTransactionParser.swift`）：`enum Behavior: String, CaseIterable { case success, voiceSample, noAmount, network, timeout, invalidResponse }`（`:9`）。`.success` 返 256/京东/其他（`:29-37`）、`.voiceSample` 返 20/支出/行（`:38-47`）。**本片新增 `.screenshotSample`**。样例时间 `sampleOccurredAt`（`:13-21`，2026-07-10 15:22）可复用。
- **N04 provider 范式参照**：`VoiceTranscribing`（`Aubade/Features/Recognition/Voice/VoiceTranscribing.swift:14-23`，`@MainActor protocol` + `start/finish/cancel`）、`VoiceTranscribeError`（`:4-10`，`Error, Equatable` 五态）、`MockVoiceTranscriber`（`Aubade/Features/Recognition/Voice/MockVoiceTranscriber.swift`，`enum Behavior: String, CaseIterable` + `static let sampleSpokenText`）。**OCR provider 照此结构，但契约是"图片数据 → 文本"的一次性调用**（无 start/finish/cancel 的录音生命周期）。
- **归一层** `RecognitionNormalizer`（`Aubade/Features/Recognition/Parsing/RecognitionNormalizer.swift`）：`amount`（无金额抛 `.noAmount`）、`occurredAt`（nil 取 now、不越未来）、`category`（按 name+direction 匹配库/兜底"其他"）。相册复用同一归一，不改。
- **`LedgerStore.createTransaction`**（`Aubade/Store/LedgerStore.swift`）已支持 `source:`/`rawText:`（N03 用、N04 透传 `.voice`）。相册透传 `.screenshotAlbum` 无需改签名。
- **测试范式** `RecognitionEntryVoiceTests`（`AubadeTests/RecognitionEntryVoiceTests.swift`）：内存容器持有 `container`（悬垂 context SIGTRAP 陷阱）、`seededCategories()`、`recognizeAndSave` 落库断言 `source=.voice`/`rawText`带前缀/`amount=Decimal(20)`/`imageRef=nil`。**照搬补 `.screenshotAlbum` 一条**。`VoiceProviderTests`（`AubadeTests/VoiceProviderTests.swift`）：provider 五态断言 + `Behavior.allCases` 全集断言。**照搬补 OCR provider 三态**。
- **相册/Vision 零脚手架**：`import Vision`/`VNRecognizeText`/`import Photos`/`PhotosPicker` 在 `Aubade/` 下**零命中**（本片首次引入 `import Vision` + `VisionTextRecognizer`；相册 UI 在切片 02）。

## 设计方案

### 1. OCR provider 协议 + 错误（新增 `Aubade/Features/Recognition/Screenshot/TextRecognizing.swift`）

对齐 N04 `VoiceTranscribing` 范式，但契约是**一次性"图片数据 → 文本"**（无录音生命周期）：

```swift
import Foundation

/// 本机图片 OCR 的可区分失败（入口层据此分支降级；对齐 VoiceTranscribeError 范式）。
enum TextRecognizeError: Error, Equatable {
    case empty      // OCR 成功执行但没读出任何文字（空白图/无文字图）
    case failed     // 图片无法解码 / Vision 请求失败
}

/// "图片 → 本机 OCR 文本" 的能力抽象。真实（Vision）与 mock 同契约，注入以便单测脱真图片。
/// 脱 View、脱相册 UI：入参是图片数据，可被 N06 快捷指令后台链路独立调用（PRD 已确认约定 9）。
/// @MainActor：与 N04 provider 一致对齐调用方（切片 02 MainActor View 的 Task）；真实实现内部把
/// 阻塞的 Vision perform 派到后台队列，@MainActor 仅约束方法入口/出口，不在主线程跑 OCR（见 §2）。
@MainActor
protocol TextRecognizing {
    /// 识别图片中的文字（本机、中文）。读不出字 → 抛 .empty；解码/请求失败 → 抛 .failed。
    /// 返回值 = trim 后的多行识别文本（行间 \n 连接）。
    func recognizeText(in imageData: Data) async throws -> String
}
```

> **入参选 `Data` 而非 `UIImage`/`CGImage`**：切片 02 的 `PhotosPicker` 经 `loadTransferable(type: Data.self)` 直接拿到图片 `Data`（最省转换）；N06 快捷指令后台收到的也是图片 `Data`。provider 内部再从 `Data` 构造 `CGImage` 喂 Vision。以 `Data` 为契约边界，两个调用方都不必先转 `UIImage`。

### 2. 真实 Vision 实现（新增 `Aubade/Features/Recognition/Screenshot/VisionTextRecognizer.swift`）

`VNRecognizeTextRequest` 中文本机 OCR。**关键 API 事实**（区别于 N04 Speech）：

- Vision 文本识别是**纯本机能力，无上云路径**——`VNRecognizeTextRequest` **没有** `requiresOnDeviceRecognition` 属性（那是 Speech 的），无需也无法显式"强制本机"，图片天然不外传（满足 PRD 隐私边界，无需额外开关）。
- `recognitionLanguages = ["zh-Hans", "zh-Hant"]`（PRD 已确认约定 1、DAG N05 范围明列中文）。
- `recognitionLevel = .accurate`（付款截图字小、需准；`.fast` 精度不足）；`usesLanguageCorrection = true`（中文纠错，付款截图含金额/商户名，纠错利大于弊）。
- **`VNImageRequestHandler.perform` 是同步阻塞调用**（区别于 N04 Speech 走异步 delegate）——`.accurate` 中文 OCR 对大图属 CPU 密集，故 **`perform` 派到后台队列执行**（`DispatchQueue.global`），避免阻塞主线程/卡"识别中"遮罩动画；`recognizeText` 的调用方（切片 02 MainActor View 的 `Task`）`await` 后自动跳回主线程。
- **用同步 `perform` 后读 `request.results`**（不用 completion-handler 构造）：`perform` 返回即结果就绪，`withCheckedThrowingContinuation` 内单次 `resume`（要么 `returning` 要么 `throwing`），无双 resume/泄漏风险。

```swift
import Foundation
import Vision
import CoreGraphics
import ImageIO

/// 真实「图片 → 本机中文 OCR 文本」实现（Vision）。图片不外传：Vision 文本识别纯本机、无上云路径。
/// perform 派后台队列执行（同步阻塞调用，不占主线程）；无存储状态。
@MainActor
final class VisionTextRecognizer: TextRecognizing {
    func recognizeText(in imageData: Data) async throws -> String {
        // 1) Data → CGImage（解码失败 = .failed，不外传、不误记）
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TextRecognizeError.failed
        }
        // 2) 后台执行 Vision（perform 同步阻塞→派 global 队列，不卡主线程）；同步读 results，单次 resume
        let lines: [String] = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLanguages = ["zh-Hans", "zh-Hant"]
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])          // 同步阻塞直到识别完成（后台线程）
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    let texts = observations.compactMap { $0.topCandidates(1).first?.string }
                    cont.resume(returning: texts)           // 成功：单次 resume
                } catch {
                    cont.resume(throwing: TextRecognizeError.failed)   // 失败：单次 resume
                }
            }
        }
        // 3) 多行拼成一段（行序即 Vision 返回序）→ trim；空 = .empty（没读出字，不误记）
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { throw TextRecognizeError.empty }
        return joined
    }
}
```

> **不做版面重排/坐标排序**：付款截图 OCR 出的文本交给 DeepSeek 解析金额/商户，DeepSeek 对行序不敏感（N03 已验证长短信文本乱序也能解析）；按 Vision 返回序拼接即可，不引入 bounding-box 排序复杂度（对齐 PRD "不过度设计"）。

### 3. Mock 实现（新增 `Aubade/Features/Recognition/Screenshot/MockTextRecognizer.swift`）

对齐 `MockVoiceTranscriber` 范式，**三态**（无录音生命周期，故比语音五态少——权限相关态在 PhotosPicker 下不存在）：

```swift
import Foundation

/// 图片 OCR mock（供 DEBUG / 预览 / 单测；对齐 MockVoiceTranscriber 范式）。
/// 三态覆盖成功 + 空结果 + 失败，让模拟器无真图片也能走通全流程与降级。
@MainActor
final class MockTextRecognizer: TextRecognizing {
    /// String rawValue：供 DEBUG 调试菜单经 @AppStorage 持久化（切片 02）。
    enum Behavior: String, CaseIterable {
        case success   // 读出付款截图样例文本
        case empty     // 没读出字
        case failed    // 图片无法解码 / OCR 失败
    }
    var behavior: Behavior = .success

    /// 截图成功样例 OCR 文本（纯识别文本，不含 [截图识别] 前缀；前缀在入口层拼，见切片 02）。
    /// 对齐 demo data.js:44 截图 raw（星巴克/88.50）；交给 parser 的 mock（.screenshotSample）解出定值。
    static let sampleRecognizedText = "星巴克咖啡\n实付金额 ¥88.50\n2026-07-10 13:10\n交易成功"

    func recognizeText(in imageData: Data) async throws -> String {
        switch behavior {
        case .success: return Self.sampleRecognizedText
        case .empty:   throw TextRecognizeError.empty
        case .failed:  throw TextRecognizeError.failed
        }
    }
}
```

> mock **忽略** `imageData`（DEBUG 下 PhotosPicker 仍会选真图，但 mock 恒返样例文本以给出验收定值——图片内容不影响 mock 结果，对齐 PRD §6"mock 恒返样例定值验字段落库正确性"）。

### 4. 截图解析 mock 定值（改 `MockTransactionParser.swift`）

新增 `.screenshotSample` case，与 `.success`/`.voiceSample` 并存（对齐 demo `data.js:43` 星巴克 88.5/支出/食）：

```swift
enum Behavior: String, CaseIterable { case success, voiceSample, screenshotSample, noAmount, network, timeout, invalidResponse }
// parse() switch 内新增：
case .screenshotSample:
    // 截图成功定值（对齐 demo data.js:43：金额 88.5 / 支出 / 分类"食" / 商户星巴克）；归一命中预置支出"食"。
    return ParsedTransaction(
        amountText: "88.50",
        direction: .expense,
        occurredAt: Self.sampleOccurredAt,
        merchant: "星巴克",
        cardTail: nil,
        categoryName: "食")
```

> **`MockParserTests` 无 `Behavior` 全集断言**（`AubadeTests/MockParserTests.swift` 只断言具体 case 的返回值/抛错），新增 case 不撞既有测试；本片补一条 `.screenshotSample` 返回值断言。

### 5. rawText 前缀（入口层拼，本片仅定义格式 + 单测覆盖）

`[截图识别]` 前缀格式（PRD 已确认约定 11，对齐 N04 `[语音转文字]` 与 demo `data.js:44`）：

```text
[截图识别]
<OCR 出的多行文字>
```

即 `"[截图识别]\n" + ocrText`。parse 收纯 OCR 文本（`ocrText`），落库 rawText 用带前缀串——经 `recognizeAndSave(text: ocrText, rawText: "[截图识别]\n" + ocrText)` 的 `text`/`rawText` 分离（与 N04 同机制）。**拼接发生在切片 02 的 `RecordTabView`**（对齐 N04 `voiceRawText(spoken:)` `RecordTabView.swift:84-86`）；本片单测直接构造带前缀串验证落库。

## 修改点

| 文件 | 改动 | 类型 |
|---|---|---|
| `Aubade/Features/Recognition/Screenshot/TextRecognizing.swift` | 新增：`TextRecognizing` 协议 + `TextRecognizeError`（empty/failed） | 新增文件 |
| `Aubade/Features/Recognition/Screenshot/VisionTextRecognizer.swift` | 新增：真实 `VNRecognizeTextRequest` 中文本机 OCR（Data→CGImage→文本） | 新增文件 |
| `Aubade/Features/Recognition/Screenshot/MockTextRecognizer.swift` | 新增：三态 mock（成功/空/失败）+ `sampleRecognizedText` | 新增文件 |
| `Aubade/Features/Recognition/Parsing/MockTransactionParser.swift` | `Behavior` 加 `.screenshotSample`；`parse()` 加对应 case（88.5/食/星巴克） | 扩展（并存不改既有） |
| `AubadeTests/ScreenshotOCRProviderTests.swift` | 新增：`MockTextRecognizer` 三态可区分 + `Behavior.allCases` 全集断言 | 新增测试 |
| `AubadeTests/RecognitionEntryScreenshotTests.swift` | 新增：`recognizeAndSave` 截图路径落库 `source=.screenshotAlbum`/前缀 rawText/Decimal；N04 默认不回归 | 新增测试 |
| `AubadeTests/MockParserTests.swift` | 补一条 `.screenshotSample` 返回值断言 | 测试扩展 |

（本项目 `Aubade/`/`AubadeTests/` 为 Xcode 16 同步文件夹 `PBXFileSystemSynchronizedRootGroup`，新增 `.swift` 放进目录**自动纳入 target，无需手改 pbxproj**；本片无工程文件改动。新增 `Screenshot/` 子目录同理自动纳入。）

## 验证点

（全部脱 View、脱真图片、脱网络；内存容器 + mock 注入，对齐 PRD 验收 9）

- **OCR provider 三态**：`MockTextRecognizer` 三 behavior → `.success` 返 `sampleRecognizedText`（非空）、`.empty` 抛 `.empty`、`.failed` 抛 `.failed`，可区分；`Behavior.allCases` 全集恰为 `{success, empty, failed}`（防后续漏改分支）。
- **`source=.screenshotAlbum` 落库**：以 `MockTextRecognizer.sampleRecognizedText` + `MockTransactionParser(.screenshotSample)` 注入 `recognizeAndSave(text: ocr, source: .screenshotAlbum, rawText: "[截图识别]\n"+ocr)` → 落库 `source=.screenshotAlbum`、`amount=Decimal(string:"88.50")`（无浮点误差）、`direction=.expense`、`category.name="食"`、`merchant="星巴克"`、`rawText` 带 `[截图识别]` 前缀且 `!= ocr`（分离）、`imageRef=nil`。
- **N03/N04 不回归**：`recognizeAndSave` 不传 `source`/`rawText` 仍落 `.text`+`rawText=text`；传 `.voice` 仍如 `RecognitionEntryVoiceTests`（复核既有测试不改）。
- **截图 mock 定值**：`MockTransactionParser(.screenshotSample).parse()` 返 88.50/支出/星巴克/食/`sampleOccurredAt`（补进 `MockParserTests`）。

## 不做什么

- **不写任何 UI / 相册选图 / 说明卡 / 入口接线**（全在切片 02）：本片只有 provider + mock + 定值 + 单测。
- **不做相册权限**：PhotosPicker 免权限（见 index）；provider 只吃图片 `Data`，与相册授权无关。
- **不改 `recognizeAndSave`/`TextRecognitionView`/`RecognitionResultCard`/`LedgerStore` 签名**（N04 已参数化，零签名改动）；不改 N03 `.success`/N04 `.voiceSample` 定值（`.screenshotSample` 并存新增）。
- **不做 Vision 版面/坐标重排**（行序拼接即可，DeepSeek 对行序不敏感）。
- **不做原图留存**：provider 吃完 `Data` 即返文本，不落 `imageRef`（恒 nil）、不做附件管理。
- **不越界**：不碰 N06 快捷指令后台（本片 provider 脱 View 为 N06 铺路，但不实现 App Intents）、N07 权限收口。
