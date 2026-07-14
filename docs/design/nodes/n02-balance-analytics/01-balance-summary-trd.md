# TRD 01 - 剩余金额 + 账单页汇总卡 + 我的页初始总额

> 节点 PRD：`docs/prd/nodes/n02-balance-analytics-prd.md`。上游：N00 数据层 + N01 账单列表（38d98ee）。
> 行号为写作时快照，可能 ±1 漂移。

## 给用户看的摘要

这一片做完，你能**录一个初始总额，然后随时看到"还剩多少钱"**：

- 进「我的」Tab，顶部出现剩余总额 + 「录入初始总额 / 调整初始总额」按钮，第一次点进去填个数（比如 12000），剩余总额就有了。
- 进「账单」Tab，列表顶部立起一张汇总卡：**剩余总额 · 本月支出 · 本月收入**。之后每记一笔收入就加、支出就减，改删账单它立刻跟着变。
- 还没录初始总额时，剩余总额显示"—"，引导你去录。

这片**不做**统计 Tab（下一片），也不做预算/Key/分类管理等完整设置（N07）。

## 本 TRD 负责什么

M6 剩余金额的**完整闭环**（PRD 目标 1、6，需求范围 §1、§2）：

1. 剩余金额**派生计算纯函数** `BalanceCalculator`（无状态、可单测）：`剩余 = initialAmount + Σ(基线后收入) − Σ(基线后支出)`，`occurredAt >= establishedAt` 为"基线后"，无基线返回 `nil`。
2. `BalanceBaseline` 的**写入 + 唯一化**（`LedgerStore` 新增方法）：录入/调整初始总额时保证库中只有一条有效基线。
3. **账单页汇总卡**：在 `LedgerTabView` 顶部插入剩余总额 · 本月支出 · 本月收入。
4. **我的页初始总额区块**：`ProfilePlaceholderView` 顶部新增剩余总额展示 + 调整初始总额 sheet。

## 当前代码事实与上下游

- **模型**：`BalanceBaseline`（`Aubade/Models/BalanceBaseline.swift`）`initialAmount: Decimal`、`establishedAt: Date`；注释（`:10`）"剩余派生不建字段，计算在 N02"。`Transaction.amount: Decimal`（正值）、`direction`、`occurredAt`（`Transaction.swift:7-9`）。
- **Store**（`Aubade/Store/LedgerStore.swift`）：已有 `createBalanceBaseline(initialAmount:establishedAt:)`（`:83`）、`fetch<T>(_:predicate:sortBy:)`（`:17`）、`delete<T>`（`:92`）。**无 update/唯一化基线方法**——本片新增。
- **账单页**（`Aubade/Features/Ledger/LedgerTabView.swift`）：body 为 `VStack(spacing:0){ filterBar; content }`（`:38-41`），注释明确"不含顶部汇总卡；汇总区 → N02"（`:8`）。汇总卡插在 `filterBar` 之上。`@Query` 全量取（`:13`）。
- **我的页**（`Aubade/Features/AppShell/RootTabView.swift:51` `ProfilePlaceholderView`）：DEBUG 下是 `NavigationStack{ List{ 占位 Section; 开发者 Section } }`（`:53-69`），Release 是 `ContentUnavailableView`。本片在其顶部加剩余总额区块。
- **格式化**：`AmountFormat.plainString(_:)`（`:31`，无符号千分位）用于剩余/合计展示；`signedString`（`:23`）备用。
- **本月区间**：复用 `LedgerFilter.DateRangeFilter.thisMonth` + `contains(_:now:calendar:)`（`LedgerFilter.swift:53,59-60`），本月支出/收入= 对全量按 `.thisMonth` 过滤后按方向求和。
- **demo 口径**：剩余 `data.js:96 remaining()`（demo 为全量简化，本片按 PRD 用**基线后**精确口径）；汇总卡 `app.js:104-113`；我的页 `app.js:662-668、707-717`（"录入初始总额/调整初始总额"按钮文案随有无基线切换）。

## 设计方案

### 1. `BalanceCalculator`（新增纯函数，`Aubade/Features/Analytics/BalanceCalculator.swift`）
无状态 enum，注入数据，不触库：

```
enum BalanceCalculator {
    /// 剩余 = initialAmount + Σ(occurredAt>=establishedAt 的收入) − Σ(同条件支出)。
    /// baseline 为 nil 时返回 nil（视图显示"—"）。
    static func remaining(transactions: [Transaction], baseline: BalanceBaseline?) -> Decimal? {
        guard let baseline else { return nil }
        let after = transactions.filter { $0.occurredAt >= baseline.establishedAt }
        let income = after.filter { $0.direction == .income }.reduce(Decimal(0)) { $0 + $1.amount }
        let expense = after.filter { $0.direction == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
        return baseline.initialAmount + income - expense
    }
    /// 区间内按方向求和（供汇总卡本月支出/收入复用；纯 Decimal）。
    static func sum(_ transactions: [Transaction], direction: TransactionDirection) -> Decimal {
        transactions.filter { $0.direction == direction }.reduce(Decimal(0)) { $0 + $1.amount }
    }
}
```

- `occurredAt >= establishedAt`（PRD 已确认约定 2）。纯 `Decimal` reduce，不经 Double。
- 新建目录 `Aubade/Features/Analytics/` 存放本节点聚合纯函数（切片 02 的 `StatisticsAggregator` 同目录）。

### 2. `LedgerStore` 基线唯一写入（新增方法）
读侧取最新、写侧唯一化（PRD 已确认约定 3）：

```
/// 设置/调整唯一初始总额基线：删除所有既有 BalanceBaseline，再插入一条新的。
/// establishedAt 传入以便测试注入（生产传 Date()）。
func setBalanceBaseline(initialAmount: Decimal, establishedAt: Date) throws {
    let existing = try fetch(BalanceBaseline.self)
    for b in existing { context.delete(b) }
    _ = try createBalanceBaseline(initialAmount: initialAmount, establishedAt: establishedAt)
}
/// 读当前有效基线：取 establishedAt 最新一条（防御多条）。
func currentBaseline() throws -> BalanceBaseline? {
    try fetch(BalanceBaseline.self, sortBy: [SortDescriptor(\.establishedAt, order: .reverse)]).first
}
```

- 唯一化用"清空+插入"而非 update：`BalanceBaseline` 无业务主键，且量极小（0~1 条），清插最简单且天然收敛到一条。`createBalanceBaseline` 内部已 `save`（`:83`）。
- **调整初始总额时 `establishedAt` 更新为当前时刻**——语义：新基线代表"此刻账户合计的新起点"，之后的账单相对新基线增减。（同日边界由 `>=` 处理，见验证点。）

### 3. 账单页汇总卡（改 `LedgerTabView`）
- 新增私有子视图 `summaryCard`，插入 body：`VStack(spacing:0){ summaryCard; filterBar; content }`（`:38` 处）。
- 新增 `@Query private var baselines: [BalanceBaseline]`（全量，量极小）→ 取最新一条传入 `BalanceCalculator.remaining`。
- 本月支出/收入：`let month = LedgerFilter.apply(allTransactions, category: .all, dateRange: .thisMonth, now: Date(), calendar: cal)`，再 `BalanceCalculator.sum(month, direction:)`。`cal` 用 `firstWeekday=2` 的 gregorian（与切片 02 统一，本片本月不涉周首日但保持一致）。
- 剩余为 nil 显示"—"；金额走 `AmountFormat.plainString`。

### 4. 我的页初始总额（改 `ProfilePlaceholderView`）
- 抽出独立视图 `ProfileView`（替换 `ProfilePlaceholderView` body 内容，保留 DEBUG 调试入口 Section）：顶部 Section 显示剩余总额（大数字/"—"）+ 按钮（`rem==nil ? "录入初始总额" : "调整初始总额"`，对齐 demo `app.js:668`）。
- 点按钮弹 `.sheet`：`TextField` 数字输入（`.keyboardType(.decimalPad)`）→ `Decimal(string:)` 解析校验 → `store.setBalanceBaseline(initialAmount:establishedAt: Date())` → dismiss。
- `@Query` 取 baselines + transactions 算剩余，实时刷新。DEBUG 的"调试菜单"Section 保留。

## 修改点

| 文件 | 改动 |
|---|---|
| `Aubade/Features/Analytics/BalanceCalculator.swift` | **新增**：`remaining` / `sum` 纯函数 |
| `Aubade/Store/LedgerStore.swift` | **新增** `setBalanceBaseline(initialAmount:establishedAt:)`、`currentBaseline()`（不改现有方法签名） |
| `Aubade/Features/Ledger/LedgerTabView.swift` | body 顶部插 `summaryCard`；加 `@Query baselines`；更新 `:8` 注释（汇总卡已落地） |
| `Aubade/Features/AppShell/RootTabView.swift` | `ProfilePlaceholderView` → 顶部加剩余总额区块 + 调整初始总额 sheet（保留 DEBUG Section） |
| `AubadeTests/BalanceCalculatorTests.swift` | **新增**单测（见验证点） |

## 验证点

单测（`@MainActor`，内存容器持有铁律，`Calendar(.gregorian)+UTC+firstWeekday=2`，`Decimal(string:)` 构造严格 `==`）：

1. **无基线返回 nil**：`remaining(transactions:[...], baseline:nil) == nil` → 视图"—"。
2. **剩余公式**：基线 12000 + 收入 500 − 支出 200 = 12300；`Decimal` 无浮点误差（如含 35.55/0.1+0.2 用例）。
3. **基线后边界（`>=`）**：`establishedAt` 当刻的账单**计入**；早于 `establishedAt` 1 秒的账单**不计入**；晚 1 秒计入。（PRD 验收 1 + 已确认约定 2）
4. **唯一化**：连续 `setBalanceBaseline` 两次后 `fetch(BalanceBaseline.self).count == 1`，`currentBaseline()?.initialAmount` 为最新值。（PRD 验收 2）
5. **本月合计 `sum`**：构造跨月账单，`.thisMonth` 过滤后 `sum(.expense)`/`sum(.income)` 只含本月、按方向正确。

肉眼（模拟器）：
6. 我的页录入 12000 → 剩余显示 12,000；账单页汇总卡同步显示；记一笔支出 200 → 两处剩余变 11,800（验收 1、3、9 同步）。
7. 未录初始总额时两处均显示"—"。

## 不做什么

- 不做统计 Tab（切片 02/03）。
- 不做预算相关（切片 03 消费 + N07 设置）。
- 我的页除"剩余总额 + 调整初始总额"外不做（Key/分类管理/首次引导/通知 → N07）；DEBUG 调试 Section 保留不动。
- 不改 N01 筛选/分组/编辑逻辑与 `LedgerStore` 现有方法签名。
