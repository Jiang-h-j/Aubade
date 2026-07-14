import Foundation

/// 预算阈值状态（PRD 已确认约定 5 + 80% 接近态）。
enum BudgetState {
    case normal   // < 80%
    case near     // 80% ~ 100%（含端点）
    case over     // > 100%
}

/// 支出分类占比一行。**具名 Identifiable 结构**（非元组）：切片 03 的 `ForEach` 与
/// 下钻 `.sheet(item:)` 都要求 Identifiable。nil 分类（未分类支出）用固定哨兵 id 保证稳定。
struct BreakdownRow: Identifiable {
    let category: LedgerCategory?
    let amount: Decimal
    let pct: Int

    /// 未分类支出的固定哨兵 id：同一批未分类账单聚成一组，id 稳定不随刷新变化。
    static let uncategorizedID = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!
    var id: UUID { category?.id ?? BreakdownRow.uncategorizedID }
}

/// 统计聚合的**无状态纯函数集合**（N02 M5，节点 PRD 目标 3、4）。
///
/// 全部注入 `[Transaction]` + `StatPeriod`（+ 趋势需 `calendar` 枚举时间桶），纯 `Decimal` 运算、
/// 不触库、不缓存，边界可单测（节点约束 2、5）。区间判定一律**半开 `[start, end)`**，与
/// `LedgerFilter` 口径一致、禁用 `DateInterval.contains`（节点约束 3）。本片实现并单测**全部**聚合，
/// 切片 03 只消费渲染、不再写聚合。
enum StatisticsAggregator {

    // MARK: - 区间合计

    /// 区间内某方向合计：先按 period 半开过滤，再复用 `BalanceCalculator.sum` 按方向求和。
    static func total(_ txs: [Transaction], in p: StatPeriod, direction: TransactionDirection) -> Decimal {
        BalanceCalculator.sum(inRange(txs, p), direction: direction)
    }

    // MARK: - 分类占比

    /// 支出分类占比：区间内支出按分类分组求和，降序，`pct = round(amount/total*100)`。
    /// 总支出为 0 时返回空数组（占比区空态）。nil 分类（未分类）单独成组、走哨兵 id。
    ///
    /// 说明：不需要 `calendar` —— 仅按 period 的具体日期半开过滤、按 `category?.id` 分组，
    /// 与 `total` 同口径（与趋势不同，趋势才需 calendar 枚举时间桶）。
    static func expenseBreakdown(_ txs: [Transaction], in p: StatPeriod) -> [BreakdownRow] {
        let expenses = inRange(txs, p).filter { $0.direction == .expense }
        let total = expenses.reduce(Decimal(0)) { $0 + $1.amount }
        guard total > 0 else { return [] }

        // 按 category?.id 分组：所有 nil 分类聚成同一组（键为 nil）。
        let groups = Dictionary(grouping: expenses) { $0.category?.id }
        let rows = groups.map { _, txs -> BreakdownRow in
            let amount = txs.reduce(Decimal(0)) { $0 + $1.amount }
            return BreakdownRow(category: txs.first?.category,
                                amount: amount,
                                pct: roundedPercent(amount, of: total))
        }
        // 金额降序；等额时按 id 串定序，保证输出稳定（Dictionary 遍历序不确定）。
        return rows.sorted {
            $0.amount != $1.amount ? $0.amount > $1.amount : $0.id.uuidString < $1.id.uuidString
        }
    }

    // MARK: - 支出趋势序列

    /// 支出趋势：时间桶跟随粒度（year=当年12月、month=当月每日、week/day=所在周7天），
    /// 每桶 (label, 支出合计)。仅统计支出；某桶无支出为 0。用于切片 03 折线图。
    /// - day 档也展示"所在周 7 天"（对齐 demo `trendSeries`），故 day 用 period.start 所在周。
    static func expenseTrend(grain: StatGrain, period p: StatPeriod,
                             txs: [Transaction], calendar: Calendar) -> [(label: String, value: Decimal)] {
        switch grain {
        case .year:
            // 当年 12 个自然月，逐月半开求和。
            var result: [(label: String, value: Decimal)] = []
            var monthStart = p.start
            for _ in 0..<12 {
                guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { break }
                let m = calendar.component(.month, from: monthStart)
                result.append(("\(m)月", expenseSum(txs, from: monthStart, to: monthEnd)))
                monthStart = monthEnd
            }
            return result

        case .month:
            // 当月每一天，逐日半开求和；桶数 = 当月天数。
            var result: [(label: String, value: Decimal)] = []
            var dayStart = p.start
            while dayStart < p.end {
                guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
                let c = calendar.dateComponents([.month, .day], from: dayStart)
                result.append(("\(c.month ?? 0)/\(c.day ?? 0)", expenseSum(txs, from: dayStart, to: dayEnd)))
                dayStart = dayEnd
            }
            return result

        case .week, .day:
            // 所在周 7 天：week 档 period 本身即该周；day 档取 period.start 所在周。
            let weekStart: Date = (grain == .week)
                ? p.start
                : (calendar.dateInterval(of: .weekOfYear, for: p.start)?.start ?? p.start)
            var result: [(label: String, value: Decimal)] = []
            var dayStart = weekStart
            for _ in 0..<7 {
                guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
                let c = calendar.dateComponents([.month, .day], from: dayStart)
                result.append(("\(c.month ?? 0)/\(c.day ?? 0)", expenseSum(txs, from: dayStart, to: dayEnd)))
                dayStart = dayEnd
            }
            return result
        }
    }

    // MARK: - 预算进度

    /// 预算进度：`pct = round(spent/budget*100)`；over(>100%) / near(80~100%) / normal(<80%)。
    /// budget <= 0 兜底为 (0, normal)，防除零（未设预算由调用方判 `@Query` nil，此处仅防脏数据）。
    static func budgetProgress(spent: Decimal, budget: Decimal) -> (pct: Int, state: BudgetState) {
        guard budget > 0 else { return (0, .normal) }
        let pct = roundedPercent(spent, of: budget)
        let state: BudgetState
        if pct > 100 { state = .over }
        else if pct >= 80 { state = .near }
        else { state = .normal }
        return (pct, state)
    }

    // MARK: - 私有 helper

    /// 区间半开过滤 `[p.start, p.end)`（禁用 DateInterval.contains，节点约束 3）。
    private static func inRange(_ txs: [Transaction], _ p: StatPeriod) -> [Transaction] {
        txs.filter { $0.occurredAt >= p.start && $0.occurredAt < p.end }
    }

    /// 指定半开区间内的支出合计。
    private static func expenseSum(_ txs: [Transaction], from: Date, to: Date) -> Decimal {
        txs.filter { $0.direction == .expense && $0.occurredAt >= from && $0.occurredAt < to }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// `round(part/whole*100)` 纯 `Decimal` 四舍五入取整（.plain 对非负值等价 Math.round）。
    private static func roundedPercent(_ part: Decimal, of whole: Decimal) -> Int {
        guard whole > 0 else { return 0 }
        var ratio = part / whole * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &ratio, 0, .plain)
        return (rounded as NSDecimalNumber).intValue
    }
}
