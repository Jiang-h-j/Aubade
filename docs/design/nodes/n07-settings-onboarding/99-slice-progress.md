# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n07-settings-onboarding/03-onboarding-flow-trd.md`
- 下一个 TRD：`docs/design/nodes/n07-settings-onboarding/04-notification-toggle-permission-trd.md`
- 更新时间：2026-07-16T10:31:27+08:00

## 上一次 TRD 开发

N07 切片 03「首次启动引导两步流程 + onboarding 完成标志 + 根路由分流」实现完成。全新安装第一次打开由 `ContentView` 按 `AppConfig.hasOnboarded` 分流进入两步引导：①录初始总额（可跳过，调既有 `setBalanceBaseline`）→ ②提示配 DeepSeek Key（可跳过，复用既有 `KeySetupSheet()`）→ `finish()` 置 `hasOnboarded=true`，`ContentView` body 重算切 `RootTabView`（默认落 `.record` 记账页）。红线守住：两步都能不输入任何内容空走完、`hasOnboarded=true` 全仓唯一在 `finish()` 置位（中途退出下次从头，无断点续引导）。分流挂 `ContentView` 内而非 `AubadeApp`，seed/purge/容器注入零改动。

## 涉及文件和符号

- **改** `Aubade/ContentView.swift`：加 `@AppStorage(AppConfig.hasOnboardedKey) hasOnboarded`，body 从「仅 `RootTabView()`」改为按标志分流 `RootTabView` / `OnboardingView`。
- **改** `Aubade/Persistence/AppConfig.swift`：新增 `static func hasOnboarded(_ defaults: UserDefaults = .standard) -> Bool`（`object(forKey:) as? Bool ?? hasOnboardedDefault`，与 `overspendThreshold(_:)` 对称），把 View body 分流不可直测的判据收敛成可单测纯读取。
- **新增** `Aubade/Features/Onboarding/OnboardingView.swift`：两步引导视图（`enum Step {.balance/.key}` + `@State step/balanceInput/showingKeySheet`）。步①照抄 `InitialBalanceSheet` 的 posix Decimal 校验（>=0，无 Double 中转）+「下一步」（有值落基线、无值也进）+「先跳过」ghost；步②「去填写」开 `.sheet{KeySetupSheet()}` +「开始记账」`finish()`。`store` 用 `LedgerStore(modelContext)` 注入 context（非链式容器，无悬垂陷阱）。视觉对齐原型 renderOnboard（🌅 + Aubade + 步进文案 + 内容区 + 主按钮 + ghost 跳过）。
- **新增** `AubadeTests/OnboardingRoutingTests.swift`：3 个用例断言分流判据——默认 false（进引导）/ 置 true（进主界面）/ 跨读取保持不回退，注入独立 `UserDefaults(suiteName:)` + defer 清理，不污染 .standard。

## 验证情况

- **编译**：全 target（生产+测试）`** TEST BUILD SUCCEEDED **`（iPhone 17 模拟器）。folder-based 项目，新增文件自动纳入编译无需改 pbxproj。
- **测试**：`xcodebuild test-without-building -only-testing:AubadeTests/OnboardingRoutingTests -only-testing:AubadeTests/StatisticsAggregatorTests` → 新增 3 个 + 回归 13 个（含切片 01 的 `testAppConfigOverspendThresholdFallbackAndClamp`）全绿，0 失败。
- **jflow-review**：1/3 轮 PASS，零阻断。两只读子 agent 并行：①代码事实/正确性（9 项 CONFIRMED：注入 context 无 SIGTRAP 悬垂、`setBalanceBaseline`/`KeySetupSheet()` 签名精确匹配、posix Decimal 无 Double 中转、`@AppStorage` 同 key 分流重算成立、单测独立 suite 不污染、AubadeApp seed/purge/容器注入未破坏）；②TRD 范围/边界（负责 5 条全落地、修改点匹配、「不做什么」7 条逐条未越界、两条红线守住、无过度设计——步②双按钮并列比 TRD 设想的「sheet 关后动态变文案」更简，属避免过度设计）。两条非阻断建议见下。

## 遗留风险和注意事项

- 可观察项（真机/模拟器）：全新安装/清 `hasOnboarded` key → 首次进引导两步 → 落记账 Tab；重启不再进引导（验收 1）；录了初始总额的我的页/账单页显示该值、两步都跳过的剩余「未设置」（验收 1 后半）；跨重启保持（验收 8）。分流判据已由单测覆盖，UI 流程建议真机跑一遍确认。
- 非阻断建议（未采纳，记此备查）：①步②按钮视觉权重可对调（「开始记账」用 prominent、「去填写」用 ghost）——TRD 未规定样式，当前实现不违规；②`AppConfig.hasOnboarded(_:)` 可补进 TRD 03「修改点」章节（TRD 验证点已点名要求此函数，属授权范围，纯文档自洽）。
- 新增两个未 track 文件（`Aubade/Features/Onboarding/OnboardingView.swift`、`AubadeTests/OnboardingRoutingTests.swift`），提交需 `git add` 这两个新文件 + 两个改动文件。

## 下一次开发

1. 读取 `current.json.next_trd`，确认值仍为 `docs/design/nodes/n07-settings-onboarding/04-notification-toggle-permission-trd.md`。
2. 读取该 TRD 同目录的 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `docs/design/nodes/n07-settings-onboarding/04-notification-toggle-permission-trd.md`，只实现该 TRD 切片。

补充说明：
1. 读取 `current.json.next_trd`，应指向切片 04 `docs/design/nodes/n07-settings-onboarding/04-notification-toggle-permission-trd.md`（N07 最后一个切片）。
2. 读该 TRD 同目录 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 切片 04 主题：通知开关 gating（`UNUserNotificationCenterNotifier.send` 内读 `AppConfig.notificationsEnabled`，关则不发、入账不受影响，对 `BackgroundIntakeService`/`SpyNotifier` 单测零改动）+ 我的页通知开关 + 统一权限降级组件 `PermissionDenialNotice`（收敛 `VoiceCaptureView:232` 纯文本 + 加「去系统设置」入口，覆盖语音/麦克风/通知）+ 通知开关 gating 单测。依赖切片 01 的 `AppConfig.notificationsEnabledKey`（已定义待 04 消费）。
4. 切片 04 是 N07 最后一片，完成后需更新 DAG 节点 N07 状态为已完成；N07 是 greenfield DAG 第八个（最后一个）节点，其后无下一节点，按 `config.json.main_branch`（当前 null，需询问）或仓库默认分支合并主线。
5. 提交沿用 `feat/n07` 分支（本 feature 已确立，不再询问）。
