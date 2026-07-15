# TRD 01 - 后台链路核心单元 + App Intent 入口 + 通知协议抽象 + 共享容器

## 给用户看的摘要

这一片搭**后台自动记账的"发动机"**，但先不接真实的系统通知、也不接界面——全部做成能脱离手机环境、用假数据在测试里跑通并断言的纯逻辑：

- 一个**后台链路核心单元**：喂它一张截图（的数据），它就按顺序跑「本机读字 → 看有没有配 Key → 发给 DeepSeek 解析 → 直接记成一笔账 → 决定该弹哪一类通知」，任何一步失败都**绝不记错账**。
- 一个 **iOS 快捷指令能调用的动作**（"记录 Aubade 截图"）：它只是薄薄一层壳，收到图片就调上面那个核心单元。
- 一个**"发通知"的抽象接口**：核心单元只说"该发成功/失败/没配 Key 哪一类通知"，真正怎么弹系统通知留到切片 02——这样测试里能断言"它决定发哪类通知"而不用真弹。
- 一个**后台安全拿数据库的通道**：让后台唤醒时能写进和你平时看到的同一个账本。

做完这片，后台记账的全部分支逻辑都被单元测试焊死；切片 02 只需把"发通知"和"点通知跳界面"接成真的。

## 本 TRD 负责什么

- 新增 `BackgroundIntakeService`：脱 View、脱 App Intent 框架、脱真系统通知的后台链路编排核心单元，注入 OCR provider / parser / store / 通知发送器 / now。
- 新增 `NotificationSending` 协议 + `IntakeNotification` 通知意图值类型（成功/失败/无 Key 三类，携带跳转所需标识）。核心单元只依赖协议，不碰 `UNUserNotificationCenter`。
- 新增 `RecordAubadeScreenshotIntent`（`AppIntent`，参数=一张图片）+ `AubadeShortcuts`（`AppShortcutsProvider`）：主 App target 内暴露快捷指令动作，`perform()` 薄壳调核心单元。
- 新增 `AppModelContainer`：全 App 共享的 `ModelContainer` 持有点，后台 `perform()` 经它拿到与主 App 同一容器的 `ModelContext`（持有容器再取 context，遵守 SIGTRAP 陷阱）。改 `AubadeApp` 从此持有点取容器。
- 新增单测：后台链路各分支（成功落 `.screenshotShortcut`/无 Key/OCR 空/OCR 失败/解析超时/无网/无金额）落库与"发哪类通知"断言；N03/N04/N05 不回归复核。

**本片不做**：真实 `UNUserNotificationCenter` 通知构造与权限（切片 02）、通知点击深链（切片 02）、演示按钮接线（切片 02）、原图真实写盘临时留存（切片 02，本片核心单元只在失败分支产出"需保留原图"的信号 + imageRef 占位入参）。

## 当前代码事实与上下游

**直接复用（只读消费，不改签名）**：

- `TextRecognizing`（`Aubade/Features/Recognition/Screenshot/TextRecognizing.swift:13-18`，`@MainActor protocol`，`func recognizeText(in imageData: Data) async throws -> String`，抛 `TextRecognizeError.empty`/`.failed`）。注释 `:10-11` 明写"可被 N06 快捷指令后台链路独立调用"。真实 `VisionTextRecognizer`、mock `MockTextRecognizer`（三态 `.success`/`.empty`/`.failed`，`sampleRecognizedText` 星巴克/¥88.50，`MockTextRecognizer.swift:8-25`）。
- `RecognitionEntry.recognizeAndSave(text:categories:parser:store:now:source:rawText:)`（`TextRecognitionView.swift:18-24`，`@MainActor static`，`source=.text`/`rawText=nil` 默认值，`now` 必传）。不变量注释 `:6-7`："任何失败（parse 抛错 / 归一抛 .noAmount）都发生在 createTransaction 之前"。内部调 `store.createTransaction` **不传 imageRef**（`:30-38`），故成功入账 `imageRef` 恒 nil。
- `TransactionParsing` 协议 + `DeepSeekClient`（`DeepSeekClient.swift:9`，`timeout=20`s `:14`、不重试 `:6-8`、无 Key 抛 `.noKey` `:17`、`.timedOut→.timeout`/其它→`.network` `:29-32`、非 2xx→`.invalidResponse` `:35`）+ mock `MockTransactionParser`（`.screenshotSample` 定值 88.50/支出/星巴克/食，`MockTransactionParser.swift:9/48-57`）。
- `RecognitionError`（`RecognitionError.swift:9-14`：`.noKey`/`.network`/`.timeout`/`.noAmount`/`.invalidResponse`）；`TextRecognizeError`（`TextRecognizing.swift:4-7`：`.empty`/`.failed`）——**OCR 层与解析层是两套错误，核心单元都要接**。
- `LedgerStore.createTransaction(...source:rawText:imageRef:)`（`LedgerStore.swift:48-61`，`source` 必传、`rawText`/`imageRef` 默认 nil，内部 `context.insert`+`save`）；`LedgerStore(_ context:)` 只持有注入 context（`:8-13`）。
- `KeychainStore.shared.deepSeekKey`/`.isConfigured`（`KeychainStore.swift:22-35/:54-56`，`kSecAttrAccessibleAfterFirstUnlock :43` 首次解锁后后台可读）。
- `TransactionSource.screenshotShortcut`（`Enums.swift:13`，已定义、当前零调用方，N06 首次用）；`Transaction.imageRef: String?`（`Transaction.swift:16`）。
- `PersistenceController.makeContainer()`/`makeInMemoryContainer()`（`PersistenceController.swift:17-27`，in-app 非共享；`:14-16` 注释"若发生在 N06 评估"）；`PresetCategories.seedIfNeeded`。

**被改动**：

- `AubadeApp.swift:6`：`let container = PersistenceController.makeContainer()` 是**实例属性**，后台 `perform()` 访问不到。改为从新增的 `AppModelContainer.shared.container` 取，保证主 App 与后台 Intent 用同一容器实例。

**上下游影响**：`AubadeApp` 改容器来源是唯一改动点，`.modelContainer(container)` 注入与 `PresetCategories.seedIfNeeded(container.mainContext)` 行为不变（同一容器实例）。`RecordTabView`/`ContentView`/所有 `@Environment(\.modelContext)` 消费方不受影响（仍是主 App 注入的同一容器）。

## 设计方案

### 1. 共享容器持有点 `AppModelContainer`（后台拿 context 的唯一合法通道）

```swift
// Aubade/Persistence/AppModelContainer.swift（新增）
import SwiftData

/// 全 App 唯一的 ModelContainer 持有者。in-app App Intents 路线：主 App 与后台唤醒的
/// perform() 共享同一实例（PRD 已确认约定 1）。持有容器（let container）再取 mainContext，
/// 绝不链式 makeContainer().mainContext——容器被 ARC 释放会导致 insert/save SIGTRAP（见 memory）。
@MainActor
final class AppModelContainer {
    static let shared = AppModelContainer()
    let container: ModelContainer = PersistenceController.makeContainer()
    private init() {}
}
```

- `AubadeApp.swift` 改为 `let container = AppModelContainer.shared.container`（取同一实例，非再造）。
- App Intent `perform()`（`@MainActor`）经 `AppModelContainer.shared.container.mainContext` 拿 context → `LedgerStore(context)`。**持有点是 `let` 属性长期持有容器**，取 `.mainContext` 时容器不会被释放，规避 SIGTRAP。
- 单测**不碰**这个共享单例（它绑生产容器），一律注入 `makeInMemoryContainer()` 的持有 container 的 mainContext（照搬 `RecognitionEntryScreenshotTests` setUp 持有 container 范式）。

### 2. 通知意图抽象（核心单元与系统通知解耦）

```swift
// Aubade/Features/Recognition/Shortcut/IntakeNotification.swift（新增）
import Foundation

/// 后台链路要发的通知意图（值类型，脱 UNUserNotificationCenter）。切片 02 的真实发送器据此构造系统通知。
enum IntakeNotification: Equatable {
    case success(transactionID: UUID, amountText: String, categoryName: String?, merchant: String?)
    case failure(imageRef: String?, rawText: String?)   // 点此补录：带原图引用 + 原文供补录带入
    case missingKey                                       // 请先配置 Key
}

/// "发通知"的能力抽象。真实实现（UNUserNotificationCenter）在切片 02；单测注入 spy 断言发了哪类。
protocol NotificationSending: Sendable {
    func send(_ notification: IntakeNotification) async
}

/// 空实现：切片 01 的 App Intent perform() 占位注入，切片 02 前保证独立编译（不发任何通知）。
struct NoOpNotifier: NotificationSending {
    func send(_ notification: IntakeNotification) async {}
}
```

- `send` 不抛错：通知权限被拒/发送失败**不得影响入账结果**（约定 9）。真实实现内部吞掉发送失败。
- 单测用 spy 记录收到的 `IntakeNotification`，断言类型与关键字段（金额/分类/imageRef）。

### 3. 后台链路核心单元 `BackgroundIntakeService`（脱 View 编排）

```swift
// Aubade/Features/Recognition/Shortcut/BackgroundIntakeService.swift（新增）
import Foundation
import SwiftData

/// 后台截图入账编排核心（脱 View、脱 AppIntent 框架、脱真系统通知）。顺序严格按技术基线 §7.3。
/// 钉 @MainActor：与 recognizeAndSave / ModelContext 落库线程约束一致（context 非 Sendable）。
@MainActor
struct BackgroundIntakeService {
    let recognizer: any TextRecognizing
    let parser: TransactionParsing
    let store: LedgerStore
    let categories: [LedgerCategory]
    let notifier: any NotificationSending
    let keychain: KeychainStore           // 默认 .shared；测试可注入
    let now: () -> Date                   // 注入当前时刻（测试固定）
    let imageStore: FailedImageStoring    // 失败原图留存（本片协议 + no-op 默认；真实实现切片 02）

    /// 入口：收到截图数据 → 跑完整条后台链路。不抛错（后台任务须自收敛：所有失败落通知 + 及时结束）。
    func intake(imageData: Data) async {
        // ① 本机 OCR（图片不外传）
        let ocrText: String
        do {
            ocrText = try await recognizer.recognizeText(in: imageData)
        } catch {
            // OCR .empty / .failed → 保留原图、发失败通知、不记账
            let ref = imageStore.save(imageData)
            await notifier.send(.failure(imageRef: ref, rawText: nil))
            return
        }
        // ② 读 Key——无 Key 直接结束（不解析、不记账）
        guard keychain.isConfigured else {
            await notifier.send(.missingKey)
            return
        }
        // ③ 解析→归一→落库（复用 recognizeAndSave 的"落库前失败不产生脏账"不变量）
        do {
            let tx = try await RecognitionEntry.recognizeAndSave(
                text: ocrText, categories: categories,
                parser: parser, store: store, now: now(),
                source: .screenshotShortcut,
                rawText: "[快捷指令]\n" + ocrText)
            // ④ 成功 → 发成功通知（imageRef 恒 nil，不留存原图）
            await notifier.send(.success(
                transactionID: tx.id,
                amountText: AmountFormat.plainString(tx.amount),
                categoryName: tx.category?.name,
                merchant: tx.merchant))
        } catch {
            // ⑤ 解析/归一失败（RecognitionError 任一）→ 保留原图、发失败通知、不记账
            let ref = imageStore.save(imageData)
            await notifier.send(.failure(imageRef: ref, rawText: "[快捷指令]\n" + ocrText))
        }
    }
}

/// 失败原图临时留存抽象（本片仅协议 + no-op 默认，真实写盘/清理在切片 02）。
protocol FailedImageStoring: Sendable {
    func save(_ imageData: Data) -> String?   // 返回 imageRef（临时文件引用）；no-op 返回 nil
}
struct NoOpFailedImageStore: FailedImageStoring {
    func save(_ imageData: Data) -> String? { nil }
}
```

- **前缀常量与 N05 对齐**：N05 用 `"[截图识别]\n" + ocrText`（`RecordTabView.swift:129-131`），N06 用 `"[快捷指令]\n" + ocrText`。落库 `rawText` 带前缀、parse 输入用纯 OCR 文本，二者经 `recognizeAndSave` 的 `text`/`rawText` 分离。
- **成功 `imageRef` 恒 nil**（`recognizeAndSave` 不透传 imageRef，与 N05 一致）；失败分支才 `imageStore.save` 落临时文件（本片 no-op、切片 02 实现）。
- **失败通知携带 `rawText`（带前缀 OCR 文本）**供补录带出原文——但 OCR 本身失败（`.empty`/`.failed`）时无 OCR 文本，`rawText: nil`。
- `catch` 不区分 `RecognitionError` 具体类型（都走"保留原图+失败通知"），但 `recognizeAndSave` 内的 `store.createTransaction` 若抛意外错，SwiftData 可能残留 pending insert——**本片在 catch 内补 `store.context.rollback()`** 守脏账（对齐 `TextRecognitionView.swift:220-222` 的 rollback 手法）。

### 4. App Intent 入口（薄壳，主 App target 内）

```swift
// Aubade/Features/Recognition/Shortcut/RecordAubadeScreenshotIntent.swift（新增）
import AppIntents
import SwiftData

/// "记录 Aubade 截图"后台动作（in-app，主 App target 内；PRD 已确认约定 1）。
/// perform() 在系统后台唤醒的主 App 进程内执行，共享 AppModelContainer；不弹前台 UI。
struct RecordAubadeScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "记录 Aubade 截图"
    static let description = IntentDescription("把截图交给 Aubade，后台识别并直接记一笔账。")
    static let openAppWhenRun = false   // 后台执行，不打开前台

    @Parameter(title: "截图")
    var image: IntentFile               // 快捷指令传入的图片文件

    @MainActor
    func perform() async throws -> some IntentResult {
        let container = AppModelContainer.shared.container
        let context = container.mainContext                  // 持有点已长期持有容器，安全取 context
        let categories = (try? context.fetch(FetchDescriptor<LedgerCategory>())) ?? []
        let service = BackgroundIntakeService(
            recognizer: VisionTextRecognizer(),
            parser: DeepSeekClient(),
            store: LedgerStore(context),
            categories: categories,
            notifier: NoOpNotifier(),                        // TODO(切片02)：换 UNUserNotificationCenterNotifier()
            keychain: .shared,
            now: { Date() },
            imageStore: NoOpFailedImageStore())              // TODO(切片02)：换 TemporaryImageStore()
        await service.intake(imageData: image.data)
        return .result()
    }
}

// Aubade/Features/Recognition/Shortcut/AubadeShortcuts.swift（新增）
import AppIntents
struct AubadeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordAubadeScreenshotIntent(),
            phrases: ["用 \(.applicationName) 记这张截图"],
            shortTitle: "记录截图",
            systemImageName: "camera.viewfinder")
    }
}
```

- **`@Parameter var image: IntentFile`**：`IntentFile` 承接快捷指令传入的图片文件，`image.data` 取 `Data` 喂核心单元。（真机传图机制、`IntentFile` vs 具体图片类型的取舍属真机自测项，本片按 `IntentFile.data` 落地，编译交付。）
- **切片依赖顺序（本片可独立编译）**：`UNUserNotificationCenterNotifier` 与 `TemporaryImageStore` 是切片 02 产物。故切片 01 的 `perform()` **按上方代码块字面注入 `NoOpNotifier()` + `NoOpFailedImageStore()`**（两者均本片内定义，见 §修改点），并留 `// TODO(切片02)` 注释；切片 02 再替换为真实实现。这样切片 01 单独编译不引用任何切片 02 类型。**核心单元 `BackgroundIntakeService` 与其单测不依赖切片 02**，逻辑完整可测。

### 5. 单测（脱真图片/真网络/真系统通知，照搬 `RecognitionEntryScreenshotTests` 范式）

新增 `AubadeTests/BackgroundIntakeServiceTests.swift`：`@MainActor`、`setUp` 持有 `container = makeInMemoryContainer()`（悬垂陷阱）、`seededCategories()`、spy 通知器。

| 用例 | 注入 | 断言 |
|---|---|---|
| 成功入账 | OCR mock `.success` + parser `.screenshotSample` + Key 已配 | 落库 1 笔、`source=.screenshotShortcut`、`amount=Decimal("88.50")`、`category?.name="食"`、`merchant="星巴克"`、`rawText` 有 `[快捷指令]` 前缀且 ≠ 纯 OCR 文本、`imageRef=nil`；spy 收到 `.success(transactionID:...)` 且金额/分类字段正确 |
| 无 Key | Key 未配（注入空 keychain 或 stub `isConfigured=false`） | **未落库**（txs.count=0）；spy 收到 `.missingKey`；未调 parser |
| OCR 空 | OCR mock `.empty` | 未落库；spy 收到 `.failure`；`imageStore.save` 被调（用 spy imageStore 断言）；`rawText=nil` |
| OCR 失败 | OCR mock `.failed` | 同上 `.failure` |
| 解析超时 | OCR `.success` + parser `.timeout` | 未落库（守不变量）；spy `.failure`；`rawText` 带前缀非空 |
| 无网 | parser `.network` | 未落库；spy `.failure` |
| 无金额 | parser `.noAmount` | 未落库；spy `.failure` |
| 不回归 | 复核既有 `RecognitionEntryScreenshotTests`/`VoiceTests`/`Tests` 仍绿 | `.screenshotAlbum`/`.voice`/`.text` 落库不变 |

- **Keychain 无 Key 的可测性（已核实：测试宿主能真实读写 Keychain）**：`MockParserTests.swift:53-70` 已有 `KeychainStore.shared` 的 set→get→clear 冒烟且通过——说明测试宿主可真实读写 Keychain。故**直接注入 `KeychainStore.shared`**、单测里 `clearDeepSeekKey()` 造"无 Key"、`setDeepSeekKey("sk-test")` 造"有 Key"，**不抽 `KeyProviding` 协议、不预造抽象**（YAGNI）。测试用例结束在 `tearDown` 清 Key，避免污染后续用例。`BackgroundIntakeService.keychain` 入参默认 `.shared`，保留注入口仅为测试造态方便，非新增抽象层。

## 修改点

- 新增 `Aubade/Persistence/AppModelContainer.swift`（共享容器持有点）。
- 改 `Aubade/AubadeApp.swift:6`：容器来源改 `AppModelContainer.shared.container`。
- 新增 `Aubade/Features/Recognition/Shortcut/IntakeNotification.swift`（`IntakeNotification` + `NotificationSending` + `FailedImageStoring` + no-op 默认 + `NoOpNotifier`）。
- 新增 `Aubade/Features/Recognition/Shortcut/BackgroundIntakeService.swift`（后台链路核心单元）。
- 新增 `Aubade/Features/Recognition/Shortcut/RecordAubadeScreenshotIntent.swift` + `AubadeShortcuts.swift`（App Intent 入口薄壳，先注入 no-op notifier/imageStore + TODO(切片02)）。
- 新增 `AubadeTests/BackgroundIntakeServiceTests.swift`（后台各分支单测 + spy 通知器/imageStore）。
- 无 Info.plist / pbxproj 权限键改动（通知权限/用途键在切片 02）。

## 验证点

1. 编译通过（含 `import AppIntents`，主 App target，无 extension target）。
2. `BackgroundIntakeServiceTests` 全绿：成功落 `.screenshotShortcut` + 各失败分支未落库 + spy 断言发对通知类型。
3. 既有测试不回归（`RecognitionEntryScreenshotTests`/`VoiceTests`/`Tests`/`ScreenshotOCRProviderTests` 仍绿）。
4. `AubadeApp` 改容器来源后 App 正常启动、主 App 记账/查询行为不变（同一容器实例）。

## 不做什么

- 不实现真实 `UNUserNotificationCenter` 通知构造与权限申请（切片 02）——本片 Intent 注入 `NoOpNotifier`。
- 不实现原图真实写盘临时留存与清理（切片 02）——本片 `imageStore` 用 `NoOpFailedImageStore`（单测用 spy 断言"被调"即可）。
- 不接通知点击深链、不接演示按钮（切片 02）。
- **不加后台总时间预算保护**（PRD 已确认约定 4/11）：超时兜底只复用 `DeepSeekClient` 内置 20s 超时；是否加总预算由真机数据决定，本节点默认不造。
- 不实现方案 B 降级（PRD §7）。
- 不改 N03/N04/N05 任何签名与既有行为；不碰 `PersistenceController` 建库配置；不建 App Group。
