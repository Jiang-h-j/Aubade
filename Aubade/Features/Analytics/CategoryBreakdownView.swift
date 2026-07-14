import SwiftUI

/// 支出分类占比条形（N02 切片 03，验收 4）：消费 `StatisticsAggregator.expenseBreakdown` 的 `[BreakdownRow]`，
/// 每行条形宽度 = pct%、色 = `CategoryStyle.color(name:direction:.expense)`（占比只统计支出，故方向恒为 .expense）。
/// 点某行 → 回调父视图弹下钻明细。空态由父视图判 `breakdown.isEmpty` 决定，此处只渲染非空列表。
struct CategoryBreakdownView: View {
    let breakdown: [BreakdownRow]
    /// 点某类回调：父视图据此 set `.sheet(item:)` 的 BreakdownRow。
    let onSelect: (BreakdownRow) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(breakdown) { row in
                Button {
                    onSelect(row)
                } label: {
                    barRow(row)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func barRow(_ row: BreakdownRow) -> some View {
        let name = row.category?.name ?? "未分类"
        let emoji = CategoryStyle.emoji(name: row.category?.name, direction: .expense)
        let color = CategoryStyle.color(name: row.category?.name, direction: .expense)
        return VStack(spacing: 6) {
            HStack {
                Text("\(emoji) \(name)").font(.subheadline)
                Spacer()
                Text("\(row.pct)% · ¥\(AmountFormat.plainString(row.amount)) ›")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color)
                        .frame(width: max(0, geo.size.width * CGFloat(row.pct) / 100))
                }
            }
            .frame(height: 8)
        }
    }
}

/// 分类占比下钻明细（N02 切片 03，验收 6）：某类在当前区间的每一笔支出。
/// 标题 = "分类名 · 区间标题"；顶部 "共 N 笔 · 合计 ¥X"（合计由实时 transactions 求和，与列表同源）；
/// List 复用 `LedgerRowView`，点某行进 `TransactionDetailView` 编辑（改删后 @Query 刷新，占比/趋势/本合计同步）。
struct CategoryDetailSheet: View {
    /// 被点的占比行（提供分类身份与标题；合计不取其 amount 快照，见 total）。
    let row: BreakdownRow
    /// 当前区间标题（来自 `StatPeriod.title`），拼进导航标题。
    let periodTitle: String
    /// 该类在当前区间的明细账单（父视图按同一半开区间 + category?.id 过滤后传入，@Query 刷新时实时更新）。
    let transactions: [Transaction]

    @State private var editingTransaction: Transaction?

    private var categoryName: String { row.category?.name ?? "未分类" }

    /// 合计由实时 transactions 求和（非 row.amount 快照）：sheet 内改/删后与"共 N 笔"、列表同步刷新。
    private var total: Decimal {
        transactions.reduce(Decimal(0)) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("共 \(transactions.count) 笔")
                        Spacer()
                        Text("合计 ¥\(AmountFormat.plainString(total))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
                Section {
                    ForEach(transactions) { tx in
                        Button {
                            editingTransaction = tx
                        } label: {
                            LedgerRowView(tx: tx)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("\(categoryName) · \(periodTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingTransaction) { tx in
                TransactionDetailView(tx: tx)
            }
        }
    }
}
