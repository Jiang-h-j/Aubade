# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n07-settings-onboarding/02-profile-budget-key-category-trd.md`
- 下一个 TRD：`docs/design/nodes/n07-settings-onboarding/03-onboarding-flow-trd.md`
- 更新时间：2026-07-16T10:15:44+08:00

## 上一次 TRD 开发

N07 切片 02「我的页预算设置 + DeepSeek Key 状态行 + 分类只读查看」实现完成。给「我的」页 List 补齐三块设置，全是纯新增 UI + 调既有能力、零签名改动：①预算设置——周/月预算填写与清空，调既有 `LedgerStore.setBudget`（写侧唯一化）/`delete`；②DeepSeek Key 状态行——读 `KeychainStore.isConfigured` 显示「已配置✓/去填写›」，点击开既有 `KeySetupSheet`；③分类一览——`@Query` 预置分类按方向分组只读展示。

## 涉及文件和符号

- **改** `Aubade/Features/AppShell/RootTabView.swift`：
  - `ProfilePlaceholderView` 加 `@Query budgets`、`@Query(isPreset==true, sort sortOrder) presetCategories`、`@State editingBudgetPeriod/showingKeySheet/keyConfigured`、`currentBudget(_:)` helper。
  - 新增 `budgetSection`（周/月行 + 当前值 + chevron，点击开 sheet）、`keySection`（Key 状态行，绿勾/去填写切换）、`categorySection`（`categoryTags` 按 direction 分组，LazyVGrid + Capsule 只读标签，无任何点击/增删改入口）。
  - List 组装顺序 `balance→budget→threshold→key→category→#if DEBUG`（与 TRD 一致）。
  - 加两个 `.sheet`：预算 `.sheet(item: $editingBudgetPeriod)`（onSave 调 setBudget、onClear 删该周期 Budget）、Key `.sheet(isPresented:onDismiss:)`（关闭重读 isConfigured 刷新）；额外加 `.onAppear` 兜底跨路径刷新 keyConfigured。
  - 新增 `private struct BudgetEditSheet`（照抄 InitialBalanceSheet 的 posix Decimal 校验范式，但预算须 > 0；带 periodType 语义标题 + 清空按钮 role .destructive）。
  - 新增 `extension BudgetPeriodType: Identifiable`（`.sheet(item:)` 前提，rawValue 唯一，与 internal enum 访问级别对齐）。
- **改** `AubadeTests/ModelCRUDTests.swift`：新增 `testClearBudgetOnlyRemovesTargetPeriod`（清空周预算→周删除、月预算 3000 存活，验证 onClear 单周期删除不误伤）。

## 验证情况

- **编译**：全 target（生产 + 测试）`** TEST BUILD SUCCEEDED **`，纯新增 UI 零签名改动、编译即验证核心风险。
- **测试**：`xcodebuild test-without-building -only-testing:AubadeTests/ModelCRUDTests` 6 个全绿（0 失败），含新增 `testClearBudgetOnlyRemovesTargetPeriod` + 回归 `testSetBudgetUniquePerPeriod`（唯一化）/`testBudgetCRUD`。预算唯一化与 Decimal 精度由既有 `testSetBudgetUniquePerPeriod`/`DecimalPrecisionTests` 覆盖，本片只补未覆盖的清空语义，不重复造轮子。
- **jflow-review**：1/3 轮 PASS，零阻断。两只读子 agent 并行：①代码事实/正确性（8 项 CONFIRMED：setBudget/delete/isConfigured 调用签名全对、onDismiss 刷新链路成立、Identifiable 前提满足且唯一定义、读侧依赖写侧唯一化、清空 onClear 精确删目标周期、分类纯只读无入口、清空单测有效、store 用注入 modelContext 无悬垂 context 陷阱）；②TRD 范围/需求边界（修改点六项全落地、List 顺序一致、「不做什么」七条逐条未越界、验收 2/4/5 路径清晰、无过度设计）。采纳两条非阻断建议：删多余 `public var id` 修饰符（保持与 internal enum 一致）、加 `.onAppear` 兜底跨路径刷新 keyConfigured（修复「在 N03 识别流程配 Key 后切回我的页状态行不刷新」的真实跨 Tab 场景）；均已修复并重新编译通过。未采纳「LazyVGrid 换普通布局」（TRD 给定选项、agent 判定无害，换反增风险）。

## 遗留风险和注意事项

- UI→统计页联动即时性（设预算后统计页进度条生效 = 验收 2）、Key 行 sheet 交互切换（验收 4）、分类标签实际渲染（验收 5）为真机/模拟器观察项，落库路径已由单测覆盖，UI 联动逻辑经子 agent 核对成立，建议真机跑一遍确认。
- `keyConfigured` 为 `@State` 镜像，现由 `onDismiss`（我的页内即时）+ `onAppear`（跨 Tab 切回兜底）双重刷新覆盖；若未来 Key 配置改非 sheet 方式（如 push）需同步刷新逻辑。
- 本片改动均在既有 track 文件（`RootTabView.swift`/`ModelCRUDTests.swift`），无新增未 track 文件，提交无需额外 `git add` 新文件。

## 下一次开发

1. 读取 `current.json.next_trd`，确认值仍为 `docs/design/nodes/n07-settings-onboarding/03-onboarding-flow-trd.md`。
2. 读取该 TRD 同目录的 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `docs/design/nodes/n07-settings-onboarding/03-onboarding-flow-trd.md`，只实现该 TRD 切片。

补充说明：
1. 读取 `current.json.next_trd`，应指向切片 03（首次启动引导：录初始总额→提示配置 Key 可跳过→落空账本记账页，消费 `AppConfig.hasOnboarded`）。
2. 读该 TRD 同目录 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 切片 01（AppConfig 地基，含 `hasOnboardedKey` 已定义待 03 消费）、切片 02（我的页三 Section）均已完成；切片 03 首次引导可直接消费 `AppConfig.hasOnboardedKey`（切片 01 已定义、零消费留给 03）与既有 `InitialBalanceSheet`/`KeySetupSheet`。
4. 提交沿用 `feat/n07` 分支（切片 01 已确立，本 feature 不再重复询问分支）。
