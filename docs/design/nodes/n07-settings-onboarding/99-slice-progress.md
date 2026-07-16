# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n07-settings-onboarding/01-config-center-budget-threshold-trd.md`
- 下一个 TRD：`docs/design/nodes/n07-settings-onboarding/02-profile-budget-key-category-trd.md`
- 更新时间：2026-07-16T09:41:34+08:00

## 上一次 TRD 开发

N07 切片 01「生产配置中心 + 超支阈值可配」实现完成。立住两块地基:①集中生产配置 `AppConfig`(供后续三片共用);②统计页超支阈值从写死 80% 改为可配设置项(默认仍 80%,行为不变)。本节点唯一有编译波及的签名改动(`budgetProgress` 加 `nearThreshold` 入参)已一次性收口,全调用点同步无遗漏。

## 涉及文件和符号

- **新增** `Aubade/Persistence/AppConfig.swift`:`enum AppConfig` 集中三项 UserDefaults key + 默认值(`hasOnboarded`/`notificationsEnabled` 本片只定义留 03/04,`overspendThreshold` 本片消费)+ `overspendThreshold(_:)` 读取兜底(`object(forKey:) as? Int ?? 80` 避开 integer 返 0 坑,夹到 50~100)。
- **改** `StatisticsAggregator.swift`:`budgetProgress` 加 `nearThreshold: Int = AppConfig.overspendThresholdDefault` 入参,`pct >= 80` → `pct >= nearThreshold`;`BudgetState` 注释同步。保持无状态纯函数(阈值由调用方注入)。
- **改** `AnalyticsTabView.swift`:加 `@AppStorage(AppConfig.overspendThresholdKey) overspendThreshold`;`budgetProgressView` 调用传 `nearThreshold: overspendThreshold`。
- **改** `RootTabView.swift`:`ProfilePlaceholderView` 加 `@AppStorage overspendThreshold` + `thresholdSection`(Stepper 50~100 步进 5),插入 List(balanceSection 后、DEBUG 入口前)。
- **改** `StatisticsAggregatorTests.swift`:新增 `testBudgetProgressRespectsNearThreshold`(80/50 两组边界)+ `testAppConfigOverspendThresholdFallbackAndClamp`(独立 UserDefaults suite,未设→80/30→50/120→100/65→65)。

## 验证情况

- **编译**:全 target(生产 + 测试)编译通过 —— 签名改造后全调用点同步无遗漏,编译即验证本片核心风险。
- **测试**:`xcodebuild test -only-testing:AubadeTests/StatisticsAggregatorTests` 13 个全绿(0 失败),含新增 2 个 + 回归的 `testBudgetProgressThresholds`/`testBudgetProgressZeroBudgetGuard`(默认 80 行为不变)。
- **jflow-review**:1/3 轮 PASS,零阻断。两只读子 agent 并行:①代码事实/签名同步(全仓 grep `budgetProgress` 无遗漏调用点、AppConfig 兜底边界正确、@AppStorage 双处同 key 同默认、纯函数保持、测试有效)CONFIRMED;②TRD 范围/需求边界(改动 = 修改点 5 项、逐条核对「不做什么」无越界、`hasOnboarded`/`notificationsEnabled` 零消费、验收点全覆盖、未改既有对外签名)CONFIRMED。

## 遗留风险和注意事项

- `overspendThreshold(_:)` 非视图读取入口本片仅测试消费,为切片 04 通知发送器预留(前瞻设计,子 agent 判定合理)。
- 阈值联动为同进程 `@AppStorage` 共享 key,依赖 SwiftUI 对 UserDefaults 变更的重算;真机跨 Tab 即时性在切片 02/03 我的页真机联调时可顺带观察。
- `AppConfig.swift` 为未 track 新文件,提交时需 `git add`。

## 下一次开发

1. 读取 `current.json.next_trd`，确认值仍为 `docs/design/nodes/n07-settings-onboarding/02-profile-budget-key-category-trd.md`。
2. 读取该 TRD 同目录的 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `docs/design/nodes/n07-settings-onboarding/02-profile-budget-key-category-trd.md`，只实现该 TRD 切片。

补充说明：
- 切片 01 已完成,下一步开发**切片 02**:`docs/design/nodes/n07-settings-onboarding/02-profile-budget-key-category-trd.md`(我的页预算设置 sheet + Key 状态行复用 `KeySetupSheet` + 分类只读查看,纯新增 UI 零签名改动)。
- 恢复动作:读该 TRD + `99-slice-progress.md`,确认依赖切片 01 的 `AppConfig` 与金额输入范式已就位,按 jflow-dev 实现。
- 提交前需向用户确认分支策略(本 feature 首次提交,`config.json.main_branch` 为 null、无既定约定):直接提交当前 `feat/n07` 分支,还是另开分支。
