# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n07-settings-onboarding/04-notification-toggle-permission-trd.md`
- 下一个 TRD：`全部完成`
- 更新时间：2026-07-16T10:50:27+08:00

## 上一次 TRD 开发

N07 切片 04「通知开关 gating + 权限被拒统一降级提示」实现完成，N07 节点全部 4 个切片收尾。① 通知总开关：`UNUserNotificationCenterNotifier.send` 开头读 `notificationsEnabled()`，关则 return——入账已完成、不受影响（关的是通知、不是记账）；我的页新增「通知」Section（Toggle + 系统级被拒时「去系统设置」引导）。② 统一权限降级：新增 `PermissionDenialNotice`（文案三要素「受影响功能 + 去系统设置 + 手动不受影响」），把 `VoiceCaptureView` 语音权限被拒的纯文本收敛到该组件 + 加「去系统设置」按钮。③ gating 判定抽成 `nonisolated static notificationsEnabled(_:)` 供单测注入独立 suite 断言。红线守住：`NotificationSending` 协议/`BackgroundIntakeService`/`RecordAubadeScreenshotIntent` 注入点/`SpyNotifier` 全零改动，后台入账链路照常落库。

## 涉及文件和符号

- **改** `Aubade/Features/Recognition/Shortcut/UNUserNotificationCenterNotifier.swift`：`send:27` 加 `guard Self.notificationsEnabled() else { return }`；新增 `nonisolated static func notificationsEnabled(_ defaults:)`（:47-49，`object(forKey:) as? Bool ?? default`，与 `AppConfig.overspendThreshold(_:)` 同范式）。标 `nonisolated` 因该类型经 `NotificationSending` 协议为 @MainActor 隔离，纯 UserDefaults 读取脱隔离供同步单测直调。
- **新增** `Aubade/Features/Permission/PermissionDenialNotice.swift`：`enum DeniedPermission {.microphoneOrSpeech/.notification}`（`affectedFeature` 派生受影响功能名）+ `enum PermissionDenialCopy`（文案三要素）+ `struct PermissionDenialNotice: View`（文案 + 「去系统设置」按钮跳 `openSettingsURLString`）。
- **改** `Aubade/Features/AppShell/RootTabView.swift`：`ProfilePlaceholderView` 加 `@AppStorage(AppConfig.notificationsEnabledKey) notificationsEnabled`(:86) + `@State systemNotifDenied`(:88) + `notificationSection`(:195-207，插在 thresholdSection 与 keySection 之间) + `openSystemSettings()`(:209) + `.task`(:145-148) 查 `notificationSettings().authorizationStatus == .denied`；`import UserNotifications`。
- **改** `Aubade/Features/Recognition/Voice/VoiceCaptureView.swift`：`statusText` 的 `.failed` 拆成 `.failed(.microphoneDenied), .failed(.speechDenied)`（:116 渲染 `PermissionDenialNotice(.microphoneOrSpeech)`）与 `.failed(let err)`（:120 兜底其余保留 `failedMessage`）。`failedMessage` 函数本身未改。
- **新增** `AubadeTests/NotificationGatingTests.swift`：3 用例断言 `notificationsEnabled(_:)` 未设→true / 设 false→false / 设 true→true，各注入独立 `UserDefaults(suiteName:)` + defer 清理，不污染 .standard。

## 验证情况

- **编译**：全 target（生产+测试）`** TEST BUILD SUCCEEDED **`（iPhone 17 模拟器）。folder-based 项目，新增文件自动纳入编译无需改 pbxproj。首轮编译因 `notificationsEnabled` 继承 @MainActor 隔离、单测同步上下文无法调用而失败，加 `nonisolated` 修复后通过。
- **测试**：`xcodebuild test-without-building`（iPhone 17）跑 4 个 suite 共 27 个用例全绿，0 失败——新增 3 个 `NotificationGatingTests` + 回归 8 个 `BackgroundIntakeServiceTests`（含 SpyNotifier 断言，验证 gating 不影响 service 逻辑）+ 3 个 `OnboardingRoutingTests` + 13 个 `StatisticsAggregatorTests`。
- **jflow-review**：1/3 轮 PASS，零阻断。两只读子 agent 并行：①代码正确性/并发安全（5 项通过：gating 默认 true 回退正确、`nonisolated static` 脱 @MainActor 安全、`.task` 回写 @State 在 MainActor 上下文、SpyNotifier/协议/注入点零改动、@AppStorage 与发送器读同一 .standard key 开关切换即时生效、VoiceCaptureView switch 穷举完备）；②TRD 范围/边界（负责 4 条全落地、修改点清单一致、「不做什么」6 条逐条未违反、文案三要素齐全、验证点单测一致、无过度设计）。

## 遗留风险和注意事项

- 可观察项（真机/模拟器，未跑）：我的页关通知开关 → N06「演示」跑后台入账 → **不弹通知、但账单出现在列表/统计**；重开 → 恢复弹通知（验收 6）。系统级通知权限被拒时开关旁显示「去系统设置」、点击跳系统设置页。拒麦克风/语音 → 语音面板显示统一降级（三要素 + 去设置按钮），App 不崩不卡、手动记账可用；相册免授权选图不受影响（验收 7）。gating 判定已单测覆盖，UI 端到端建议真机跑一遍确认。
- 非阻断（记此备查，均符合 TRD、不改）：① `DeniedPermission.notification` case 目前「已定义未消费」——我的页通知降级用内联 Button 文案而非 `PermissionDenialNotice(.notification)`，属 TRD §3 明确设计（enum 覆盖三类、通知降级呈现收敛到我的页开关旁引导）。② `VoiceCaptureView.failedMessage` 的 `.microphoneDenied/.speechDenied` 分支现不可达（被 statusText 前置特化拦截），因 switch 需穷举而保留、无害。③ gating 依赖 App Intent 在主 app 进程 perform（`UserDefaults.standard` 才与 @AppStorage 共享）；当前 `RecordAubadeScreenshotIntent` 在主 target 成立，若未来迁独立 extension 需改 App Group suiteName——属既存架构前提，非本切片引入。④ `systemNotifDenied` 仅 `.task` 查一次，用户跳设置改权限返回需视图重新 appear 才刷新——TRD §2 明确「查一次」，符合设计。
- 新增两个未 track 文件（`Aubade/Features/Permission/PermissionDenialNotice.swift`、`AubadeTests/NotificationGatingTests.swift`），提交需 `git add` 这两个新文件 + 三个改动文件。

## 下一次开发

全部 TRD 已完成。下一次若继续，请从 PRD 验收标准和最终验证情况开始检查。

补充说明：
N07 是 greenfield DAG 第八个（最后一个）节点，本切片 04 是 N07 最后一片，**N07 节点全部完成**。下一步动作：
1. 更新 DAG 文档 `docs/design/aubade-v1-dev-dag.md` 中 N07 节点状态为已完成。
2. N07 之后无下一节点（DAG 收尾）。提交沿用 `feat/n07` 分支（本 feature 已确立）。
3. 主线合并：`config.json.main_branch` 为 null、`git status` 起始主分支为 `main`——**是否把 `feat/n07` 合并到 `main` 需先询问用户**（主线合并不自动执行）。
4. 若用户确认，全部 8 个 DAG 节点完成即 Aubade v1 开发 DAG 收尾，可考虑整体验收。
