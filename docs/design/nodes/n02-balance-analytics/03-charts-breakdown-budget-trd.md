# TRD 03 - 周月年档可视化：趋势折线 + 分类占比 + 下钻 + 预算进度

> 节点 PRD：`docs/prd/nodes/n02-balance-analytics-prd.md`。上游：切片 02（聚合纯函数 + 统计骨架）。
> UI 事实：demo `app.js:511-561`（趋势/占比/预算渲染）、`app.js:627-660`（lineChart）。行号为写作时快照。

## 给用户看的摘要

这一片把「统计」Tab 的周/月/年档**填满**：

- **支出趋势折线图**：看这段时间每天（或每月）花了多少，带峰值/均值标注。
- **支出分类占比**：一排彩色条形，哪类花得最多一目了然；点某一类，弹出这段时间里这一类的每一笔明细，点某笔还能进去改。
- **预算进度条**（仅周/月档）：设了预算就显示用了百分之多少，接近 80% 提醒、超 100% 标红说"已超支！"；没设就提示去「我的」设置。

这些都建立在上一片已经算好的数据上，这一片只负责"把数画出来 + 点击交互"。

## 本 TRD 负责什么

统计周/月/年档的**可视化与交互**（PRD 需求范围 §5、§6，验收 4 占比 / 5 趋势 / 6 下钻 / 7 预算）：

1. **支出趋势折线图**（周/月/年档）：消费 `StatisticsAggregator.expenseTrend`，用 **Swift Charts** 渲染折线 + 面积渐变 + 峰值/均值标注；本期无支出显示"本期还没有支出"占位。
2. **支出分类占比条形图**：消费 `expenseBreakdown`，条形宽度=占比、色=`CategoryStyle`；空态占位。
3. **分类占比下钻明细**：点某类 → `.sheet` 弹该类在当前区间的明细（复用 `LedgerRowView` + `TransactionDetailView` 编辑）。
4. **预算进度**（仅周/月档）：消费 `budgetProgress`，进度条 + 百分比 + 阈值态（near/over）；未设预算引导；年档不显示。
5. **DEBUG 写预算/初始总额入口**：`DebugMenuView` 加写周/月 `Budget` 的按钮，支撑预算 UI 的肉眼验收（设置界面在 N07）。

## 当前代码事实与上下游

- **聚合已就绪**（切片 02）：`StatisticsAggregator.expenseTrend/expenseBreakdown(→[BreakdownRow])/budgetProgress`、`StatPeriod`、`BudgetState{normal,near,over}`、`BreakdownRow`（Identifiable，供 `ForEach`/`.sheet(item:)`）。本片**只消费不重写聚合**。
- **骨架已就绪**（切片 02）：`AnalyticsTabView` 已有粒度/导航/合计卡/日档 + `@Binding var selection: AppTab`（切片 02 已接线，本片直接消费 `selection = .profile` 跳我的 Tab，不回改 02 签名），周月年档留了"切片 03 填充"占位区——本片替换该占位区。
- **行样式/编辑复用**：`LedgerRowView`（`Aubade/Features/Ledger/LedgerRowView.swift:8`，左 emoji 彩标 + 中摘要 + 右金额）；`TransactionDetailView`（`:11`，`.sheet(item:)` 编辑+删除二次确认）。
- **配色**：`CategoryStyle.color(name:direction:)`（`:42`）——占比条形与明细图标用**支出方向**传入（占比只统计支出）。
- **Charts 未引入**：需 `import Charts`（iOS 16+ 系统框架，无需第三方依赖）。
- **Budget 模型**：`Budget(periodType:amount:)`（`Budget.swift:12`）**无时间戳字段**（只有 id/periodType/amount，`:5-9`）；`LedgerStore.createBudget`（`:73`）已存在但不做唯一化。**本片新增 `LedgerStore.setBudget(periodType:amount:)`**（清同周期再插，写侧唯一化），读侧 `@Query budgets` 后 `first{$0.periodType==...}`（唯一化后至多一条，first 即唯一值）——**不依赖不可靠的 `.last`**（PRD 已确认约定 3 修订版）。
- **demo 对照**：趋势 `app.js:518-524`（标题随粒度、空态占位、峰值均值行）；占比 `app.js:527-539`（bar-row 可点下钻 `openCatDetail`）；预算 `app.js:542-561`（pct、over 标红"已超支！"、进度条 `min(pct,100)`、未设引导）。

## 设计方案

### 1. 趋势折线图 — 技术选型：**Swift Charts**（非自绘 SVG）
**决策**：用 iOS 16+ 原生 `import Charts`，`LineMark` + `AreaMark`（面积渐变）+ 峰值 `PointMark`/`.annotation`。
**理由**：
- 项目 iOS 17+，Swift Charts 是系统框架、**零第三方依赖**，原生支持折线/面积渐变/标注/坐标轴，比手写 SVG `Path` 可靠且少代码。
- demo 用 SVG 仅因它是网页原型；Swift 侧无须复刻 SVG，只需复刻**视觉效果**（折线 + 面积渐变 + 峰值/均值），Charts 直接覆盖。
- 聚合已产出 `[(label, Decimal)]`，Charts 消费无缝（`Decimal` 转 `Double` 仅用于绘图坐标，不参与金额计算，精度无关）。

```
import Charts
struct ExpenseTrendChart: View {
    let series: [(label: String, value: Decimal)]   // 来自 expenseTrend
    var body: some View {
        Chart(Array(series.enumerated()), id: \.offset) { i, pt in
            LineMark(x: .value("", i.offset), y: .value("支出", (pt.value as NSDecimalNumber).doubleValue))
            AreaMark(...)  // 渐变填充
        }
        // 峰值/均值标注：算 max/avg（Decimal），叠加 .annotation 或副标题行（对齐 demo 峰值¥X·均值¥Y）
    }
}
```
- 横轴标签跟随粒度（week/day=周内日期、month=当月每日抽稀、year=1~12月），由 series 的 label 提供。
- 本期无支出（series 全 0 或总支出 0）→ 显示"本期还没有支出"占位（不渲染 Chart）。

### 2. 分类占比条形（自绘，对齐 demo bar-row）
条形用 `GeometryReader`/`Capsule` 宽度=pct%，无需 Charts：

```
ForEach(breakdown) { row in
    Button { selectedCat = row } label: {
        VStack {
            HStack { Text("\(emoji) \(name)"); Spacer(); Text("\(pct)% · ¥\(amount) ›") }
            // 轨道 + 填充：填充宽度 = pct%，色 = CategoryStyle.color(name:direction:.expense)
        }
    }
}
```
- 数据源 `expenseBreakdown`；空态"本期还没有支出"占位（PRD 已确认约定/原型 §5 占比区空态）。

### 3. 下钻明细 sheet
- `@State private var detailCategory: BreakdownRow?`；点条形 set → `.sheet(item:)`。
- sheet 内容：标题 = "分类名 · 区间标题"（用 `StatPeriod.title`）；共 N 笔 + 合计（该类区间内支出）；`List{ ForEach 明细 LedgerRowView }`，点某行 → 再进 `TransactionDetailView` 编辑（改删后 `@Query` 刷新，占比同步——验收 6、9）。
- 明细数据 = 当前区间账单中 `category?.id == 该类` 的支出，与占比数字同源（保证合计一致）。

### 4. 预算进度（仅周/月档）
- **读预算**：新增 `@Query private var budgets: [Budget]`（全量，量极小），在内存里 `budgets.first { $0.periodType == 目标 }`。**为何 first 即可**：`Budget` 无时间戳字段（`Budget.swift:5-9`），无法按时间"取最新"；改由**写侧唯一化**保证每周期至多一条（见 §5 与 `LedgerStore.setBudget`），读侧取唯一 `first`。用 `@Query` 而非命令式 `store.fetch`，与全节点"@Query 全量 + 内存聚合"口径统一，且预算变更能响应式刷新进度条。
- 无预算 → "还没设置{周/月}预算，去『我的』设置 ›"，**点击 `selection = .profile` 切到我的 Tab**（消费切片 02 已接线的 `@Binding selection`，本节点不做设置界面）。
- 有 → `budgetProgress(spent: 区间支出, budget: 额)` 得 (pct, state)：进度条填充 `min(pct,100)%`；`state==.over` 标红 + "已超支！"；`state==.near` 接近提示样式（80~100%）；显示"已用 ¥X · 剩余 ¥max(budget-spent,0)"。
- `grain==.year` 不渲染预算区（原型 §4.6 / demo `app.js:542`）。

### 5. DEBUG 写预算/初始总额入口（`DebugMenuView`）
- 新增 Section "N02 调试"：按钮"写月预算 1500"、"写周预算 800"（调 **`store.setBudget(periodType:amount:)`**——清同周期旧记录再插，保证唯一）、"清空预算"；"写初始总额 12000"（复用切片 01 `setBalanceBaseline`）。
- 目的：预算设置界面在 N07，本节点验收预算 UI（进度/near/over）需要能写库，DEBUG 入口提供可观察路径。写侧唯一化使多次点击不会累积多条，`@Query budgets.first` 稳定取到。

## 修改点

| 文件 | 改动 |
|---|---|
| `Aubade/Store/LedgerStore.swift` | **新增** `setBudget(periodType:amount:)`：清同 `periodType` 旧记录再插（写侧唯一化，对称 `setBalanceBaseline`） |
| `Aubade/Features/Analytics/AnalyticsTabView.swift` | 周/月/年档占位区 → 趋势图 + 占比条形 + 预算区；加 `@Query budgets` 与下钻 sheet；消费 `selection` 跳我的 Tab |
| `Aubade/Features/Analytics/ExpenseTrendChart.swift` | **新增**：Swift Charts 折线+面积+峰值/均值 |
| `Aubade/Features/Analytics/CategoryBreakdownView.swift` | **新增**：占比条形 + 下钻 sheet（或内联进 AnalyticsTabView，按体量定） |
| `Aubade/Debug/DebugMenuView.swift` | **新增** N02 调试 Section（`setBudget` 写周/月预算、`setBalanceBaseline` 写初始总额、清空预算） |
| `AubadeTests/`（可选） | 占比明细合计=占比数值的一致性由切片 02 聚合单测覆盖；`setBudget` 唯一化可加一条单测（连写两次周预算后 count==1）；本片图表以肉眼验收为主 |

## 验证点

肉眼（模拟器，先用 DEBUG 入口造数据）：
1. **趋势（验收 5）**：月档趋势横轴=当月每日、周档=本周每日、年档=当年每月，仅支出；本期无支出显示"本期还没有支出"占位而非空图；峰值/均值显示。
2. **占比（验收 4）**：条形按金额降序、色与账单标签一致、pct 之和≈100%；本期无支出占比区空态。
3. **下钻（验收 6）**：点某类弹明细（标题=类+区间、共N笔+合计），合计与占比数字一致；点明细某笔进 `TransactionDetailView` 改/删，返回后占比/趋势同步刷新。
4. **预算（验收 7）**：DEBUG 写月预算 1500 → 月档显示进度；当月支出≥80% 显示接近态、>100%（如 2055/1500=137%）标红"已超支！"；未设预算显示"去设置"引导；年档无预算区。
5. **同步（验收 9）**：下钻明细里改/删账单后，合计卡、趋势、占比、预算全部自动刷新。
6. **不越界（验收 10）**：预算只显示进度与引导、无设置输入 UI；统计不建缓存表（每次 `@Query` 全量 + 内存聚合）。

单测（补充）：
7. Swift Charts 渲染不单测（UI）；趋势/占比/预算的**数值**正确性已由切片 02 `StatisticsAggregatorTests` 覆盖，本片不重复。

## 不做什么

- 不做预算/初始总额的**正式设置界面**（N07）——仅 DEBUG 入口写库验证。
- 不做日档趋势图（原型 §4.6 日档只列流水，切片 02 已实现）。
- 不引第三方图表库（用系统 Swift Charts）。
- 不建统计缓存表（技术基线 §7.5 按需实时聚合）。
- 不改切片 02 的聚合纯函数签名与 N01 账单/编辑逻辑。
