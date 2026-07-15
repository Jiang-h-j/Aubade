# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n06-shortcut-background/02-notification-deeplink-demo-trd.md`
- 下一个 TRD：`全部完成`
- 更新时间：2026-07-15T20:09:34+08:00

## 上一次 TRD 开发

N06 切片02：把切片01 的后台"发动机"接成看得见点得动的完整主入口——真弹通知、点通知能跳、演示按钮变真的、失败留原图。

- **真实通知发送** `UNUserNotificationCenterNotifier`（实现切片01 `NotificationSending`）：三类 `IntakeNotification` → 系统本地通知；`makeContent` 抽纯函数供单测；随首次发通知 `requestAuthorization`，被拒 `guard granted` 静默不发、`try? add` 吞错——绝不影响入账（约定9）。
- **失败原图临时留存** `TemporaryImageStore`（实现 `FailedImageStoring`）：写 `temporaryDirectory/AubadeShortcutIntake`，`save/loadImage/remove/purgeAll`；补录/放弃 `onDisappear remove`、App 启动 `purgeAll` 兜底残留。
- **通知点击深链** `AppDelegate`（`UNUserNotificationCenterDelegate`）+ `DeepLinkRouter`（`@Observable @MainActor`）：`didReceive` 解析 userInfo→`DeepLinkIntent`（`intent(from:)` 纯函数）、`willPresent` 前台也弹横幅（支撑演示可见）。三类落点：成功→独立 `DeepLinkResultSheet`（`TransactionEditor.edit` + onDelete 二次确认 + rawText，可改/删/看原文，守验收3）、失败→`ManualEntryView` 带原文原图、无Key→`KeySetupSheet`。
- **深链时序**：`RootTabView`（onChange + 首个 task 双入口消费 `router.pending`）→ 切 record tab + 下传 `$pendingDeepLink` → `RecordTabView`（onChange + task）承接；消费后置 nil 防重复、防冷启动订阅前丢失。**不污染既有入口**（守验收10）：成功落点用独立 sheet，最近记录 `editSheet` 保持原样不加 onDelete/rawText。
- **演示按钮接后台链路**：`ScreenshotIntakeSheet` 加 `onDemo` 回调，`RecordTabView.runBackgroundDemo` 构造真实 `BackgroundIntakeService`（依赖注入集中处）真跑一遍、弹真通知；移除"敬请期待"占位 alert。
- **App Intent 换真实实现**：`perform()` 里 `NoOpNotifier`/`NoOpFailedImageStore` → `UNUserNotificationCenterNotifier`/`TemporaryImageStore`，删两处 TODO；`IntakeNotification.swift` 删两个已无引用的 NoOp。
- **ManualEntryView/TransactionEditor 带原图**：均加带默认值参数（`prefillImageRef` / `attachmentImageData`），零破坏现有调用；补录页展示原图缩略，成功落 `imageRef`。

## 涉及文件和符号

新增：
- `Aubade/Features/Recognition/Shortcut/UNUserNotificationCenterNotifier.swift`（`send` + `makeContent` 纯函数 + `Key`/`Kind` 常量）
- `Aubade/Features/Recognition/Shortcut/TemporaryImageStore.swift`（`save/loadImage/remove/purgeAll`）
- `Aubade/App/AppDelegate.swift`（`AppDelegate` + `DeepLinkIntent` + `DeepLinkRouter` + `intent(from:)` 纯函数）
- `AubadeTests/ShortcutNotificationDeepLinkTests.swift`（19 用例）

修改：
- `Aubade/AubadeApp.swift`（`@UIApplicationDelegateAdaptor` + `.environment(router)` + 启动 `purgeAll`）
- `Aubade/ContentView.swift` / `RootTabView.swift`（Preview 注入 router；RootTabView 深链承接下传）
- `Aubade/Features/Record/RecordTabView.swift`（三类深链落点 + `runBackgroundDemo` + `prefillNote` + `DeepLinkResultSheet` + `DeepLinkManualEntry`）
- `Aubade/Features/Record/ManualEntryView.swift`（`prefillImageRef` 带默认值 + 原图取回/清理）
- `Aubade/Features/Editor/TransactionEditor.swift`（`attachmentImageData` 带默认值 + `attachmentSection`）
- `Aubade/Features/Recognition/Screenshot/ScreenshotIntakeSheet.swift`（`onDemo` + `runDemo` + 遮罩；删占位 alert）
- `Aubade/Features/Recognition/Shortcut/IntakeNotification.swift`（删 NoOp 两实现）
- `Aubade/Features/Recognition/Shortcut/RecordAubadeScreenshotIntent.swift`（换真实依赖）
- 无 Info.plist / pbxproj 改动（本地通知无需权限键/entitlement；新文件经 PBXFileSystemSynchronizedRootGroup 自动纳入）

## 验证情况

- **编译**：`build-for-testing`（iPhone 17 模拟器 / Debug）通过，零 error / 零本片 warning（含 `import AppIntents`/`UserNotifications`/`@UIApplicationDelegateAdaptor`）。
- **单测**：全 **141 绿**（切片01 后 122 → 本片新增 19 = 141），0 failures。本片 `ShortcutNotificationDeepLinkTests` 覆盖 makeContent 三类映射（含 nil/空串省略）、TemporaryImageStore save/load/remove/purgeAll/缺失ref、AppDelegate.intent 解析（成功/坏UUID→nil/失败带值/空串→nil/missingKey/未知kind→nil/空dict→nil）、prefillNote 去前缀。既有 `BackgroundIntakeServiceTests`/`RecognitionEntryScreenshotTests` 等不回归。
- **jflow-review**：1/3 轮 PASS，零阻断。两独立只读子 agent（①正确性+Swift6并发+SwiftData+深链时序 ②守纪+范围+PRD/TRD覆盖+不回归）均 PASS。已采纳 1 条非阻断修复：`makeContent` 空串分类/商户会产生尾部 " · "，改 `compactMap` 过滤空串 + 补空串省略单测。未采纳（TRD 明确接受/低优先）：openTransaction 全表fetch（数据量小）、onDisappear 悬空 imageRef（TRD §169 v1 不读回原图接受）、Release 演示恒失败（TRD §159 接受）。

## 遗留风险和注意事项

- **真机验证项（不阻塞节点门禁，用户自测）**：真快捷指令传图 → 后台入账 + 真机通知交付 + 点击深链；后台执行时间预算能否容纳一次 DeepSeek 往返。**若真机后台预算普遍不足 → 触发技术基线 §7.3 方案 B 降级**，本节点默认不实现。
- **补录成功后 `imageRef` 悬空**：补录成功新账单落 `imageRef`（文件名），但 `onDisappear` 已 `remove` 临时文件——账单只存字符串、v1 不从账单读回原图，故无影响；M9 做图库时需重新设计留存。
- **openTransaction 全表 fetch**：`consumeDeepLink` 取单条 tx 用全表 fetch + 内存 first，数据量增大后可换 predicate；当前数据量小，与既有 todayCount 同风格。
- **深链 sheet 与最近记录 editSheet 并存**：靠入口互斥保证同帧仅一个激活，维持互斥约定防回归（与既有三 fullScreenCover 同类权衡）。

## 下一次开发

全部 TRD 已完成。下一次若继续，请从 PRD 验收标准和最终验证情况开始检查。

补充说明：
- **本切片是 N06 节点最后一个 TRD**（`completed_trds` 将含 01+02，`next_trd` 应为空）。切片02 完成即 **N06 节点全部切片实现完毕**。
- 下一步动作：`complete-trd` 推进状态后，**更新 DAG（`docs/design/aubade-v1-dev-dag.md`）标记 N06 节点完成**，并按 DAG 找下一个可开发节点（N04/N07），把 `next_action` 指向生成该节点 PRD。若无后续节点则按主线合并流程处理。
- 提交：分支 `feat/n06`，提交信息 `feat(n06): 实现切片02 真实通知+权限降级+点击深链路由+演示接线+原图留存清理`。
- 恢复命令：`继续按照 Jflow 推进` 或 `按照 TRD 开发`（但 N06 已无下一 TRD，orchestrator 应转向 DAG 下一节点）。
