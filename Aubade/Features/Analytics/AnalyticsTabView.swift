import SwiftUI
import SwiftData

/// 统计 Tab（N02 M5，切片 02 骨架）：粒度切换（日/周/月/年）+ 时间导航（禁未来）+ 合计卡 + 日档流水。
///
/// 替换切片 01 的 `AnalyticsPlaceholderView`。本片建**时间维度骨架 + 合计卡**：
/// - 日档：列当天流水（复用 `LedgerRowView`），点行进 `TransactionDetailView` 编辑（`.sheet(item:)`）。
/// - 周/月/年档：合计卡即时可用，趋势/占比/预算留"切片 03 填充"占位区。
/// 聚合走 `StatisticsAggregator` 无状态纯函数（`@Query` 全量 + 内存聚合，天然实时同步，节点约束 5）。
struct AnalyticsTabView: View {
    /// 跨 Tab 跳转能力：切片 03「未设预算 → 去『我的』设置」用 `selection = .profile`。
    /// 本片即接线并定死签名（照抄 `RecordTabView(selection:)` 范式），避免切片 03 回改本片签名。
    @Binding var selection: AppTab

    @Query(sort: \Transaction.occurredAt, order: .reverse) private var allTransactions: [Transaction]
    /// 预算全量（量极小，至多周+月两条）；读侧 `first { periodType == 目标 }` 取唯一值。
    /// 写侧 `LedgerStore.setBudget` 已按 periodType 唯一化，first 即该周期当前预算。
    @Query private var budgets: [Budget]

    @State private var grain: StatGrain = .month   // demo 默认月档
    @State private var offset: Int = 0             // 相对当前的周期偏移（0=当前）
    @State private var editingTransaction: Transaction?
    /// 下钻明细：点占比某行 set，驱动 `.sheet(item:)`。
    @State private var detailCategory: BreakdownRow?

    /// 固定周一为周首日（节点约束 4）；聚合/区间边界依赖它。
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    private var period: StatPeriod {
        StatPeriod.make(grain: grain, offset: offset, calendar: cal)
    }

    private var expenseTotal: Decimal {
        StatisticsAggregator.total(allTransactions, in: period, direction: .expense)
    }
    private var incomeTotal: Decimal {
        StatisticsAggregator.total(allTransactions, in: period, direction: .income)
    }

    /// 当前区间内账单（半开过滤）；`@Query` 已按 occurredAt 倒序，filter 保序，日档直接用。
    private var periodTransactions: [Transaction] {
        allTransactions.filter { $0.occurredAt >= period.start && $0.occurredAt < period.end }
    }

    /// 支出趋势序列（周/月/年档折线数据源）；桶跟随粒度。
    private var trendSeries: [(label: String, value: Decimal)] {
        StatisticsAggregator.expenseTrend(grain: grain, period: period,
                                          txs: allTransactions, calendar: cal)
    }

    /// 支出分类占比（降序、pct、空数组=本期无支出）。
    private var breakdown: [BreakdownRow] {
        StatisticsAggregator.expenseBreakdown(allTransactions, in: period)
    }

    /// 当前粒度对应的预算周期：月档→monthly、周档→weekly；日/年档无预算周期。
    private var budgetPeriodType: BudgetPeriodType? {
        switch grain {
        case .week:  return .weekly
        case .month: return .monthly
        case .day, .year: return nil
        }
    }

    /// 当前周期已设预算（唯一化后 first 即唯一值）；未设为 nil。
    private var currentBudget: Budget? {
        guard let type = budgetPeriodType else { return nil }
        return budgets.first { $0.periodType == type }
    }

    /// 下钻某类在当前区间的支出明细：与占比同源（同一半开区间 + 相同 category?.id + 仅支出）。
    private func detailTransactions(for row: BreakdownRow) -> [Transaction] {
        periodTransactions.filter { $0.direction == .expense && $0.category?.id == row.category?.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    grainPicker
                    timeNav
                    totalsCards
                    if grain == .day {
                        dayList
                    } else {
                        periodCharts
                    }
                }
                .padding()
            }
            .navigationTitle("统计")
            .sheet(item: $editingTransaction) { tx in
                TransactionDetailView(tx: tx)
            }
            .sheet(item: $detailCategory) { row in
                CategoryDetailSheet(row: row,
                                    periodTitle: period.title,
                                    transactions: detailTransactions(for: row))
            }
        }
    }

    // MARK: - 粒度切换（切换归位当前，PRD §3）

    private var grainPicker: some View {
        Picker("粒度", selection: $grain) {
            ForEach(StatGrain.allCases, id: \.self) { g in
                Text(label(for: g)).tag(g)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: grain) { offset = 0 }
    }

    private func label(for grain: StatGrain) -> String {
        switch grain {
        case .day:   return "日"
        case .week:  return "周"
        case .month: return "月"
        case .year:  return "年"
        }
    }

    // MARK: - 时间导航条（‹ 可翻过去 / › 到当前置灰，禁未来）

    private var timeNav: some View {
        HStack {
            Button { offset -= 1 } label: {
                Image(systemName: "chevron.left").font(.title3)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(period.title).font(.headline)
                if let subtitle = period.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { offset += 1 } label: {
                Image(systemName: "chevron.right").font(.title3)
            }
            .disabled(StatPeriod.isAtOrAfterNow(offset: offset))
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 合计卡（日档文案"当天支出/收入"）

    private var totalsCards: some View {
        HStack(spacing: 12) {
            totalCard(title: grain == .day ? "当天支出" : "总支出",
                      amount: expenseTotal, direction: .expense)
            totalCard(title: grain == .day ? "当天收入" : "总收入",
                      amount: incomeTotal, direction: .income)
        }
    }

    private func totalCard(title: String, amount: Decimal, direction: TransactionDirection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text("¥" + AmountFormat.plainString(amount))
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(AmountFormat.color(for: direction))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 日档流水列表（复用 N01 行样式 + 编辑 sheet）

    @ViewBuilder
    private var dayList: some View {
        if periodTransactions.isEmpty {
            emptyDay
        } else {
            VStack(spacing: 0) {
                ForEach(periodTransactions) { tx in
                    Button {
                        editingTransaction = tx
                    } label: {
                        LedgerRowView(tx: tx).padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    if tx.id != periodTransactions.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var emptyDay: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("这一天还没有账单")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - 周/月/年档：趋势折线 + 分类占比 + 预算进度（切片 03）

    @ViewBuilder
    private var periodCharts: some View {
        trendSection
        breakdownSection
        if grain == .week || grain == .month {
            budgetSection
        }
    }

    // MARK: 趋势区

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(trendTitle).font(.headline)
            if expenseTotal > 0 {
                ExpenseTrendChart(series: trendSeries)
            } else {
                chartEmpty
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var trendTitle: String {
        switch grain {
        case .week:  return "支出趋势（本周每日）"
        case .month: return "支出趋势（当月每日）"
        case .year:  return "支出趋势（当年每月）"
        case .day:   return "支出趋势"   // 日档不走本区（body 已分流），兜底文案
        }
    }

    private var chartEmpty: some View {
        Text("本期还没有支出")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }

    // MARK: 占比区

    @ViewBuilder
    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("支出分类占比").font(.headline)
            if breakdown.isEmpty {
                Text("本期还没有支出")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                CategoryBreakdownView(breakdown: breakdown) { row in
                    detailCategory = row
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: 预算区（仅周/月档）

    @ViewBuilder
    private var budgetSection: some View {
        let label = grain == .month ? "月" : "周"
        VStack(alignment: .leading, spacing: 12) {
            Text("\(label)预算").font(.headline)
            if let budget = currentBudget {
                budgetProgressView(budget: budget.amount)
            } else {
                Button {
                    selection = .profile
                } label: {
                    HStack {
                        Text("还没设置\(label)预算，去「我的」设置")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func budgetProgressView(budget: Decimal) -> some View {
        let progress = StatisticsAggregator.budgetProgress(spent: expenseTotal, budget: budget)
        let isOver = progress.state == .over
        let barColor: Color = isOver ? .red : (progress.state == .near ? .orange : .accentColor)
        let remaining = max(budget - expenseTotal, 0)
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("预算 ¥\(AmountFormat.plainString(budget))").font(.subheadline)
                Spacer()
                Text("\(progress.pct)%" + (isOver ? " 已超支！" : ""))
                    .font(.subheadline.bold())
                    .monospacedDigit()
                    .foregroundStyle(isOver ? .red : .primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(barColor)
                        .frame(width: max(0, geo.size.width * CGFloat(min(progress.pct, 100)) / 100))
                }
            }
            .frame(height: 10)
            Text("已用 ¥\(AmountFormat.plainString(expenseTotal)) · 剩余 ¥\(AmountFormat.plainString(remaining))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(PersistenceController.makeInMemoryContainer())
}
