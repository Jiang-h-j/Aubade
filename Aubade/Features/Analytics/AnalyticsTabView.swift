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

    @State private var grain: StatGrain = .month   // demo 默认月档
    @State private var offset: Int = 0             // 相对当前的周期偏移（0=当前）
    @State private var editingTransaction: Transaction?

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
                        chartsPlaceholder
                    }
                }
                .padding()
            }
            .navigationTitle("统计")
            .sheet(item: $editingTransaction) { tx in
                TransactionDetailView(tx: tx)
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

    // MARK: - 周/月/年档占位区（切片 03 替换为趋势/占比/预算）

    private var chartsPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("趋势、分类占比、预算进度将在下一版呈现")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    RootTabView()
        .modelContainer(PersistenceController.makeInMemoryContainer())
}
