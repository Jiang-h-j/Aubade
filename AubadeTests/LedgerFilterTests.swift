import XCTest
import SwiftData
@testable import Aubade

/// 切片 03：账单筛选/分组纯函数 `LedgerFilter` / `DateRangeFilter` / `CategoryFilter`。
///
/// 核心是**钉死半开区间 `[start, end)`**（防 off-by-one，TRD 验证点 1）：本周/本月上边界落在
/// 下一周期第一刻应判出、上一刻应判入；自定义含所选止日整天、止日次日 0 点判出。
/// 用固定 UTC calendar + firstWeekday=2（周一）+ 固定 now，避免 CI 时区/周首日漂移。
@MainActor
final class LedgerFilterTests: XCTestCase {

    // 持有容器：ModelContext 不强引用 ModelContainer（N00 SIGTRAP 坑）。
    private var container: ModelContainer!

    // 固定日历：UTC + 周一为周首日，钉死本周/本月边界计算。
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2   // 周一
        return c
    }()

    override func setUp() {
        super.setUp()
        container = PersistenceController.makeInMemoryContainer()
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    // MARK: - 构造 helper

    private func date(_ y: Int, _ mo: Int, _ d: Int,
                      _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        var dc = DateComponents()
        dc.year = y; dc.month = mo; dc.day = d
        dc.hour = h; dc.minute = mi; dc.second = s
        dc.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: dc)!
    }

    @discardableResult
    private func makeTx(_ occurredAt: Date, category: LedgerCategory? = nil,
                        direction: TransactionDirection = .expense) throws -> Transaction {
        try LedgerStore(container.mainContext).createTransaction(
            amount: Decimal(10), direction: direction,
            occurredAt: occurredAt, category: category, source: .manual)
    }

    // MARK: - 本月边界（now = 2026-03-15，本月区间 [03-01 00:00, 04-01 00:00)）

    func testThisMonthUpperBoundExclusive() {
        let now = date(2026, 3, 15, 12)
        // 本月最后一刻判入。
        XCTAssertTrue(DateRangeFilter.thisMonth.contains(date(2026, 3, 31, 23, 59, 59), now: now, calendar: cal))
        // 下月第一刻判出（半开右端排他，不得误纳）。
        XCTAssertFalse(DateRangeFilter.thisMonth.contains(date(2026, 4, 1, 0, 0, 0), now: now, calendar: cal))
    }

    func testThisMonthLowerBoundInclusive() {
        let now = date(2026, 3, 15, 12)
        // 本月第一刻判入。
        XCTAssertTrue(DateRangeFilter.thisMonth.contains(date(2026, 3, 1, 0, 0, 0), now: now, calendar: cal))
        // 上月最后一刻判出。
        XCTAssertFalse(DateRangeFilter.thisMonth.contains(date(2026, 2, 28, 23, 59, 59), now: now, calendar: cal))
    }

    // MARK: - 本周边界（now = 2026-03-15 周日，周一起 → 本周 [03-09 00:00, 03-16 00:00)）

    func testThisWeekUpperBoundExclusive() {
        let now = date(2026, 3, 15, 12)   // 周日
        // 本周最后一刻（周日 23:59:59）判入。
        XCTAssertTrue(DateRangeFilter.thisWeek.contains(date(2026, 3, 15, 23, 59, 59), now: now, calendar: cal))
        // 下周第一刻（下周一 00:00）判出。
        XCTAssertFalse(DateRangeFilter.thisWeek.contains(date(2026, 3, 16, 0, 0, 0), now: now, calendar: cal))
    }

    func testThisWeekLowerBoundInclusive() {
        let now = date(2026, 3, 15, 12)
        // 本周第一刻（周一 00:00）判入。
        XCTAssertTrue(DateRangeFilter.thisWeek.contains(date(2026, 3, 9, 0, 0, 0), now: now, calendar: cal))
        // 上周最后一刻判出。
        XCTAssertFalse(DateRangeFilter.thisWeek.contains(date(2026, 3, 8, 23, 59, 59), now: now, calendar: cal))
    }

    // MARK: - 自定义区间（含所选止日整天，止日次日 0 点排他）

    func testCustomIncludesEndDayFullDayAndExcludesNext() {
        // 用户选 03-10 ~ 03-12（起止各带任意时刻，应被归一到整天）。
        let range = DateRangeFilter.custom(start: date(2026, 3, 10, 15, 30), end: date(2026, 3, 12, 8, 0))
        // 止日整天含入：03-12 23:59:59 判入。
        XCTAssertTrue(range.contains(date(2026, 3, 12, 23, 59, 59), calendar: cal))
        // 止日次日 00:00 判出。
        XCTAssertFalse(range.contains(date(2026, 3, 13, 0, 0, 0), calendar: cal))
        // 起日 00:00 判入（归一到 startOfDay）。
        XCTAssertTrue(range.contains(date(2026, 3, 10, 0, 0, 0), calendar: cal))
        // 起日前一刻判出。
        XCTAssertFalse(range.contains(date(2026, 3, 9, 23, 59, 59), calendar: cal))
    }

    // MARK: - 全部时间

    func testAllRangeContainsEverything() {
        XCTAssertTrue(DateRangeFilter.all.contains(date(2000, 1, 1), calendar: cal))
        XCTAssertTrue(DateRangeFilter.all.contains(date(2099, 12, 31), calendar: cal))
    }

    // MARK: - 分类过滤

    func testCategoryFilterAllMatchesEverything() throws {
        let store = LedgerStore(container.mainContext)
        let food = try store.createCategory(name: "食", direction: .expense, sortOrder: 1)
        let txWithCat = try makeTx(date(2026, 3, 10), category: food)
        let txNoCat = try makeTx(date(2026, 3, 10))
        XCTAssertTrue(CategoryFilter.all.matches(txWithCat))
        XCTAssertTrue(CategoryFilter.all.matches(txNoCat))
    }

    func testCategoryFilterSomeMatchesOnlyThatCategory() throws {
        let store = LedgerStore(container.mainContext)
        let food = try store.createCategory(name: "食", direction: .expense, sortOrder: 1)
        let travel = try store.createCategory(name: "行", direction: .expense, sortOrder: 2)
        let txFood = try makeTx(date(2026, 3, 10), category: food)
        let txTravel = try makeTx(date(2026, 3, 10), category: travel)
        let txNil = try makeTx(date(2026, 3, 10))

        let filter = CategoryFilter.some(food)
        XCTAssertTrue(filter.matches(txFood))
        XCTAssertFalse(filter.matches(txTravel), "别的分类不命中")
        XCTAssertFalse(filter.matches(txNil), "未分类不命中具体分类")
    }

    func testCategoryFilterEqualityByIdNotReference() throws {
        let store = LedgerStore(container.mainContext)
        let food = try store.createCategory(name: "食", direction: .expense, sortOrder: 1)
        // 相同分类 → 相等（Hashable 基于 id，@Query 刷新后按 id 稳定）。
        XCTAssertEqual(CategoryFilter.some(food), CategoryFilter.some(food))
        XCTAssertNotEqual(CategoryFilter.some(food), CategoryFilter.all)
    }

    // MARK: - 两条件叠加（分类 × 时间，验收 6）

    func testApplyCombinesCategoryAndDateRange() throws {
        let store = LedgerStore(container.mainContext)
        let food = try store.createCategory(name: "食", direction: .expense, sortOrder: 1)
        let travel = try store.createCategory(name: "行", direction: .expense, sortOrder: 2)
        let inDate = try makeTx(date(2026, 3, 10), category: food)   // 食 + 区间内 → 留
        _ = try makeTx(date(2026, 3, 20), category: food)           // 食 + 区间外 → 去
        _ = try makeTx(date(2026, 3, 10), category: travel)         // 行 + 区间内 → 去
        _ = try makeTx(date(2026, 3, 20), category: travel)         // 行 + 区间外 → 去

        let all = try store.fetch(Transaction.self)
        let result = LedgerFilter.apply(all,
                                        category: .some(food),
                                        dateRange: .custom(start: date(2026, 3, 10), end: date(2026, 3, 12)),
                                        calendar: cal)
        XCTAssertEqual(result.count, 1, "仅『食』且落在区间内的一笔")
        XCTAssertEqual(result.first?.id, inDate.id)
    }

    // MARK: - 分组倒序（验收 2）

    func testGroupByDayOrdersDaysAndItemsDescending() throws {
        let store = LedgerStore(container.mainContext)
        try makeTx(date(2026, 3, 10, 9, 0))
        try makeTx(date(2026, 3, 10, 18, 0))
        try makeTx(date(2026, 3, 11, 12, 0))
        try makeTx(date(2026, 3, 12, 8, 0))

        let all = try store.fetch(Transaction.self)
        let groups = LedgerFilter.groupByDay(all, calendar: cal)

        // 3 个自然日分组，按日期倒序。
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.map(\.day), [date(2026, 3, 12), date(2026, 3, 11), date(2026, 3, 10)])
        // 03-10 组内按 occurredAt 倒序：18:00 在前、09:00 在后。
        let firstGroupTimes = groups.last?.items.map(\.occurredAt)
        XCTAssertEqual(firstGroupTimes, [date(2026, 3, 10, 18, 0), date(2026, 3, 10, 9, 0)])
    }

    func testGroupByDayMergesSameDay() throws {
        let store = LedgerStore(container.mainContext)
        try makeTx(date(2026, 3, 10, 1, 0))
        try makeTx(date(2026, 3, 10, 23, 0))
        let groups = LedgerFilter.groupByDay(try store.fetch(Transaction.self), calendar: cal)
        XCTAssertEqual(groups.count, 1, "同一自然日归一组")
        XCTAssertEqual(groups.first?.items.count, 2)
    }
}
