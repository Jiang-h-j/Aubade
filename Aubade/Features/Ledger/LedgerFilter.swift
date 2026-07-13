import Foundation

/// 账单筛选的**值模型 + 纯函数过滤/分组**（切片 03）。
///
/// 本片决策：`@Query` 取全量 + 内存过滤/分组（TRD §1）。理由——N01 个人记账数据量小，
/// 全量取 + 内存 filter 简单可靠，增删改后 `@Query` 自动刷新；动态 `FetchDescriptor` 对可选
/// 关系 `category` 与区间 predicate 在 iOS 17 易踩坑。过滤/分组抽为无状态纯函数，边界可单测。

/// 分类筛选：全部 / 指定某分类。
///
/// Equatable/Hashable **基于 `LedgerCategory.id`** 而非 `@Model` 引用语义：`@Query` 刷新后
/// SwiftData 可能返回同一分类的不同实例，若按引用比较 Picker selection 会丢失；按 id 稳定。
enum CategoryFilter: Hashable {
    case all
    case some(LedgerCategory)

    /// 账单是否命中本分类条件：`all` 全过；`some(c)` 留 `tx.category?.id == c.id`。
    func matches(_ tx: Transaction) -> Bool {
        switch self {
        case .all:            return true
        case .some(let c):    return tx.category?.id == c.id
        }
    }

    static func == (lhs: CategoryFilter, rhs: CategoryFilter) -> Bool {
        switch (lhs, rhs) {
        case (.all, .all):                        return true
        case (.some(let l), .some(let r)):        return l.id == r.id
        default:                                  return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .all:            hasher.combine(0)
        case .some(let c):    hasher.combine(1); hasher.combine(c.id)
        }
    }
}

/// 时间范围筛选：全部 / 本周 / 本月 / 自定义起止。
enum DateRangeFilter: Hashable {
    case all
    case thisWeek
    case thisMonth
    case custom(start: Date, end: Date)

    /// 账单发生时间是否落在本区间。**统一半开区间 `[start, end)`**（防 off-by-one）：
    /// `Calendar.dateInterval` 的 `.end` 是下一周期起点（排他），而 `DateInterval.contains` 含右端点，
    /// 会把下周期第一刻误纳入——故此处不用 `DateInterval.contains`，改手写 `start <= date < end`。
    /// - now: 计算本周/本月的参考"当前时刻"。显式注入（默认当前时间）以便单测钉死边界。
    /// - calendar: 注入以便单测固定 firstWeekday/timeZone。
    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .thisWeek:
            return halfOpenContains(date, interval: calendar.dateInterval(of: .weekOfYear, for: now))
        case .thisMonth:
            return halfOpenContains(date, interval: calendar.dateInterval(of: .month, for: now))
        case .custom(let start, let end):
            // 自定义含用户所选止日整天：下边界取起日 0 点，上边界取止日**次日** 0 点，半开排他。
            let lower = calendar.startOfDay(for: start)
            let endDayStart = calendar.startOfDay(for: end)
            let upper = calendar.date(byAdding: .day, value: 1, to: endDayStart) ?? endDayStart
            return date >= lower && date < upper
        }
    }

    /// 半开区间判定。`interval` 为 nil（Calendar API 理论失败）时兜底放行，宁可多显示不可漏账单。
    private func halfOpenContains(_ date: Date, interval: DateInterval?) -> Bool {
        guard let interval else { return true }
        return date >= interval.start && date < interval.end
    }
}

/// 过滤 + 分组纯函数集合。无状态、注入 now/calendar，边界可单测。
enum LedgerFilter {

    /// 应用分类 + 时间双条件（**叠加**，验收 6），返回过滤后账单。
    static func apply(_ transactions: [Transaction],
                      category: CategoryFilter,
                      dateRange: DateRangeFilter,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> [Transaction] {
        transactions.filter { tx in
            category.matches(tx) && dateRange.contains(tx.occurredAt, now: now, calendar: calendar)
        }
    }

    /// 按 `occurredAt` 所属**自然日**分组：日期键倒序，组内按 `occurredAt` 倒序（验收 2）。
    static func groupByDay(_ transactions: [Transaction],
                           calendar: Calendar = .current) -> [DayGroup] {
        Dictionary(grouping: transactions) { calendar.startOfDay(for: $0.occurredAt) }
            .map { DayGroup(day: $0.key, items: $0.value.sorted { $0.occurredAt > $1.occurredAt }) }
            .sorted { $0.day > $1.day }
    }
}

/// 列表分组：某自然日 + 当日账单（已按 occurredAt 倒序）。`day` 作 `ForEach` 稳定 id。
struct DayGroup: Identifiable {
    let day: Date
    let items: [Transaction]
    var id: Date { day }
}
