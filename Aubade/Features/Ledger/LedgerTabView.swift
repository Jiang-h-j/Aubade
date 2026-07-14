import SwiftUI
import SwiftData

/// 账单 Tab 真实视图（原型 §4.1，切片 03），替换切片 01 的 `LedgerTabPlaceholder`。
///
/// 组成：顶部汇总卡（剩余总额 · 本月支出 · 本月收入，N02）+ 筛选栏（分类 × 时间范围，叠加）
/// + 按自然日分组的流水列表 + 侧滑删除（二次确认）+ 点行进编辑 sheet（复用 `TransactionDetailView`）。
/// 空账本与筛选无结果分别有空态。
///
/// 数据：`@Query` 取全量按 occurredAt 倒序，内存过滤/分组（TRD §1，数据量小、增删改自动刷新）。
struct LedgerTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.occurredAt, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query private var baselines: [BalanceBaseline]

    @State private var categoryFilter: CategoryFilter = .all
    @State private var dateFilter: DateRangeFilter = .all
    @State private var editingTransaction: Transaction?
    @State private var pendingDelete: Transaction?
    // 自定义时间范围编辑态：起止草稿 + sheet 开关。
    @State private var showingCustomRange = false
    @State private var customStart = Calendar.current.startOfDay(for: Date())
    @State private var customEnd = Date()

    private var store: LedgerStore { LedgerStore(modelContext) }

    /// 过滤后按自然日分组（日期倒序、组内倒序）。now 取当前时刻用于本周/本月判定。
    private var groups: [DayGroup] {
        let filtered = LedgerFilter.apply(allTransactions,
                                          category: categoryFilter,
                                          dateRange: dateFilter,
                                          now: Date())
        return LedgerFilter.groupByDay(filtered)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryCard
                filterBar
                content
            }
            .navigationTitle("账单")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingTransaction) { tx in
                TransactionDetailView(tx: tx)
            }
            .sheet(isPresented: $showingCustomRange) {
                customRangeSheet
            }
            .confirmationDialog("删除这笔账单？", isPresented: deleteConfirmBinding,
                                titleVisibility: .visible, presenting: pendingDelete) { tx in
                Button("删除", role: .destructive) { delete(tx) }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: { _ in
                Text("删除后无法恢复")
            }
        }
    }

    // MARK: - 汇总卡（原型 §4.1 hero：剩余总额 · 本月支出 · 本月收入）

    /// 本月合计用的日历：周首日=周一（节点约束 4，与切片 02 统一；本月区间不涉周首日但保持一致）。
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    /// 当前有效基线：取 establishedAt 最新一条（防御多条并存，与 store.currentBaseline 同口径）。
    private var currentBaseline: BalanceBaseline? {
        baselines.max { $0.establishedAt < $1.establishedAt }
    }

    /// 本月账单（半开区间 [本月, 下月)，复用 LedgerFilter 口径）。
    private var monthTransactions: [Transaction] {
        LedgerFilter.apply(allTransactions, category: .all, dateRange: .thisMonth,
                           now: Date(), calendar: calendar)
    }

    private var summaryCard: some View {
        let remaining = BalanceCalculator.remaining(transactions: allTransactions,
                                                    baseline: currentBaseline)
        let month = monthTransactions
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("剩余总额")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(remaining.map { "¥" + AmountFormat.plainString($0) } ?? "—")
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
            }
            HStack(spacing: 26) {
                summaryColumn(title: "本月支出",
                              amount: BalanceCalculator.sum(month, direction: .expense),
                              direction: .expense)
                summaryColumn(title: "本月收入",
                              amount: BalanceCalculator.sum(month, direction: .income),
                              direction: .income)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func summaryColumn(title: String, amount: Decimal,
                               direction: TransactionDirection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption).foregroundStyle(.secondary)
            Text("¥" + AmountFormat.plainString(amount))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AmountFormat.color(for: direction))
        }
    }

    // MARK: - 筛选栏（原型 §4.1）

    private var filterBar: some View {
        HStack(spacing: 12) {
            categoryMenu
            dateMenu
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var categoryMenu: some View {
        Menu {
            Picker("分类", selection: $categoryFilter) {
                Text("全部分类").tag(CategoryFilter.all)
                ForEach(categories) { cat in
                    Text("\(CategoryStyle.emoji(for: cat)) \(cat.name)")
                        .tag(CategoryFilter.some(cat))
                }
            }
        } label: {
            filterChip(text: categoryLabel)
        }
    }

    private var dateMenu: some View {
        Menu {
            Button("全部时间") { dateFilter = .all }
            Button("本周") { dateFilter = .thisWeek }
            Button("本月") { dateFilter = .thisMonth }
            Button("自定义…") { showingCustomRange = true }
        } label: {
            filterChip(text: dateLabel)
        }
    }

    private func filterChip(text: String) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.subheadline)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.background.secondary, in: Capsule())
    }

    private var categoryLabel: String {
        switch categoryFilter {
        case .all:            return "全部分类"
        case .some(let c):    return c.name
        }
    }

    private var dateLabel: String {
        switch dateFilter {
        case .all:        return "全部时间"
        case .thisWeek:   return "本周"
        case .thisMonth:  return "本月"
        case .custom:     return "自定义"
        }
    }

    // MARK: - 内容（空账本 / 筛选无结果 / 分组列表）

    @ViewBuilder
    private var content: some View {
        if allTransactions.isEmpty {
            ContentUnavailableView {
                Label("还没有账单", systemImage: "list.bullet.rectangle")
            } description: {
                Text("去『记账』记第一笔吧")
            }
        } else if groups.isEmpty {
            ContentUnavailableView {
                Label("没有符合条件的账单", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("换个筛选条件试试")
            }
        } else {
            ledgerList
        }
    }

    private var ledgerList: some View {
        List {
            ForEach(groups) { group in
                Section(sectionTitle(group.day)) {
                    ForEach(group.items) { tx in
                        Button {
                            editingTransaction = tx
                        } label: {
                            LedgerRowView(tx: tx)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = tx
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// 组头日期：本地化「M月d日」。
    private func sectionTitle(_ day: Date) -> String {
        day.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - 自定义时间范围 sheet

    private var customRangeSheet: some View {
        NavigationStack {
            Form {
                // 禁未来（与手动记账口径一致）；止不早于起。
                DatePicker("开始", selection: $customStart, in: ...Date(), displayedComponents: .date)
                DatePicker("结束", selection: $customEnd, in: customStart...Date(), displayedComponents: .date)
            }
            .navigationTitle("自定义时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showingCustomRange = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dateFilter = .custom(start: customStart, end: customEnd)
                        showingCustomRange = false
                    }
                }
            }
        }
    }

    // MARK: - 删除

    /// confirmationDialog 的 Bool 绑定：pendingDelete 非 nil 即弹；关闭时清空。
    private var deleteConfirmBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })
    }

    private func delete(_ tx: Transaction) {
        EditorActions.makeDelete(store: store, tx: tx)()
        pendingDelete = nil
    }
}

#Preview {
    LedgerTabView()
        .modelContainer(PersistenceController.makeInMemoryContainer())
}
