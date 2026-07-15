# TRD 02 - 真实通知发送 + 权限 + 点击深链路由 + 演示接线 + 原图留存清理 + DEBUG 端到端

## 给用户看的摘要

这一片把切片 01 的"发动机"接成**看得见、点得动的完整主入口**：

- **真弹通知**：后台记完账，用 iOS 真实本地通知弹出来——成功弹「已记一笔 · ¥88.50 · 食」，没识别出弹「没识别出，点此补录」，没配 Key 弹「请先配置 Key」。
- **点通知能跳**：点成功通知 → 打开那笔账的**结果卡片**（能改能删）；点失败通知 → 打开**手动补录页**，把识别到的原文、留着的原图带进去；点没配 Key 的通知 → 打开填 Key 的地方。
- **演示按钮变真的**：记账页「📷 截图识别」说明卡里那个「▶︎ 演示」按钮，从"敬请期待"占位换成**真跑一遍后台链路**——模拟器上、没配快捷指令时，点一下就能亲眼看到"识别→入账→弹通知→点通知跳卡片"整条主链路。
- **失败留着原图**：没记成的那张截图会先存起来，等你点通知补录用；补录完或放弃了再清掉。

做完这片，整个 N06 在模拟器上用假数据就能肉眼验收全流程；只剩"真机用真快捷指令触发"这一步留给你自测。

## 本 TRD 负责什么

- 新增 `UNUserNotificationCenterNotifier`：实现切片 01 的 `NotificationSending`，把三类 `IntakeNotification` 构造成真实系统通知；内部处理权限申请与被拒降级（吞发送失败、不影响入账）。
- 新增 `TemporaryImageStore`：实现切片 01 的 `FailedImageStoring`，把失败原图写本机临时目录、返回 `imageRef`；提供清理入口（成功/放弃/补录完成后删）。
- 新增 `AppDelegate`（`UNUserNotificationCenterDelegate`）+ 深链路由状态：承接通知点击 → 路由到结果卡片 / 手动补录 / Key 配置。把 `RootTabView` 的 tab selection 与深链意图提升为可外部驱动。
- 把切片 01 App Intent `perform()` 里的 `NoOpNotifier`/`NoOpFailedImageStore` 替换为真实 `UNUserNotificationCenterNotifier`/`TemporaryImageStore`。
- 把 `ScreenshotIntakeSheet`「演示」按钮从"敬请期待"占位接成真实后台链路演示（复用切片 01 `BackgroundIntakeService`）。
- Info.plist 键（如需）+ DEBUG 端到端验收路径。

## 当前代码事实与上下游

**切片 01 已产出（本片消费/替换）**：`BackgroundIntakeService`、`NotificationSending`/`IntakeNotification`、`FailedImageStoring`/`NoOpFailedImageStore`/`NoOpNotifier`、`RecordAubadeScreenshotIntent`（含 `perform()` 里的 no-op 占位 + TODO(切片02)）、`AppModelContainer`。

**被扩展/接线**：

- `AubadeApp.swift`：当前 `@main struct AubadeApp: App`（`:4-15`），`WindowGroup { ContentView() }`。**无 `@UIApplicationDelegateAdaptor`、无通知 delegate**。本片加 `AppDelegate` 承接通知点击。
- `ContentView.swift`：极薄，仅 `RootTabView()`（`:6-10`），**无深链状态**。
- `RootTabView.swift:15-37`：`@State private var selectedTab: AppTab = .record`（**私有 State，未对外暴露**）；`RecordTabView(selection: $selectedTab)`（`:20`）已接受 selection 绑定。深链要"跳记账 Tab + 打开某 tx 卡片/补录"需把路由意图注入 RootTabView。
- `RecordTabView.swift`：`ScreenshotRoute` enum（`:20-29`，`.intro`/`.recognizing(ocrText:)`）单一 `fullScreenCover(item:)` 驱动（`:188-207`）；`ScreenshotIntakeSheet(recognizer: makeTextRecognizer()) { ocrText in ... }`（`:194`）当前只注入 recognizer。`makeTextRecognizer()`（`:106-115`）/`screenshotParser`（`:119-125`）/`screenshotRawText(ocrText:)`（`:129-131`）DEBUG/Release 注入范式已就绪。深链承接的"打开结果卡片/补录"落点需接入这里的 `editingTransaction`/route 状态或新增。
- `ScreenshotIntakeSheet.swift:26`：`Button("▶︎ 演示…") { showDemoPlaceholder = true }`；`:52-56` "敬请期待" alert。sheet 现注入 `recognizer` + `onRecognized` 回调（`:11-12`）。
- `TextRecognitionView.swift:46-61`：`TextRecognitionView(parser:categories:presetText:source:rawTextOverride:)` 有 `presetText`（进入即自动识别）；成功入账后 `resultTx` 触发 `RecognitionResultCard`（`:152-154`，private）。**通知点击"打开结果卡片"复用此通路**（见 §设计 3）。
- `ManualEntryView.swift:16`：`init(prefillNote: String? = nil)`。失败补录带原文复用它；带原图需加带默认值参数（见 §设计 3）。
- `KeySetupSheet`（`Recognition/KeySetupSheet.swift`）：无 Key 引导落点。
- `Enums.swift`/`Transaction.swift`：`.screenshotShortcut`、`imageRef` 就绪。
- pbxproj：`GENERATE_INFOPLIST_FILE=YES` + N04 加的麦克风/语音 `INFOPLIST_KEY_NS*UsageDescription`；无 extension target。

## 设计方案

### 1. 真实通知发送器 `UNUserNotificationCenterNotifier`

```swift
// Aubade/Features/Recognition/Shortcut/UNUserNotificationCenterNotifier.swift（新增）
import UserNotifications

/// 把 IntakeNotification 构造成真实本地通知。发送失败/无权限一律吞掉——绝不影响入账（约定 9）。
struct UNUserNotificationCenterNotifier: NotificationSending {
    /// userInfo key（点击路由据此解析深链意图）。
    enum Key { static let kind = "kind"; static let txID = "txID"; static let imageRef = "imageRef"; static let rawText = "rawText" }

    func send(_ notification: IntakeNotification) async {
        let center = UNUserNotificationCenter.current()
        // 申请权限（首次弹系统授权；已决定则立即返回当前态）。被拒 → 静默不发，不抛错。
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        switch notification {
        case let .success(txID, amountText, categoryName, merchant):
            content.title = "已记一笔"
            content.body = "¥\(amountText)" + (categoryName.map { " · \($0)" } ?? "") + (merchant.map { " · \($0)" } ?? "")
            content.userInfo = [Key.kind: "success", Key.txID: txID.uuidString]
        case let .failure(imageRef, rawText):
            content.title = "没识别出这张截图"
            content.body = "点此补录这笔账。"
            content.userInfo = [Key.kind: "failure", Key.imageRef: imageRef ?? "", Key.rawText: rawText ?? ""]
        case .missingKey:
            content.title = "请先配置 DeepSeek Key"
            content.body = "截图记账要用到 DeepSeek，点此去配置。"
            content.userInfo = [Key.kind: "missingKey"]
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil) // trigger nil = 立即
        try? await center.add(request)
    }
}
```

- **权限申请时机**：随首次发通知时 `requestAuthorization`（在后台入账成功/失败那一刻）。这满足"本节点只做自身必需申请"（约定 9）；统一收口/我的页开关留 N07。被拒 → `guard granted else { return }` 静默不发，入账已完成、不崩溃、不误记（约定 9）。
- **成功文案**"已记一笔 / ¥88.50 · 食 · 星巴克"对齐 PRD §3/技术基线 `:104`；分类/商户可空时省略。
- 通知**立即触发**（`trigger: nil`）。

### 2. 失败原图临时留存 `TemporaryImageStore`

```swift
// Aubade/Features/Recognition/Shortcut/TemporaryImageStore.swift（新增）
import Foundation

/// 后台失败时把原图写本机临时目录，返回 imageRef（文件名）。成功/放弃/补录完成后清理（约定 8）。
struct TemporaryImageStore: FailedImageStoring {
    /// 临时目录：NSTemporaryDirectory()/AubadeShortcutIntake（仅存后台失败待补录原图，非长期图库）。
    private var dir: URL { FileManager.default.temporaryDirectory.appendingPathComponent("AubadeShortcutIntake", isDirectory: true) }

    func save(_ imageData: Data) -> String? {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".img"
        let url = dir.appendingPathComponent(name)
        guard (try? imageData.write(to: url)) != nil else { return nil }
        return name                                   // imageRef = 文件名（相对临时目录）
    }
    func loadImage(ref: String) -> Data? { try? Data(contentsOf: dir.appendingPathComponent(ref)) }
    func remove(ref: String) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(ref)) }
    /// App 启动扫：清理孤儿（无对应 imageRef 账单的残留临时图）——由启动时调用（见 §清理触发点）。
    func purgeAll() { try? FileManager.default.removeItem(at: dir) }
}
```

- **imageRef 语义**：失败分支存"文件名"进 `imageRef`（不落库账单，仅通知 `userInfo` 携带 + 补录时带入）。**注意**：失败**不产生账单**（守脏账），所以 `imageRef` 不落在任何 Transaction 上——它只活在通知 `userInfo` 与临时文件里，供点通知补录时 `loadImage(ref:)` 取回。补录**成功**后新账单是手动补录产生的（`source=.manual`），是否把原图 ref 落到该账单的 `imageRef` 见 §3 补录带原图。
- **清理触发点**：① 补录完成或用户放弃 → `remove(ref:)`；② App 启动时 `purgeAll()` 清理上次残留（临时目录本就是"待补录缓冲"，启动即可清空——因为待补录意图只在"通知还在通知中心且未处理"期间有效，重启后从通知点入的场景本片按"尽力而为"处理，残留由启动清扫兜底，不做跨启动持久化补录队列，避免过度设计）。
- 成功入账 `imageRef` 恒 nil（切片 01 已定），不经此 store。

### 3. 通知点击深链路由（承接点 + 复用落点）

**承接点**：`AppDelegate` 实现 `UNUserNotificationCenterDelegate`，`userNotificationCenter(_:didReceive:)` 解析 `userInfo[kind]` → 发布一个深链意图；`AubadeApp` 用 `@UIApplicationDelegateAdaptor` 挂上，并把意图注入根视图。

```swift
// Aubade/App/AppDelegate.swift（新增）
import UIKit
import UserNotifications

/// 深链意图（通知点击 → 路由目标）。
enum DeepLinkIntent: Equatable {
    case openTransaction(UUID)        // 成功通知 → 结果卡片
    case manualEntry(rawText: String?, imageRef: String?)  // 失败通知 → 手动补录带原文/原图
    case configureKey                 // 无 Key 通知 → Key 配置
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// 观察型单例：根视图订阅 pendingIntent；delegate 收到点击写入。用 @Observable/ObservableObject。
    static let router = DeepLinkRouter()

    func application(_ app: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        switch info[UNUserNotificationCenterNotifier.Key.kind] as? String {
        case "success": if let s = info[...txID] as? String, let id = UUID(uuidString: s) { Self.router.pending = .openTransaction(id) }
        case "failure": Self.router.pending = .manualEntry(rawText: info[...rawText] as? String, imageRef: (info[...imageRef] as? String).flatMap { $0.isEmpty ? nil : $0 })
        case "missingKey": Self.router.pending = .configureKey
        default: break
        }
    }
    /// 前台也展示横幅：演示按钮在前台运行（ScreenshotIntakeSheet 内），iOS 默认抑制前台通知，
    /// 不实现此方法则验收 1「点演示亲眼看到弹通知」在前台看不到横幅。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@Observable @MainActor final class DeepLinkRouter { var pending: DeepLinkIntent? }
```

- `AubadeApp` 加 `@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate`，并把 `AppDelegate.router` 经 `.environment` 注入 `ContentView` → `RootTabView`。
- **`RootTabView` 消费深链**：`selectedTab` 保持 `@State`，新增 `.onChange(of: router.pending)`：收到意图 → `selectedTab = .record` + 把意图下传给 `RecordTabView`（新增一个 `deepLink: DeepLinkIntent?` 绑定/参数）。**冷启动/被杀态时序**：通知点击可能在 `RootTabView` 订阅前就写入 `router.pending`，纯 `.onChange` 不会对"初始已有值"触发。故除 `.onChange` 外，在根视图首个 `.task`/`.onAppear` **也消费一次 `router.pending`**（消费后置 nil，避免重复触发）。消费后置 nil 也保证同一意图不被 onChange + task 双触发。

**三类落点复用（关键：绕开 `RecognitionResultCard` 是 private）**：

- **成功 → 结果卡片**：`RecognitionResultCard` 是 `TextRecognitionView.swift:268` 的 **private struct**，外部不能直接实例化。**复用手法照抄 N04/N05**——不碰 private 卡片，`RecordTabView` 收到 `.openTransaction(id)` 时按 id `fetch` 出 tx，用 `TransactionEditor(.edit)` 打开（改金额/方向/分类/时间/商户/备注 + 完成回写），满足验收 3 的"可改/可删/看原文"。**关键落点必须满足验收 3 三件事**：
  - **可改**：`TransactionEditor(mode: .edit(tx), onSave: EditorActions.makeUpdate(...))`（`RecordTabView.swift:315-319` editSheet 已有此形态）。
  - **可删**：`editSheet` 当前**未注入 `onDelete`**（`RecordTabView.swift:314`）；深链成功落点需 `onDelete: EditorActions.makeDelete(...)` + 二次确认（照 `TextRecognitionView.swift:286-292` 的"先 dismiss 再 delete"手法——注意 `RecognitionResultCard` 就在 `TextRecognitionView.swift` 内，非独立文件）。
  - **可看原文**：`TransactionEditor` 支持 `rawText:` 入参（`TransactionEditor.swift:26/91`）；落点须显式传 `rawText: tx.rawText` 渲染折叠原文（现有 `editSheet:312-320` 未传，需补）。
  - **不污染既有入口（守验收 10）**：`RecordTabView` 的 `editingTransaction` sheet（`:208-210`）当前被"最近记录点击"复用（`:281`）。**给共享 editSheet 无条件加 onDelete/rawText 会让最近记录的编辑页也多出删除按钮 + 原文区，改动既有行为**。故深链成功落点**不复用同一 editSheet**，而是**新增一个独立的深链结果 sheet 状态**（如 `@State deepLinkResultTx: Transaction?`），只在这个 sheet 注入 `onDelete + rawText`；最近记录的 `editingTransaction` sheet 保持原样不动。这样"可改可删可看原文"齐备且零污染既有入口。
- **失败 → 手动补录带原文/原图**：复用 `ManualEntryView(prefillNote:)`（`:16` 已带默认值）带出原文（`rawText` 去掉 `[快捷指令]` 前缀或整串预填备注，对齐 N03 转手动带原文）。**带原图**：给 `ManualEntryView` 加 `init(prefillNote:prefillImageRef:)` 的 `prefillImageRef: String? = nil` **带默认值参数**（零破坏，照 `prefillNote` 范式）——补录页据 ref 从 `TemporaryImageStore.loadImage` 取图展示（缩略/占位），补录成功后把 ref 落到新账单 `imageRef` 并 `remove(ref:)`，或放弃时 `remove(ref:)`。**注意 v1 不做图库**（PRD §不做/全局 PRD `:105`）——原图仅补录期临时展示，不做长期附件管理。
- **无 Key → Key 配置**：复用 `KeySetupSheet`（对齐 `RecordTabView.swift:228-230` 无 Key sheet 手法），`RecordTabView` 收到 `.configureKey` 弹 `KeySetupSheet`。

### 4. 「演示」按钮接真实后台链路

`ScreenshotIntakeSheet`「演示」按钮（`:26` 现 `showDemoPlaceholder=true`、`:52-56` alert）改为**真跑一遍后台核心单元**：

- 给 `ScreenshotIntakeSheet` 补注入一个 `onDemo: () async -> Void` 回调（或直接注入 `BackgroundIntakeService`）。**取舍**：sheet 现只注入 `recognizer`（`:11`）；演示走全链路需 parser/store/notifier/imageStore。为不把一堆依赖塞进 sheet，**在 `RecordTabView` 构造 `BackgroundIntakeService` 并经 `onDemo` 闭包传入**——sheet 只管"点了演示按钮"，链路编排留在 RecordTabView（依赖注入集中处，对齐 `makeTextRecognizer()`/`screenshotParser` 已在此的范式）。
- 演示用的图片数据：DEBUG 下 OCR 走 `MockTextRecognizer`（不真正读图），故传任意占位 `Data`（如空 `Data()` 或内置 1x1）即可——`MockTextRecognizer` 按 `DebugScreenshotMockSettings` 的 behavior 返回定值/抛错，无需真图片。
- 演示注入 `screenshotParser`（DEBUG=`.screenshotSample` 88.5/星巴克/食）+ 真实 `UNUserNotificationCenterNotifier`（演示也弹真通知、可点击验证深链）+ `TemporaryImageStore`。
- **DEBUG mock 切分支**：复用 N05 `DebugScreenshotMockSettings`（`DebugMenuView.swift:19-20`，`MockTextRecognizer.Behavior` 成功/空/失败）——演示按钮按当前 mock 行为跑，可观察成功/失败通知；再配文本 mock（`DebugMockSettings`/`MockTransactionParser.Behavior` 无金额/网络/超时）观察解析失败分支通知。

### 5. Info.plist / pbxproj

- 本地通知（`UNUserNotificationCenter` 本地推送）**无需** `NSUserNotificationsUsageDescription` 之类键（本地通知权限走运行时 `requestAuthorization`，无 Info.plist 用途文案要求；区别于远程推送需 `aps-environment` entitlement）。**核实**：仅本地通知，不加远程推送 entitlement、不加后台模式键（App Intent 后台唤醒由系统 App Intents 机制驱动，非 `UIBackgroundModes`）。
- 若真机验证发现需要额外键，照 N04 `INFOPLIST_KEY_*` build setting 方式补（`GENERATE_INFOPLIST_FILE=YES` 现状）。**本片默认不加任何权限键**，除非编译/运行报缺失。

## 修改点

- 新增 `Aubade/Features/Recognition/Shortcut/UNUserNotificationCenterNotifier.swift`。
- 新增 `Aubade/Features/Recognition/Shortcut/TemporaryImageStore.swift`。
- 新增 `Aubade/App/AppDelegate.swift`（`AppDelegate` + `DeepLinkIntent` + `DeepLinkRouter`）；含 `didReceive`（点击解析）+ `willPresent`（前台也弹横幅，支撑演示可观察）。
- 改 `Aubade/AubadeApp.swift`：加 `@UIApplicationDelegateAdaptor(AppDelegate.self)`、注入 `DeepLinkRouter` 到根视图。
- 改 `Aubade/Features/AppShell/RootTabView.swift`：`.onChange(of: router.pending)` **+ 首个 `.task` 也消费一次**（冷启动时序）→ 切 `.record` tab + 下传深链意图给 `RecordTabView`；消费后置 nil 防重复。
- 改 `Aubade/Features/Record/RecordTabView.swift`：接深链意图——成功→**新增独立的深链结果 sheet 状态**（`@State deepLinkResultTx`，注入 `onDelete + rawText`，**不动最近记录的 `editingTransaction` sheet**，守验收 10）/ 失败→`ManualEntryView` 带原文原图 / 无 Key→`KeySetupSheet`；构造 `BackgroundIntakeService` 经 `onDemo` 传给说明卡。
- 改 `Aubade/Features/Recognition/Screenshot/ScreenshotIntakeSheet.swift`：「演示」按钮从 alert 占位改为调 `onDemo` 回调；移除/保留 `showDemoPlaceholder`（改为真实链路后不再需要"敬请期待" alert）。
- 改 `Aubade/Features/Record/ManualEntryView.swift`：`init` 加 `prefillImageRef: String? = nil` 带默认值参数 + 补录期原图展示 + 补录成功落 `imageRef`/清理。
- 改 `Aubade/Features/Recognition/Shortcut/RecordAubadeScreenshotIntent.swift`：`perform()` 里 `NoOpNotifier`/`NoOpFailedImageStore` → 真实 `UNUserNotificationCenterNotifier`/`TemporaryImageStore`（去掉切片 01 的 TODO）。
- App 启动清理：`AubadeApp` 或 `AppDelegate.didFinishLaunching` 调 `TemporaryImageStore().purgeAll()` 清上次残留。
- 单测（可测部分）：`UNUserNotificationCenterNotifier` 的 `userInfo` 构造可抽纯函数单测（给定 `IntakeNotification` → 断言 title/body/userInfo，不真弹）；`TemporaryImageStore` save→load→remove 冒烟；`DeepLinkRouter`/`AppDelegate` userInfo 解析 → `DeepLinkIntent` 映射单测。真弹通知/真点击/真机后台由用户自测。

## 验证点

（可观察验收 = DEBUG「演示」mock 端到端 + 单测；真机项标注"真机自测"。对齐 PRD 验收 1-10。）

1. **演示端到端（PRD 验收 1 的 mock 等价，主可观察路径）**：记账页「📷」→ 说明卡 →「▶︎ 演示」（DEBUG OCR mock=成功）→ 后台核心单元跑完 → 生成一笔 `.screenshotShortcut` 已入账账单（88.5/支出/食/星巴克、`rawText` 带 `[快捷指令]` 前缀、金额 Decimal 无误差）→ 弹真实成功通知「已记一笔 · ¥88.50 · 食」。
2. **成功通知点击 → 可改/删/看原文（PRD 验收 3）**：点成功通知 → 切记账 Tab + 打开该 tx 编辑（可改金额/方向/分类/时间/商户/备注、完成回写、删除二次确认撤销、展开看带前缀原文）；统计/剩余同步刷新。
3. **失败不误记 + 失败通知 + 补录（PRD 验收 4/13 后台）**：DEBUG OCR mock=空/失败 或 parser mock=无金额/网络/超时 → 演示**不生成账单**、原图写临时目录、弹"没识别出，点此补录"→ 点击进手动补录、带出原文（原图缩略/占位展示）。
4. **无 Key 后台提示（PRD 验收 5/11 后台）**：清 Key 后点演示 → 不记账、弹"请先配置 Key"→ 点击开 `KeySetupSheet`；不崩溃、手动记账不受影响。
5. **原图留存/清理（PRD 验收 7 边界）**：失败保留原图（补录可取回）；补录完成/放弃后清理；成功入账不留原图（`imageRef` nil）；App 启动清残留。
6. **单测**：`UNUserNotificationCenterNotifier` userInfo 构造映射、`TemporaryImageStore` save/load/remove、`DeepLinkRouter` userInfo→intent 解析；切片 01 `BackgroundIntakeServiceTests` 仍绿。
7. **真机（自测）**：真快捷指令传图 → 后台入账 + 真机通知交付 + 点击深链；后台时间预算是否容纳一次 DeepSeek 往返（不足则触发方案 B，本节点不实现）。
8. **不越界/不回归**：不做 App Group/迁移/权限统一收口/我的页/首次引导/通知开关（N07）；不碰 N05 相册流程（仅接同卡演示按钮）；N03/N04/N05 落库与既有行为不变；`recognizeAndSave`/OCR provider 零签名改动；`ManualEntryView` 加带默认值参数不破坏 N01/N03 调用。

## 不做什么

- 不做通知开关 / 权限统一收口 / 我的页设置 / 首次引导集中申请（N07）——本片只做后台入账自身必需的一次 `requestAuthorization` 与被拒静默降级。
- 不做远程推送（无 `aps-environment` entitlement）、不做 `UIBackgroundModes` 后台模式键（App Intents 后台唤醒由系统机制驱动）。
- 不做原图长期留存/图库/附件管理（v1 不做，全局 PRD `:105/:127`）——仅补录期临时留存 + 清理。
- 不做跨启动持久化补录队列（残留由启动 `purgeAll` 兜底，尽力而为）。
- 不实现方案 B 降级（PRD §7，仅记录预案，真机数据触发后另行调整）。
- 不改 `PersistenceController` 建库；不建 App Group / extension target。
- 不重写 N03/N05 OCR/解析层/结果卡片/Key/归一。
