import Foundation

/// 统计的**时间维度粒度**：日 / 周 / 月 / 年（对齐 demo `data.js` 的 grain）。
enum StatGrain: String, CaseIterable {
    case day, week, month, year
}

/// 统计区间口径的**无状态纯函数值模型**（N02 M5，节点 PRD 目标 3、4）。
///
/// 给定粒度 + 相对偏移，算出半开区间 `[start, end)` + 导航条标题/副标题。注入 `now`/`calendar`
/// 便于单测钉死边界。区间口径与 `LedgerFilter` 一致——一律用 `Calendar.dateInterval` 取
/// 半开 `[start, end)`（`.end` 是下一周期起点、排他），**禁用 `DateInterval.contains`**（含右端点会误纳）。
/// 周界由 `calendar.firstWeekday` 决定，调用方须传 `firstWeekday = 2`（周一，节点约束 4）。
struct StatPeriod {
    let start: Date        // 半开区间下界（含）
    let end: Date          // 半开区间上界（不含）—— 下一周期起点
    let title: String      // 导航条主标题："7月10日" / "7月6日 - 7月12日" / "2026年7月" / "2026年"
    let subtitle: String?   // "周五" / "本周" / "本月" / "今年"；非当前月/年为 nil（不渲染）

    /// weekday 组件 1=周日…7=周六 → 中文；`weekday - 1` 命中下标。
    private static let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    /// 给定粒度 + 偏移（0=当前，-1=上一个），算区间与标题。
    /// - offset: 相对 `now` 的周期偏移。日=天、周=周、月=月、年=年。
    /// - calendar: 注入以固定 `firstWeekday`/`timeZone`（周界、边界钉死）。
    static func make(grain: StatGrain, offset: Int,
                     now: Date = Date(), calendar: Calendar = .current) -> StatPeriod {
        let component: Calendar.Component
        switch grain {
        case .day:   component = .day
        case .week:  component = .weekOfYear
        case .month: component = .month
        case .year:  component = .year
        }

        // 先把"当前"按粒度平移 offset 个周期，再取该周期的半开区间。
        let shifted = calendar.date(byAdding: component, value: offset, to: now) ?? now
        let interval = calendar.dateInterval(of: component, for: shifted)
        // dateInterval 理论失败时的兜底（标准粒度 + 有效 calendar 下不会触发）：退化为当天。
        let start = interval?.start ?? calendar.startOfDay(for: shifted)
        let end = interval?.end
            ?? calendar.date(byAdding: component, value: 1, to: start)
            ?? start

        let title: String
        let subtitle: String?
        switch grain {
        case .day:
            let c = calendar.dateComponents([.month, .day, .weekday], from: start)
            title = "\(c.month ?? 0)月\(c.day ?? 0)日"
            subtitle = "周" + weekdaySymbols[((c.weekday ?? 1) - 1 + 7) % 7]
        case .week:
            // 展示末日 = 起始 + 6 天（周日），对齐 demo 的闭区间标题 "M月D日 - M月D日"。
            let lastDay = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            let s = calendar.dateComponents([.month, .day], from: start)
            let e = calendar.dateComponents([.month, .day], from: lastDay)
            title = "\(s.month ?? 0)月\(s.day ?? 0)日 - \(e.month ?? 0)月\(e.day ?? 0)日"
            subtitle = offset == 0 ? "本周" : "\(-offset)周前"
        case .month:
            let c = calendar.dateComponents([.year, .month], from: start)
            title = "\(c.year ?? 0)年\(c.month ?? 0)月"
            subtitle = offset == 0 ? "本月" : nil
        case .year:
            let c = calendar.dateComponents([.year], from: start)
            title = "\(c.year ?? 0)年"
            subtitle = offset == 0 ? "今年" : nil
        }

        return StatPeriod(start: start, end: end, title: title, subtitle: subtitle)
    }

    /// 该 offset 是否已是"当前区间或更未来"——即导航 `›` 是否应禁用（禁未来，节点约束/demo `atNow`）。
    static func isAtOrAfterNow(offset: Int) -> Bool { offset >= 0 }
}
