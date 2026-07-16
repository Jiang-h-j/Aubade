import XCTest
import SwiftData
@testable import Aubade

/// TRD 02 验证点 3~6：统计聚合纯函数 `StatisticsAggregator`。
///
/// 核心：区间合计按方向 + 半开过滤（区间外不计）、分类占比降序 + pct + 总额 0 空数组 + nil 分类成组、
/// 趋势桶数跟随粒度（month=当月天数 / year=12 / week·day=7）且仅统计支出、预算阈值 normal/near/over。
/// 用固定 UTC calendar + firstWeekday=2 + 固定 now(2026-07-14 周二)，避免 CI 漂移。
@MainActor
final class StatisticsAggregatorTests: XCTestCase {

    // 持有容器：ModelContext 不强引用 ModelContainer（N00 SIGTRAP 坑）。
    private var container: ModelContainer!

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
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

    private func date(_ y: Int, _ mo: Int, _ d: Int,
                      _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        var dc = DateComponents()
        dc.year = y; dc.month = mo; dc.day = d
        dc.hour = h; dc.minute = mi; dc.second = s
        dc.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: dc)!
    }

    private var now: Date { date(2026, 7, 14, 12, 0, 0) }

    @discardableResult
    private func makeTx(_ amount: String, _ direction: TransactionDirection, _ occurredAt: Date,
                        category: LedgerCategory? = nil) throws -> Transaction {
        try LedgerStore(container.mainContext).createTransaction(
            amount: Decimal(string: amount)!, direction: direction,
            occurredAt: occurredAt, category: category, source: .manual)
    }

    private func makeCategory(_ name: String, _ direction: TransactionDirection = .expense) throws -> LedgerCategory {
        try LedgerStore(container.mainContext).createCategory(name: name, direction: direction)
    }

    private func allTxs() throws -> [Transaction] {
        try LedgerStore(container.mainContext).fetch(Transaction.self)
    }

    // MARK: - 验证点 3：区间合计 total（按方向 + 半开过滤 + Decimal 精度）

    func testTotalByDirectionInMonth() throws {
        let p = StatPeriod.make(grain: .month, offset: 0, now: now, calendar: cal)  // [07-01, 08-01)
        _ = try makeTx("100", .expense, date(2026, 7, 3))
        _ = try makeTx("200", .expense, date(2026, 7, 20))
        _ = try makeTx("300", .income, date(2026, 7, 10))
        _ = try makeTx("999", .expense, date(2026, 6, 30, 23, 59, 59))  // 上月最后一刻 → 排除
        _ = try makeTx("888", .expense, date(2026, 8, 1, 0, 0, 0))      // 下月第一刻 → 排除（半开）

        let txs = try allTxs()
        XCTAssertEqual(StatisticsAggregator.total(txs, in: p, direction: .expense), Decimal(string: "300")!)
        XCTAssertEqual(StatisticsAggregator.total(txs, in: p, direction: .income), Decimal(string: "300")!)
    }

    func testTotalDecimalPrecision() throws {
        let p = StatPeriod.make(grain: .month, offset: 0, now: now, calendar: cal)
        _ = try makeTx("0.1", .expense, date(2026, 7, 2))
        _ = try makeTx("0.2", .expense, date(2026, 7, 3))
        // 0.1 + 0.2 在 Double 下为 0.30000...4；纯 Decimal 必须精确。
        XCTAssertEqual(StatisticsAggregator.total(try allTxs(), in: p, direction: .expense),
                       Decimal(string: "0.3")!)
    }

    // MARK: - 验证点 4：分类占比 expenseBreakdown

    func testExpenseBreakdownDescendingAndPct() throws {
        let p = StatPeriod.make(grain: .month, offset: 0, now: now, calendar: cal)
        let food = try makeCategory("食")
        let play = try makeCategory("玩")
        _ = try makeTx("600", .expense, date(2026, 7, 2), category: food)
        _ = try makeTx("300", .expense, date(2026, 7, 3), category: play)
        _ = try makeTx("100", .expense, date(2026, 7, 4), category: play)
        _ = try makeTx("500", .income, date(2026, 7, 5), category: food)  // 收入不计入支出占比

        let rows = StatisticsAggregator.expenseBreakdown(try allTxs(), in: p)
        // 食 600 / 玩 400，总 1000。降序：食在前。
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].category?.id, food.id)
        XCTAssertEqual(rows[0].amount, Decimal(string: "600")!)
        XCTAssertEqual(rows[0].pct, 60)
        XCTAssertEqual(rows[1].category?.id, play.id)
        XCTAssertEqual(rows[1].amount, Decimal(string: "400")!)
        XCTAssertEqual(rows[1].pct, 40)
        // 各类金额和 == 总支出
        XCTAssertEqual(rows.reduce(Decimal(0)) { $0 + $1.amount }, Decimal(string: "1000")!)
    }

    func testExpenseBreakdownEmptyWhenNoExpense() throws {
        let p = StatPeriod.make(grain: .month, offset: 0, now: now, calendar: cal)
        _ = try makeTx("500", .income, date(2026, 7, 5))  // 只有收入
        XCTAssertTrue(StatisticsAggregator.expenseBreakdown(try allTxs(), in: p).isEmpty)
    }

    func testExpenseBreakdownNilCategoryGroupedWithSentinel() throws {
        let p = StatPeriod.make(grain: .month, offset: 0, now: now, calendar: cal)
        _ = try makeTx("100", .expense, date(2026, 7, 2))  // 无分类
        _ = try makeTx("50", .expense, date(2026, 7, 3))   // 无分类 → 同组

        let rows = StatisticsAggregator.expenseBreakdown(try allTxs(), in: p)
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].category)
        XCTAssertEqual(rows[0].amount, Decimal(string: "150")!)
        XCTAssertEqual(rows[0].id, BreakdownRow.uncategorizedID)  // 哨兵 id
    }

    // MARK: - 验证点 5：趋势 expenseTrend（桶数跟随粒度 + 仅支出）

    func testExpenseTrendMonthBucketCountEqualsDaysInMonth() throws {
        let p = StatPeriod.make(grain: .month, offset: 0, now: now, calendar: cal)  // 2026-07，31 天
        _ = try makeTx("100", .expense, date(2026, 7, 1))
        _ = try makeTx("200", .expense, date(2026, 7, 31))
        _ = try makeTx("999", .income, date(2026, 7, 15))  // 收入不计入趋势

        let series = StatisticsAggregator.expenseTrend(grain: .month, period: p,
                                                       txs: try allTxs(), calendar: cal)
        XCTAssertEqual(series.count, 31)
        XCTAssertEqual(series.first?.value, Decimal(string: "100")!)   // 7/1
        XCTAssertEqual(series.last?.value, Decimal(string: "200")!)    // 7/31
        XCTAssertEqual(series[14].value, Decimal(0))                   // 7/15 只有收入 → 0
        XCTAssertEqual(series.first?.label, "7/1")
    }

    func testExpenseTrendYearHasTwelveBuckets() throws {
        let p = StatPeriod.make(grain: .year, offset: 0, now: now, calendar: cal)
        _ = try makeTx("100", .expense, date(2026, 1, 15))
        _ = try makeTx("300", .expense, date(2026, 12, 20))

        let series = StatisticsAggregator.expenseTrend(grain: .year, period: p,
                                                       txs: try allTxs(), calendar: cal)
        XCTAssertEqual(series.count, 12)
        XCTAssertEqual(series[0].value, Decimal(string: "100")!)    // 1月
        XCTAssertEqual(series[11].value, Decimal(string: "300")!)   // 12月
        XCTAssertEqual(series[0].label, "1月")
        XCTAssertEqual(series[11].label, "12月")
    }

    func testExpenseTrendWeekHasSevenBuckets() throws {
        let p = StatPeriod.make(grain: .week, offset: 0, now: now, calendar: cal)  // [07-13, 07-20)
        _ = try makeTx("100", .expense, date(2026, 7, 13))  // 周一
        _ = try makeTx("70", .expense, date(2026, 7, 19))   // 周日

        let series = StatisticsAggregator.expenseTrend(grain: .week, period: p,
                                                       txs: try allTxs(), calendar: cal)
        XCTAssertEqual(series.count, 7)
        XCTAssertEqual(series[0].value, Decimal(string: "100")!)   // 7/13
        XCTAssertEqual(series[6].value, Decimal(string: "70")!)    // 7/19
        XCTAssertEqual(series[0].label, "7/13")
    }

    func testExpenseTrendDayShowsOwningWeek() throws {
        // 日档趋势展示"所在周 7 天"（对齐 demo）：offset 0 → 07-14 所在周 [07-13, 07-20)。
        let p = StatPeriod.make(grain: .day, offset: 0, now: now, calendar: cal)
        _ = try makeTx("42", .expense, date(2026, 7, 14))
        let series = StatisticsAggregator.expenseTrend(grain: .day, period: p,
                                                       txs: try allTxs(), calendar: cal)
        XCTAssertEqual(series.count, 7)
        XCTAssertEqual(series[0].label, "7/13")           // 周一起
        XCTAssertEqual(series[1].value, Decimal(string: "42")!)  // 7/14 = 周二
    }

    // MARK: - 验证点 6：预算阈值 budgetProgress（PRD 验收 7）

    func testBudgetProgressThresholds() {
        XCTAssertEqual(StatisticsAggregator.budgetProgress(spent: 79, budget: 100).state, .normal)
        XCTAssertEqual(StatisticsAggregator.budgetProgress(spent: 80, budget: 100).state, .near)
        XCTAssertEqual(StatisticsAggregator.budgetProgress(spent: 100, budget: 100).state, .near)
        XCTAssertEqual(StatisticsAggregator.budgetProgress(spent: 101, budget: 100).state, .over)

        // 137% = 2055/1500（PRD 验收 7 示例）
        let over = StatisticsAggregator.budgetProgress(spent: Decimal(string: "2055")!,
                                                       budget: Decimal(string: "1500")!)
        XCTAssertEqual(over.pct, 137)
        XCTAssertEqual(over.state, .over)
    }

    func testBudgetProgressZeroBudgetGuard() {
        // 脏数据防除零：budget=0 → (0, normal)。
        let r = StatisticsAggregator.budgetProgress(spent: 100, budget: 0)
        XCTAssertEqual(r.pct, 0)
        XCTAssertEqual(r.state, .normal)
    }

    // MARK: - 验证点：阈值驱动 near 判定（N07 切片 01，PRD 验收 9）

    func testBudgetProgressRespectsNearThreshold() {
        // nearThreshold: 80 → 等价现有默认行为（回归对照）。
        XCTAssertEqual(StatisticsAggregator.budgetProgress(spent: 79, budget: 100, nearThreshold: 80).state, .normal)
        XCTAssertEqual(StatisticsAggregator.budgetProgress(spent: 80, budget: 100, nearThreshold: 80).state, .near)
        XCTAssertEqual(StatisticsAggregator.budgetProgress(spent: 100, budget: 100, nearThreshold: 80).state, .near)
        XCTAssertEqual(StatisticsAggregator.budgetProgress(spent: 101, budget: 100, nearThreshold: 80).state, .over)

        // nearThreshold: 50 → 阈值真的驱动 .near 判定（50% 即接近，79% 仍接近）。
        XCTAssertEqual(StatisticsAggregator.budgetProgress(spent: 49, budget: 100, nearThreshold: 50).state, .normal)
        XCTAssertEqual(StatisticsAggregator.budgetProgress(spent: 50, budget: 100, nearThreshold: 50).state, .near)
        XCTAssertEqual(StatisticsAggregator.budgetProgress(spent: 100, budget: 100, nearThreshold: 50).state, .near)
        XCTAssertEqual(StatisticsAggregator.budgetProgress(spent: 101, budget: 100, nearThreshold: 50).state, .over)

        // pct 计算与阈值正交：Decimal 无浮点误差（137% 仍 over，与阈值无关）。
        let over = StatisticsAggregator.budgetProgress(spent: Decimal(string: "2055")!,
                                                       budget: Decimal(string: "1500")!,
                                                       nearThreshold: 50)
        XCTAssertEqual(over.pct, 137)
        XCTAssertEqual(over.state, .over)
    }

    // MARK: - 验证点：AppConfig.overspendThreshold 读取兜底（N07 切片 01）

    func testAppConfigOverspendThresholdFallbackAndClamp() throws {
        let suite = "test.AppConfig.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        // 未设值 → 返回默认 80（而非 integer(forKey:) 的 0）。
        XCTAssertEqual(AppConfig.overspendThreshold(defaults), 80)

        // 越下界（30 < 50）→ 夹到下界 50。
        defaults.set(30, forKey: AppConfig.overspendThresholdKey)
        XCTAssertEqual(AppConfig.overspendThreshold(defaults), 50)

        // 越上界（120 > 100）→ 夹到上界 100。
        defaults.set(120, forKey: AppConfig.overspendThresholdKey)
        XCTAssertEqual(AppConfig.overspendThreshold(defaults), 100)

        // 界内（65）→ 原样返回。
        defaults.set(65, forKey: AppConfig.overspendThresholdKey)
        XCTAssertEqual(AppConfig.overspendThreshold(defaults), 65)
    }
}
