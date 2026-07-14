import XCTest
@testable import Aubade

/// TRD 02 验证点 1、2：统计区间口径纯函数 `StatPeriod`。
///
/// 核心：四档半开区间 `[start, end)` 边界精确（上界=下一周期起点、排他）、周首日=周一、
/// 标题/副标题对齐 demo 口径、禁未来 `isAtOrAfterNow`。用固定 UTC calendar + firstWeekday=2
/// + 固定 now(2026-07-14 周二)，避免 CI 时区/周首日漂移。
final class StatPeriodTests: XCTestCase {

    // 固定日历：UTC + 周一为周首日，钉死区间与周界。
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2   // 周一
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int,
                      _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        var dc = DateComponents()
        dc.year = y; dc.month = mo; dc.day = d
        dc.hour = h; dc.minute = mi; dc.second = s
        dc.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: dc)!
    }

    // 2026-07-14 是周二；firstWeekday=2 下所在周 = [周一 07-13, 周一 07-20)。
    private var now: Date { date(2026, 7, 14, 12, 0, 0) }

    // MARK: - 验证点 1：日档半开边界 + 标题/副标题

    func testDayGrainCurrent() {
        let p = StatPeriod.make(grain: .day, offset: 0, now: now, calendar: cal)
        XCTAssertEqual(p.start, date(2026, 7, 14, 0, 0, 0))
        XCTAssertEqual(p.end, date(2026, 7, 15, 0, 0, 0))   // 次日 0 点，排他
        XCTAssertEqual(p.title, "7月14日")
        XCTAssertEqual(p.subtitle, "周二")
    }

    func testDayGrainPastOffset() {
        let p = StatPeriod.make(grain: .day, offset: -1, now: now, calendar: cal)
        XCTAssertEqual(p.start, date(2026, 7, 13, 0, 0, 0))
        XCTAssertEqual(p.end, date(2026, 7, 14, 0, 0, 0))
        XCTAssertEqual(p.title, "7月13日")
        XCTAssertEqual(p.subtitle, "周一")
    }

    // MARK: - 验证点 1：周档 firstWeekday=2（周一起、周日末）

    func testWeekGrainMondayStart() {
        let p = StatPeriod.make(grain: .week, offset: 0, now: now, calendar: cal)
        // 周一为起点，下周一为排他上界。
        XCTAssertEqual(p.start, date(2026, 7, 13, 0, 0, 0))   // 周一
        XCTAssertEqual(p.end, date(2026, 7, 20, 0, 0, 0))     // 下周一，排他
        XCTAssertEqual(cal.component(.weekday, from: p.start), 2)  // 2=周一
        XCTAssertEqual(p.title, "7月13日 - 7月19日")            // 末日=周日 07-19
        XCTAssertEqual(p.subtitle, "本周")
    }

    func testWeekGrainPastSubtitle() {
        let p = StatPeriod.make(grain: .week, offset: -2, now: now, calendar: cal)
        XCTAssertEqual(p.start, date(2026, 6, 29, 0, 0, 0))
        XCTAssertEqual(p.end, date(2026, 7, 6, 0, 0, 0))
        XCTAssertEqual(p.subtitle, "2周前")
    }

    // MARK: - 验证点 1：月档半开边界

    func testMonthGrainCurrent() {
        let p = StatPeriod.make(grain: .month, offset: 0, now: now, calendar: cal)
        XCTAssertEqual(p.start, date(2026, 7, 1, 0, 0, 0))
        XCTAssertEqual(p.end, date(2026, 8, 1, 0, 0, 0))     // 下月 1 日 0 点，排他
        XCTAssertEqual(p.title, "2026年7月")
        XCTAssertEqual(p.subtitle, "本月")
    }

    func testMonthGrainPastNilSubtitle() {
        let p = StatPeriod.make(grain: .month, offset: -1, now: now, calendar: cal)
        XCTAssertEqual(p.start, date(2026, 6, 1, 0, 0, 0))
        XCTAssertEqual(p.end, date(2026, 7, 1, 0, 0, 0))
        XCTAssertEqual(p.title, "2026年6月")
        XCTAssertNil(p.subtitle)   // 非当前月不显示副标题
    }

    // MARK: - 验证点 1：年档半开边界

    func testYearGrainCurrent() {
        let p = StatPeriod.make(grain: .year, offset: 0, now: now, calendar: cal)
        XCTAssertEqual(p.start, date(2026, 1, 1, 0, 0, 0))
        XCTAssertEqual(p.end, date(2027, 1, 1, 0, 0, 0))     // 次年 1 日 0 点，排他
        XCTAssertEqual(p.title, "2026年")
        XCTAssertEqual(p.subtitle, "今年")
    }

    func testYearGrainPastNilSubtitle() {
        let p = StatPeriod.make(grain: .year, offset: -1, now: now, calendar: cal)
        XCTAssertEqual(p.start, date(2025, 1, 1, 0, 0, 0))
        XCTAssertEqual(p.end, date(2026, 1, 1, 0, 0, 0))
        XCTAssertEqual(p.title, "2025年")
        XCTAssertNil(p.subtitle)
    }

    // MARK: - 验证点 2：禁未来

    func testIsAtOrAfterNow() {
        XCTAssertTrue(StatPeriod.isAtOrAfterNow(offset: 0))    // 当前区间 → › 禁用
        XCTAssertTrue(StatPeriod.isAtOrAfterNow(offset: 1))    // 未来 → 禁用
        XCTAssertFalse(StatPeriod.isAtOrAfterNow(offset: -1))  // 过去 → 可翻
    }
}
