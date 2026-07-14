# TRD 02 - 统计聚合纯函数 + 统计 Tab 骨架（粒度/导航/日档）

> 节点 PRD：`docs/prd/nodes/n02-balance-analytics-prd.md`。上游：N01（本片不调用切片 01，仅同 `Analytics/` 目录与 Tab 体系）。
> UI/口径事实：demo `prototype/app/app.js:470-569`（renderStats）、`data.js:106-215`（periodRange/trendSeries/rangeCatBreakdown）。行号为写作时快照。

## 给用户看的摘要

这一片把「统计」Tab 的**时间骨架**立起来：

- 顶部一排「日 / 周 / 月 / 年」切换，下面一条「‹ 时间 ›」导航条，可以往过去翻，**翻不到未来**（到当前区间时 › 变灰）。
- 切到**日**档：选某天，看当天每一笔流水 + 当天收支合计，点某笔能进去改（复用账单编辑）。
- 切换粒度时，时间自动跳回"当前"（今天/本周/本月/今年）。

周/月/年档的趋势图、分类占比、预算进度是**下一片**填的——这一片先把骨架和背后的**聚合算法**做扎实（能算任意区间的收支合计、趋势序列、分类占比、预算进度），并用单测钉死边界。

## 本 TRD 负责什么

M5 统计的**底座 + 骨架**（PRD 目标 3、4，需求范围 §3、§4、§7）：

1. **区间口径纯函数** `StatPeriod`：给定粒度（日/周/月/年）+ 相对偏移，算出半开区间 `[start, end)` + 标题/副标题 + 是否已到"当前区间"（禁未来）。
2. **聚合纯函数** `StatisticsAggregator`（无状态、可单测）：区间收支合计、支出趋势序列（横轴跟随粒度）、支出分类占比、预算进度与阈值状态。**本片实现并单测全部聚合**（切片 03 只消费渲染，不再写聚合）。
3. **统计 Tab 骨架**：替换 `AnalyticsPlaceholderView`，实现粒度切换 + 时间导航（禁未来）+ 粒度切换归位 + **日档流水列表**（复用 N01 行样式与编辑 sheet）。周/月/年档本片先留"下一片填充"占位区，但合计卡（总支出/总收入）本片即接入。

## 当前代码事实与上下游

- **区间口径基准**：`LedgerFilter` 已有 `.weekOfYear`/`.month` 的半开区间（`LedgerFilter.swift:58-60,71-74`）与"不用 DateInterval.contains"约定（`:48-50`）。本片扩展到日/周/月/年四档，同口径。
- **禁未来先例**：`TransactionEditor.swift:144`、`LedgerTabView.swift:181` 用 `in: ...Date()` 限制 DatePicker 不选未来；统计导航禁未来沿用"不超过当前区间"同语义。
- **日档流水复用**：N01 的行渲染在 `LedgerRowView`（`Aubade/Features/Ledger/LedgerRowView.swift`），编辑 sheet 复用 `TransactionDetailView`（`Aubade/Features/Ledger/TransactionDetailView.swift:11`，`.sheet(item:)` 呈现）。
- **配色/格式化**：`CategoryStyle.color(name:direction:)`（`:42`）/`emoji`（`:33`）；`AmountFormat.plainString`（`:31`）。
- **Charts**：项目**未引入** Swift Charts（`grep import Charts` 无结果）。趋势图渲染在切片 03 决策（见切片 03 TRD）；本片聚合只产出 `[（label, Decimal）]` 序列，与渲染方式无关。
- **demo 口径对照**：
  - `periodRange(grain, offset)`（`data.js:122-155`）：day=某天、week=周一起7天、month=自然月、year=自然年；`isFuture`（`:164`）= offset>0 禁用。
  - `trendSeries`（`data.js:185-203`）：year=当年12月、month=当月每日、week/day=所在周7天（仅支出）。
  - `rangeCatBreakdown`（`data.js:173-179`）：按分类求和、降序、`pct=round(val/total*100)`。
  - `rangeSum`（`data.js:171`）：区间内按方向求和。

## 设计方案

### 1. `StatPeriod`（新增，`Aubade/Features/Analytics/StatPeriod.swift`）
粒度枚举 + 区间计算纯函数，注入 `now`/`calendar`（calendar 必须 `firstWeekday=2`）：

```
enum StatGrain: String, CaseIterable { case day, week, month, year }

struct StatPeriod {
    let start: Date        // 半开区间下界（含）
    let end: Date          // 半开区间上界（不含）
    let title: String      // 导航条主标题："7月10日" / "2026年7月" / "2026年"
    let subtitle: String?   // "周五" / "本周" / "本月" / "今年" 等

    /// 给定粒度 + 偏移（0=当前，-1=上一个），算区间。calendar.firstWeekday 决定周界（需=2）。
    static func make(grain: StatGrain, offset: Int, now: Date = Date(), calendar: Calendar = .current) -> StatPeriod

    /// 该 (grain, offset) 是否已是"当前区间或更未来"——即导航 › 是否应禁用（offset>=0）。
    static func isAtOrAfterNow(offset: Int) -> Bool { offset >= 0 }
}
```

- `make` 用 `calendar.dateInterval(of: component, for: shiftedDate)` 取半开 `[start,end)`：
  - day → `.day`，shiftedDate = `now + offset 天`（`calendar.date(byAdding:.day,value:offset)`）。
  - week → `.weekOfYear`，shiftedDate = `now + offset 周`。
  - month → `.month`，shiftedDate = `now + offset 月`。
  - year → `.year`，shiftedDate = `now + offset 年`。
- **半开区间统一**：`start = interval.start`，`end = interval.end`（`dateInterval` 的 end 即下一周期起点，排他），与 `LedgerFilter` 口径一致。
- 标题/副标题用 `DateFormatter`/`Calendar` 组件拼装（day 带"周X"，week 带起止或"本周"，month/year 带"本月/今年"当 offset==0）。

### 2. `StatisticsAggregator`（新增，`Aubade/Features/Analytics/StatisticsAggregator.swift`）
无状态聚合，全部注入 `[Transaction]` + period + `now`/`calendar`，纯 `Decimal`：

```
enum StatisticsAggregator {
    /// 区间内某方向合计（复用 BalanceCalculator.sum 思路，但先按 period 半开过滤）。
    static func total(_ txs: [Transaction], in p: StatPeriod, direction: TransactionDirection) -> Decimal

    /// 支出分类占比：降序，pct=四舍五入百分比。总支出为 0 时返回空数组（占比区空态）。
    static func expenseBreakdown(_ txs: [Transaction], in p: StatPeriod, calendar: Calendar)
        -> [BreakdownRow]

    /// 支出趋势序列：桶跟随粒度（week/day=所在周7天、month=当月每日、year=当年12月）。
    /// 每个桶 (label, 支出合计)。用于折线图；空区间由调用方判占位。
    static func expenseTrend(grain: StatGrain, period: StatPeriod, txs: [Transaction], calendar: Calendar)
        -> [(label: String, value: Decimal)]

    /// 预算进度：给定区间支出与预算额，算百分比 + 阈值状态。
    static func budgetProgress(spent: Decimal, budget: Decimal) -> (pct: Int, state: BudgetState)
}

enum BudgetState { case normal, near, over }   // near: >=80% 且 <=100%; over: >100%

/// 分类占比一行。具名 **Identifiable** 结构（非元组）：切片 03 的 `ForEach` 与
/// 下钻 `.sheet(item:)` 都要求 Identifiable。nil 分类（未分类支出）用固定哨兵 id 保证稳定。
struct BreakdownRow: Identifiable {
    let category: LedgerCategory?
    let amount: Decimal
    let pct: Int
    var id: UUID { category?.id ?? BreakdownRow.uncategorizedID }
    static let uncategorizedID = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!
}
```

- **区间过滤**：`txs.filter { $0.occurredAt >= p.start && $0.occurredAt < p.end }`（半开，禁用 DateInterval.contains）。
- **趋势分桶**：按 demo `trendSeries` 口径——用 `calendar` 枚举桶边界（每日/每月），逐桶半开求和支出。day 与 week 都展示"所在周 7 天"（对齐 demo `:198-202`）。
- **占比**：按 `category?.id` 分组（nil 分类单独成组、用哨兵 id，标签走 `CategoryStyle` 方向兜底），`pct = round(amount/total*100)`，降序，返回 `[BreakdownRow]`（Identifiable，供切片 03 `ForEach`/`.sheet(item:)` 直接消费）。
- **预算阈值**：`pct = round(spent/budget*100)`；`over = pct>100`、`near = 80<=pct<=100`、否则 normal（PRD 已确认约定 5，补 80% 接近态）。`Decimal` 比例转百分比用 `NSDecimalNumber` 或 `(spent/budget * 100)` 后四舍五入。

### 3. 统计 Tab 骨架（新增 `Aubade/Features/Analytics/AnalyticsTabView.swift`，替换占位）
- 状态：`@State grain: StatGrain = .month`（demo 默认月）、`@State offset: Int = 0`。
- **跨 Tab 绑定（本片即接线，供切片 03「去设置」跳我的 Tab 用）**：`@Binding var selection: AppTab`——照抄 `RecordTabView(selection:)` 范式（`RecordTabView.swift:9-10`、`RootTabView.swift:19`）。本片 `AnalyticsTabView` 自身不用它切 Tab，但**在切片 02 就把签名与接线定死**，避免切片 03 回改本片签名（评审要求）。
- `@Query(sort:\Transaction.occurredAt, order:.reverse) allTransactions`（全量，实时同步）。
- 固定 `calendar`：`var cal: Calendar { var c = Calendar(identifier:.gregorian); c.firstWeekday = 2; return c }`（周一起）。
- body：
  - **粒度切换段**（Picker/分段按钮，`StatGrain.allCases`）：切换时 `offset = 0`（归位当前，PRD §3）。
  - **时间导航条**：`‹` → `offset -= 1`；标题 = `period.title`（+subtitle）；`›` → `offset += 1`，**当 `offset >= 0` 时禁用置灰**（`StatPeriod.isAtOrAfterNow`，禁未来）。
  - **合计卡**：总支出/总收入（日档文案"当天支出/收入"）= `StatisticsAggregator.total(...)`，`AmountFormat.plainString`。
  - **日档**（`grain == .day`）：列当天流水（`LedgerRowView`），点行 → `.sheet(item:)` `TransactionDetailView`；空态"这一天还没有账单"。
  - **周/月/年档**：本片放一个"趋势 / 占比 / 预算将在切片 03 呈现"的轻量占位区（合计卡已显示）；切片 03 替换为真实图表。
- `RootTabView`（`:27`）`AnalyticsPlaceholderView()` → `AnalyticsTabView(selection: $selectedTab)`（照抄 `:19` 的 `RecordTabView(selection: $selectedTab)`）；删除 `AnalyticsPlaceholderView` 占位结构体。

## 修改点

| 文件 | 改动 |
|---|---|
| `Aubade/Features/Analytics/StatPeriod.swift` | **新增**：`StatGrain` + `StatPeriod.make` 区间口径 |
| `Aubade/Features/Analytics/StatisticsAggregator.swift` | **新增**：total/expenseBreakdown/expenseTrend/budgetProgress + `BudgetState` |
| `Aubade/Features/Analytics/AnalyticsTabView.swift` | **新增**：统计 Tab 骨架（`@Binding selection` + 粒度/导航/日档/合计卡 + 周月年占位区） |
| `Aubade/Features/AppShell/RootTabView.swift` | `AnalyticsPlaceholderView()` → `AnalyticsTabView(selection: $selectedTab)`；移除占位结构体 |
| `AubadeTests/StatPeriodTests.swift` | **新增**：四档区间边界、禁未来单测 |
| `AubadeTests/StatisticsAggregatorTests.swift` | **新增**：合计/占比/趋势/预算阈值单测 |

## 验证点

单测（`@MainActor`，内存容器，`Calendar(.gregorian)+UTC+firstWeekday=2`，显式注入 now）：

1. **四档区间半开边界**：对每档，区间**最后一刻**的账单判入、**下一区间第一刻**判出（对齐 `LedgerFilterTests` 边界范式）。周档验证 `firstWeekday=2` 下周一为起点、周日为末日。
2. **禁未来**：`isAtOrAfterNow(offset:0)==true`（禁用）、`offset:-1==false`（可翻）。
3. **合计 total**：区间内按方向求和正确、`Decimal` 精度；区间外账单不计。
4. **占比 expenseBreakdown**：各类金额和 == 总支出、pct 降序、总支出 0 返回空数组；nil 分类单独成组。
5. **趋势 expenseTrend**：month 档桶数 = 当月天数、year 档 = 12、week/day = 7；仅统计支出；某桶无支出为 0。
6. **预算阈值 budgetProgress**：79%→normal、80%→near、100%→near、101%→over、137%→over（PRD 验收 7 阈值）。

肉眼（模拟器）：
7. 统计 Tab 切日/周/月/年，导航 ‹ 可翻过去、› 到当前置灰不能翻未来；切粒度归位当前；日档列当天流水、点进可编辑、空天显示占位；合计卡数字随区间变化。

## 不做什么

- 不做趋势折线图、条形占比图、下钻明细弹窗、预算进度条 UI（切片 03，本片只出聚合数据 + 骨架占位区）。
- 不做预算/初始总额设置界面（N07）。
- 不改 N01 账单/记账界面与 `LedgerFilter` 现有逻辑；`LedgerRowView`/`TransactionDetailView` 只复用不改。
