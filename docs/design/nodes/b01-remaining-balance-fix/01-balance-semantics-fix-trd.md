# TRD 01 - 剩余口径修复 + 单测同步

## 给用户看的摘要

这一片就是修 bug 本体：把 `BalanceCalculator` 里那行「只算初始总额之后的账」删掉，改成对**全部**账单加减。改完，你先记 3 笔 10 元支出、再录初始总额 1000，剩余就会显示 **970** 而不是纹丝不动的 1000。同时把一条锁着旧口径的单测改成新口径，并补一条「早于初始总额录入时刻的账也要算进去」的正向断言，保证以后不会有人手滑改回去。纯逻辑 + 单测，不碰任何界面。

## 本 TRD 负责什么

- 删除 `BalanceCalculator.remaining` 的 `occurredAt >= establishedAt` 日期过滤，改为对全部 `transactions` 按方向求和。
- 同步更新函数内注释（`:9-10`），删除「基线后 / 约定 2」旧口径描述，改写为新全量口径。
- 更新 `testBaselineBoundaryInclusive`：从「早于基线不计」改为「早于基线也计入」，并补一条正向断言对齐验收 1、3。
- 覆盖 PRD 验收标准 1、2、3、6。

## 当前代码事实与上下游

**唯一改动的业务代码**（`Aubade/Features/Analytics/BalanceCalculator.swift:12-18`，行号写作时快照）：

```swift
/// 剩余 = initialAmount + Σ(基线后收入) − Σ(基线后支出)。            // :9  旧口径注释
/// "基线后" = `occurredAt >= establishedAt`（PRD 已确认约定 2，同刻计入）。  // :10 旧口径注释
/// baseline 为 nil 时返回 nil —— 视图显示"—"，引导用户先录初始总额。  // :11
static func remaining(transactions: [Transaction], baseline: BalanceBaseline?) -> Decimal? {
    guard let baseline else { return nil }                          // :13  不动
    let after = transactions.filter { $0.occurredAt >= baseline.establishedAt }  // :14  ← 删这行过滤
    return baseline.initialAmount
        + sum(after, direction: .income)                           // :16  after → transactions
        - sum(after, direction: .expense)                          // :17  after → transactions
}
```

- `sum(_:direction:)`（`:21-25`）纯 `Decimal` reduce，**不动**，切片 01 继续复用。
- `guard let baseline`（`:13`）**不动**：`baseline == nil` 仍返回 nil、视图显示「未设置/—」（验收 5 的分支，本片不涉改，天然保持）。

**读侧调用点（不改，自动受益）**：

- `RootTabView.swift:102-103` — 我的页剩余总额。
- `LedgerTabView.swift:83` — 账单页 hero 剩余总额。
  两处都只是调用 `remaining(...)` 拿返回值渲染，口径改对后它们显示的数字自动变对，无需改动。

**不可误改的红线点**（全项目「基线后过滤」仅 `:14` 一处，其余 `establishedAt` 读取点都不是过滤点）：

- 写入侧：`LedgerStore.createBalanceBaseline/setBalanceBaseline`、`OnboardingView:95`、`RootTabView:128`、`DebugMenuView:159`。
- 挑最新基线：`LedgerStore:115`、`LedgerTabView:73`、`RootTabView:99`。
- `StatisticsAggregator`：用统计周期区间过滤 `occurredAt`，与 `establishedAt` 无关，不受影响。

**待改单测**（`AubadeTests/BalanceCalculatorTests.swift:91-102`）：`testBaselineBoundaryInclusive` 现构造「同刻计入 100 + 早 1 秒排除 50 + 晚 1 秒计入 30」，断言 `1000+100+30=1130`（显式锁旧口径「早 1 秒的 50 被排除」）。新口径下 50 必须计入，断言随之改为 `1180`。

## 设计方案

**改法（去过滤，全量求和）**：删掉 `:14` 的 `let after = ...` 过滤行，把 `:16-17` 两处 `sum(after, ...)` 改回 `sum(transactions, ...)`。`remaining` 变为：

```swift
/// 剩余 = initialAmount + Σ(全部收入) − Σ(全部支出)。对全部账单求和，
/// 不按 occurredAt 与 establishedAt 先后过滤——早于初始总额录入时刻的账也参与加减（B01 推翻 N02 约定 2）。
/// baseline 为 nil 时返回 nil —— 视图显示"—"，引导用户先录初始总额。
static func remaining(transactions: [Transaction], baseline: BalanceBaseline?) -> Decimal? {
    guard let baseline else { return nil }
    return baseline.initialAmount
        + sum(transactions, direction: .income)
        - sum(transactions, direction: .expense)
}
```

`establishedAt` 此后在 `remaining` 内不再被读取——这是预期的（新口径不看它）；`baseline.initialAmount` 仍在用，`guard let baseline` 仍需要（区分 nil 分支），故不会有未使用告警。

**单测改法（`testBaselineBoundaryInclusive`）**：函数名保留不变（该用例仍覆盖「基线时刻附近三笔账（同刻/早 1 秒/晚 1 秒）的计入行为」，只是断言值随口径更新；改名无实际收益、徒增 diff）。三笔构造不变、断言值从 `1130` 改为 `1180`（`1000+100+50+30`），并更新注释说明「早 1 秒的 50 现也计入」（不再有「边界排除」语义）。**新增一条独立正向用例** `testTransactionsBeforeBaselineIncluded`，机制上对齐验收 1、3（早于基线仍计入）：初始总额 1000 + 一笔早于 `establishedAt` 的 10 元支出 → 剩余 990（旧口径会得 1000）。

## 修改点

- **改** `Aubade/Features/Analytics/BalanceCalculator.swift`：
  - `:9-11` 注释三行改写为新全量口径描述（删「基线后 / 约定 2 / occurredAt >= establishedAt」）。
  - `:14` 删除 `let after = transactions.filter { $0.occurredAt >= baseline.establishedAt }`。
  - `:16-17` `sum(after, ...)` → `sum(transactions, ...)`（两处）。
  - `sum` 函数、`guard let baseline`、签名、返回类型不动。
- **改** `AubadeTests/BalanceCalculatorTests.swift`：
  - `testBaselineBoundaryInclusive`（`:91-102`）：断言 `1130` → `1180`，更新注释（早 1 秒的 50 现计入，删「边界 `>=` 排除」措辞）；方法名保留不变（不新增/删除/重命名其他现有用例）。
  - 新增 `testTransactionsBeforeBaselineIncluded`：`makeBaseline("1000", established)` + 一笔 `established` 之前的 10 元 expense → 断言 `remaining == 990`，复用现有 `date()`/`makeTx()`/`makeBaseline()` helper。

## 验证点

1. **单测全绿**（`xcodebuild test`，iPhone 模拟器）：`BalanceCalculatorTests` 全部通过——改后的 `testBaselineBoundaryInclusive`（1180）、新增 `testTransactionsBeforeBaselineIncluded`（990）、以及未动的 `testRemainingNilWithoutBaseline`/`testRemainingFormula`/`testRemainingDecimalPrecision`/写侧唯一化/`testMonthlySum`/`testSumEmptyIsZero` 均绿。
2. **回归**：`StatisticsAggregatorTests` 全绿（本片不碰统计链路，应零影响）。
3. **可观察（验收 1、2）**：全新库，先记 3 笔各 10 元支出、再录初始总额 1000 → 我的页/账单页剩余显示 **970**；再记 1 笔 20 元收入 → 显示 **990**。
4. **可观察（验收 3）**：把某笔消费日期改到初始总额录入时刻之前 → 该笔仍计入剩余（数字随之变化）。
5. **nil 分支不回归（验收 5）**：未录初始总额时 `remaining` 返回 nil、视图显示「未设置/—」（`guard let baseline` 未改，天然保持）。

## 不做什么

- 不改 `sum(_:direction:)`、不改 `remaining` 签名与返回类型、不引入 `Double`。
- 不动 `baseline == nil` 分支逻辑与其视图呈现。
- 不改任何 `establishedAt` 写入侧与「挑最新基线」读取点（红线，误改引新 bug）。
- 不动 `StatisticsAggregator` / 统计周期过滤 / `AnalyticsTabView`。
- 不删除或重命名 `BalanceCalculatorTests` 中除 `testBaselineBoundaryInclusive` 外的现有用例。
- 不碰任何 UI（D7 提示是切片 02 的事）。
- 不碰 B02~B04 范围，不改数据模型、无 SwiftData 迁移。
