# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n06-shortcut-background/01-background-intake-intent-trd.md`
- 下一个 TRD：`docs/design/nodes/n06-shortcut-background/02-notification-deeplink-demo-trd.md`
- 更新时间：2026-07-15T18:21:07+08:00

## 上一次 TRD 开发

N06 切片01：后台截图入账链路的"发动机"——脱 UI、脱真系统通知的纯逻辑底座，全分支单测焊死。

- **共享容器持有点** `AppModelContainer`（`@MainActor` 单例，`let container` 长期持有，规避 SIGTRAP 悬垂陷阱）；`AubadeApp` 容器来源改为它（主 App 与后台 Intent 共享同一实例）。
- **通知意图抽象**：`IntakeNotification` 值类型（成功/失败/无 Key 三类）+ `NotificationSending` 协议 + `FailedImageStoring` 协议 + 两个 NoOp 实现。两协议标 `@MainActor` 隔离（非 `Sendable`），与核心单元调用链一致。
- **后台链路核心单元** `BackgroundIntakeService`（`@MainActor` struct）：`intake(imageData:)` 按 OCR→读 Key→解析归一落库（复用 `RecognitionEntry.recognizeAndSave`）→发通知意图 编排；失败各分支不落脏账，解析失败分支 `store.context.rollback()` 守脏账；落库 `.screenshotShortcut`、`rawText` 带 `[快捷指令]` 前缀。
- **App Intent 入口薄壳** `RecordAubadeScreenshotIntent`（`@Parameter image: IntentFile`，`perform()` 仅装配依赖注入 NoOp + 调核心单元）+ `AubadeShortcuts`（AppShortcutsProvider）。
- **单测** `BackgroundIntakeServiceTests`：8 用例（成功/无 Key/OCR 空/OCR 失败/超时/无网/无金额/不回归），spy 通知器 + spy imageStore 断言"发哪类通知 + 是否留原图"。

## 涉及文件和符号

- 新增 `Aubade/Persistence/AppModelContainer.swift`（`AppModelContainer.shared.container`）。
- 改 `Aubade/AubadeApp.swift:7`（容器来源 → `AppModelContainer.shared.container`，唯一既有文件改动）。
- 新增 `Aubade/Features/Recognition/Shortcut/IntakeNotification.swift`（`IntakeNotification` / `NotificationSending` / `FailedImageStoring` / `NoOpNotifier` / `NoOpFailedImageStore`）。
- 新增 `Aubade/Features/Recognition/Shortcut/BackgroundIntakeService.swift`（`BackgroundIntakeService.intake(imageData:)`）。
- 新增 `Aubade/Features/Recognition/Shortcut/RecordAubadeScreenshotIntent.swift` + `AubadeShortcuts.swift`。
- 新增 `AubadeTests/BackgroundIntakeServiceTests.swift`。
- 无 Info.plist / pbxproj 改动（新文件经 PBXFileSystemSynchronizedRootGroup 自动纳入 target）。

## 验证情况

- **编译**：`build-for-testing` 通过（含 `import AppIntents`，主 App target，无 extension）。修复了一处本片引入的 Swift 6 warning：spy 类 `@MainActor` conformance 冲突——根因是协议标 `Sendable`（nonisolated 要求）与 spy 的 MainActor 状态冲突，改协议为 `@MainActor` 隔离解决，零本片 error/warning。
- **单测**：全 122 绿；本片 `BackgroundIntakeServiceTests` 8 用例独立跑绿（含加强后的成功用例 `rawText` 完整相等断言）；既有 `RecognitionEntryScreenshotTests`/`VoiceProviderTests`/`ScreenshotOCRProviderTests`/`MockParserTests` 不回归。
- **jflow-review**：1/3 轮 PASS，零阻断。两独立只读子 agent（①正确性+并发+脏账 ②守纪+范围+PRD 覆盖）均 PASS。已采纳 2 条非阻断修复：测试文件 `:27/:34` 过时注释订正、成功用例 rawText 补完整相等断言。未采纳 3 条（child context 隔离回滚 / Key 协议化 DI / seed 兜底）——涉及扩大范围或改设计，TRD 已明确排除或留切片02。

## 遗留风险和注意事项

- **真机验证项（不阻塞节点门禁，用户自测）**：真快捷指令传图机制、`IntentFile.data` 真机取值、后台执行时间预算能否容纳一次 DeepSeek 往返、后台通知交付。**若真机实测后台预算普遍不足 → 触发技术基线 §7.3 方案 B 降级**，本节点默认不实现。
- **rollback 作用域**（评审非阻断 1）：`store.context.rollback()` 作用于共享 mainContext，语义是丢弃该 context 全部 pending 变更。当前后台执行时前台通常不活跃、与既有 `TextRecognitionView` 手法一致，风险低；若后续要严格隔离可让后台链路用 child ModelContext。
- **Keychain 测试造态耦合全局单例**（评审非阻断 2）：`KeychainStore` 无协议抽象，测试读写真实 `KeychainStore.shared`，靠 setUp/tearDown clear 收敛，串行不污染；一旦开启并行测试有理论 flaky 风险。
- **后台 categories 依赖主 App 已 seed**（评审非阻断 3）：`perform()` 不走 `ContentView().task` 的 seed；用户须先开 App 配 Key（届时已 seed），风险有限。

## 下一次开发

1. 读取 `current.json.next_trd`，确认值仍为 `docs/design/nodes/n06-shortcut-background/02-notification-deeplink-demo-trd.md`。
2. 读取该 TRD 同目录的 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `docs/design/nodes/n06-shortcut-background/02-notification-deeplink-demo-trd.md`，只实现该 TRD 切片。

补充说明：
- 切片01 已完成并通过评审。**下一步：切片02** `docs/design/nodes/n06-shortcut-background/02-notification-deeplink-demo-trd.md`。
- 切片02 内容：`UNUserNotificationCenterNotifier` 真实通知 + 权限/被拒降级、`TemporaryImageStore` 失败原图留存清理、`AppDelegate`/`DeepLinkRouter` 点击深链（成功→编辑卡片 / 失败→补录带原文原图 / 无Key→Key配置）、「演示」按钮接后台链路、DEBUG 端到端。
- 切片02 把切片01 的 `RecordAubadeScreenshotIntent.perform()` 里的 `NoOpNotifier()` / `NoOpFailedImageStore()`（两处 `// TODO(切片02)`）替换为真实实现。
- 恢复命令：`按照 TRD 开发`。分支已在 `feat/n06`。
