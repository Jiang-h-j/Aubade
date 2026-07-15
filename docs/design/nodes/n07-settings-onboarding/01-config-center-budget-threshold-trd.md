# TRD 01 - 生产配置中心 + 超支阈值可配（含签名改造 + 全调用点同步）

## 给用户看的摘要

先把两块"地基"立住：① 一个集中的**生产配置**存放点（以后 onboarding 标志、通知开关、超支阈值都存这里，不散落各处）；② 把统计页"接近预算就提醒"的阈值从**写死的 80%** 改成**你能调的设置项**（默认还是 80%，不动它就跟现在一模一样）。这一片改完，统计页多出一个可调的"超支提示阈值"，我的页多一个设置它的入口。

## 本 TRD 负责什么

- 新增 `AppConfig`：集中定义本节点三项生产配置的 UserDefaults key 与默认值（本片只用到 `overspendThreshold`，另两项 `hasOnboarded`/`notificationsEnabled` 一并定义好，供切片 03/04 直接用）。
- `StatisticsAggregator.budgetProgress` 加 `nearThreshold` 入参（默认 80），把硬编码 `pct >= 80` 改为 `pct >= nearThreshold`。
- **同步全部调用点**：生产 `AnalyticsTabView.budgetProgressView:310` + 测试 `StatisticsAggregatorTests:184-200`（PRD 只提了前者，本片显式补后者）。
- 我的页 `ProfilePlaceholderView` 增"超支提示阈值"设置项（读写 `AppConfig.overspendThreshold`）。
- 阈值驱动单测（80/50 两组 normal/near/over 边界）。

## 当前代码事实与上下游

- `StatisticsAggregator.budgetProgress(spent:budget:) -> (pct:Int, state:BudgetState)`（`StatisticsAggregator.swift:116-124`）：纯函数、无状态；`:121` 硬编码 `else if pct >= 80 { state = .near }`。
- **生产调用点唯一**：`AnalyticsTabView.budgetProgressView:310` `StatisticsAggregator.budgetProgress(spent: expenseTotal, budget: budget)`。
- **测试调用点（PRD 漏点，本片必须一并改）**：`StatisticsAggregatorTests.swift`
  - `:184` `budgetProgress(spent: 79, budget: 100).state` → `.normal`
  - `:185` `budgetProgress(spent: 80, budget: 100).state` → `.near`
  - `:186` `budgetProgress(spent: 100, budget: 100).state` → `.near`
  - `:187` `budgetProgress(spent: 101, budget: 100).state` → `.over`
  - `:190-192` `budgetProgress(spent: 2055, budget: 1500)` → `pct 137/.over`
  - `:196-200` `budgetProgress(spent: 100, budget: 0)` → `(0, .normal)`（除零兜底）
  - 加默认值入参后**这些调用不传 nearThreshold 仍走默认 80、行为不变**，故最小改动是"不改这些调用"，只**新增**阈值驱动测试；但需确认默认值语义（见"设计方案"）。
- 生产配置现状：生产零 UserDefaults；DEBUG mock key 集中在 `DebugMenuView.swift:7/13/19`（`enum XxxSettings { static let key }` + `@AppStorage` 范式）。
- 我的页 `ProfilePlaceholderView`（`RootTabView.swift:64-123`）：`@Query`/`store`/`List` + `balanceSection` + DEBUG 调试入口；本片在 List 追加阈值 Section。

## 设计方案

### 1. `AppConfig` 集中配置（新增文件 `Aubade/Persistence/AppConfig.swift`）

照 `DebugMockSettings` 范式，一个 `enum` 集中 key + 默认值。放 `Persistence/`（与 `KeychainStore` 同层，语义都是"配置持久化"）。

```swift
import Foundation

/// 本节点（N07）首次引入的生产配置集中定义（PRD 已确认约定 8）。
/// key 集中、默认值集中；视图用 @AppStorage(key) 绑定，非视图读 UserDefaults.standard。
/// Key（DeepSeek）仍走 Keychain、不在此（业务规则 12）。
enum AppConfig {
    /// 首次引导完成标志（切片 03）。默认 false = 未引导。
    static let hasOnboardedKey = "config.hasOnboarded"
    static let hasOnboardedDefault = false

    /// 截图后台入账通知总开关（切片 04）。默认 true = 开。
    static let notificationsEnabledKey = "config.notificationsEnabled"
    static let notificationsEnabledDefault = true

    /// 超支提示阈值（百分比整数，本片）。默认 80 = 与现状一致。
    static let overspendThresholdKey = "config.overspendThreshold"
    static let overspendThresholdDefault = 80

    /// 阈值合理范围（我的页 stepper/slider 约束 + 读取兜底）：50~100，步进 5。
    static let overspendThresholdRange = 50...100
    static let overspendThresholdStep = 5

    /// 非视图读超支阈值：注册默认值 + 兜底夹到合理范围（防脏值 / 未注册返回 0）。
    static func overspendThreshold(_ defaults: UserDefaults = .standard) -> Int {
        let raw = defaults.object(forKey: overspendThresholdKey) as? Int ?? overspendThresholdDefault
        return min(max(raw, overspendThresholdRange.lowerBound), overspendThresholdRange.upperBound)
    }
}
```

> 说明：`overspendThreshold(_:)` 用 `object(forKey:) as? Int ?? default` 而非 `integer(forKey:)`——后者未设值返回 0，会让"没配过"退化成阈值 0（永远 near）。默认参数 `.standard` 便于单测注入独立 `UserDefaults(suiteName:)`。

### 2. `budgetProgress` 加阈值入参（`StatisticsAggregator.swift`）

```swift
static func budgetProgress(spent: Decimal, budget: Decimal,
                           nearThreshold: Int = AppConfig.overspendThresholdDefault)
    -> (pct: Int, state: BudgetState) {
    guard budget > 0 else { return (0, .normal) }
    let pct = roundedPercent(spent, of: budget)
    let state: BudgetState
    if pct > 100 { state = .over }
    else if pct >= nearThreshold { state = .near }
    else { state = .normal }
    return (pct, state)
}
```

- 默认值 `= AppConfig.overspendThresholdDefault`（80）：**保证现有测试 6 处不传参调用行为完全不变**（回归安全），也保证任何未显式传参的地方走默认。
- 纯函数属性保持：阈值由**调用方**读 `AppConfig` 后传入，聚合器不读 UserDefaults（不污染纯函数、单测可直接传不同阈值）。

### 3. 生产调用点同步（`AnalyticsTabView.budgetProgressView:310`）

`budgetProgressView` 读 `AppConfig.overspendThreshold()` 传入。视图内用 `@AppStorage` 绑定阈值，保证我的页改阈值后统计页实时重算：

```swift
// AnalyticsTabView 顶部加：
@AppStorage(AppConfig.overspendThresholdKey) private var overspendThreshold = AppConfig.overspendThresholdDefault

// budgetProgressView 内：
let progress = StatisticsAggregator.budgetProgress(
    spent: expenseTotal, budget: budget, nearThreshold: overspendThreshold)
```

> `@AppStorage` 让阈值变化驱动 `AnalyticsTabView` body 重算（我的页与统计页共享同一 UserDefaults key，切 Tab 回来即时生效；同进程 `@AppStorage` 变更亦触发刷新）。

### 4. 测试调用点同步（`StatisticsAggregatorTests.swift:184-200`）

- 现有 6 处不传 `nearThreshold` 的调用：**保持不变**（走默认 80，断言值不变，即回归保护）。
- **新增**阈值驱动测试（见"验证点"），显式传 `nearThreshold:`。

### 5. 我的页"超支提示阈值"设置项（`ProfilePlaceholderView`）

在 List 追加一个 Section（放在 balanceSection 之后、DEBUG 入口之前）：

```swift
@AppStorage(AppConfig.overspendThresholdKey) private var overspendThreshold = AppConfig.overspendThresholdDefault

private var thresholdSection: some View {
    Section("预算提醒") {
        Stepper(value: $overspendThreshold,
                in: AppConfig.overspendThresholdRange,
                step: AppConfig.overspendThresholdStep) {
            HStack {
                Text("超支提示阈值")
                Spacer()
                Text("\(overspendThreshold)%").foregroundStyle(.secondary).monospacedDigit()
            }
        }
    } footer: {
        Text("支出达到预算的该比例时，统计页预算条转为「接近」提醒。默认 80%。")
    }
}
```

- 用 `Stepper`（50~100 步进 5）：无需 Decimal（整数百分比）、无键盘校验负担、范围天然受约束——比 slider/输入框更少出错。呈现形态本片定为 Stepper（PRD 把形态留给 TRD）。

## 修改点

- **新增** `Aubade/Persistence/AppConfig.swift`：`enum AppConfig` 集中三项 key/默认值 + `overspendThreshold(_:)` 读取兜底。
- **改** `Aubade/Features/Analytics/StatisticsAggregator.swift:116`：`budgetProgress` 加 `nearThreshold: Int = AppConfig.overspendThresholdDefault` 入参，`:121` 改 `pct >= nearThreshold`。
- **改** `Aubade/Features/Analytics/AnalyticsTabView.swift`：加 `@AppStorage overspendThreshold`；`budgetProgressView:310` 调用传 `nearThreshold: overspendThreshold`。
- **改** `Aubade/Features/AppShell/RootTabView.swift`：`ProfilePlaceholderView` 加 `@AppStorage overspendThreshold` + `thresholdSection`，插入 List。
- **改** `AubadeTests/StatisticsAggregatorTests.swift`：新增阈值驱动测试（现有 6 处调用保持不变）。

## 验证点

- **可编译**：全 target 编译通过（改签名后生产 + 测试调用点全部同步，无遗漏——这是本片核心风险，编译即验证）。
- **阈值驱动单测**（新增 `testBudgetProgressRespectsNearThreshold`）：
  - `nearThreshold: 80` → 79%→`.normal`、80%→`.near`、100%→`.near`、101%→`.over`（等价现有默认行为）。
  - `nearThreshold: 50` → 49%→`.normal`、50%→`.near`、100%→`.near`、101%→`.over`（验证阈值真的驱动 `.near` 判定）。
  - Decimal 无浮点误差（复用现有 `spent: 2055, budget: 1500 → 137%` 精度断言思路）。
- **AppConfig 兜底单测**（新增，注入独立 `UserDefaults(suiteName:)`）：未设值→返回 80；设 30（越下界）→夹到 50；设 120（越上界）→夹到 100。
- **回归**：现有 `testBudgetProgressThresholds:183` / `testBudgetProgressZeroBudgetGuard:196` 不改、仍绿（默认 80 行为不变）。
- **可观察**：我的页调阈值到 50% → 统计页某周期支出到 50% 即转橙色"接近"；调回 80% 表现与改动前一致。

## 不做什么

- 不做通知开关 gating、不做 onboarding 引导（`AppConfig` 里定义了 key 但本片不消费，留切片 03/04）。
- 不重做统计页预算进度条/超支展示的**渲染**（N02 已做，本片只改阈值判定来源与设置入口）。
- 不改 `budgetProgress` 的除零兜底、pct 计算、`.over` 判定（仅 `.near` 阈值参数化）。
- 阈值不做按周/月分别配置（一个全局阈值，PRD 未要求分周期）。
- 不删 DEBUG 预算硬编码入口（`DebugMenuView:70-75` 保留）。
