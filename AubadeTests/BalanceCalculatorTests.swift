import XCTest
import SwiftData
@testable import Aubade

/// TRD 01 验证点 1~5：剩余金额派生纯函数 `BalanceCalculator` + 基线唯一写入 `LedgerStore.setBalanceBaseline`。
///
/// 核心：无基线返回 nil、剩余公式 Decimal 无浮点误差、基线后边界 `>=`、写侧唯一化收敛到一条、
/// 本月合计按方向求和。用固定 UTC calendar + firstWeekday=2 + 固定 now，避免 CI 时区/周首日漂移。
@MainActor
final class BalanceCalculatorTests: XCTestCase {

    // 持有容器：ModelContext 不强引用 ModelContainer（N00 SIGTRAP 坑）。
    private var container: ModelContainer!

    // 固定日历：UTC + 周一为周首日，钉死本月边界计算。
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
    private func makeTx(_ amount: String, _ direction: TransactionDirection,
                        _ occurredAt: Date) throws -> Transaction {
        try LedgerStore(container.mainContext).createTransaction(
            amount: Decimal(string: amount)!, direction: direction,
            occurredAt: occurredAt, source: .manual)
    }

    private func makeBaseline(_ amount: String, _ establishedAt: Date) -> BalanceBaseline {
        BalanceBaseline(initialAmount: Decimal(string: amount)!, establishedAt: establishedAt)
    }

    // MARK: - 验证点 1：无基线返回 nil

    func testRemainingNilWithoutBaseline() throws {
        let txs = [try makeTx("100", .income, date(2026, 7, 1))]
        XCTAssertNil(BalanceCalculator.remaining(transactions: txs, baseline: nil))
    }

    // MARK: - 验证点 2：剩余公式 + Decimal 无浮点误差

    func testRemainingFormula() throws {
        let baseline = makeBaseline("12000", date(2026, 7, 1))
        let txs = [
            try makeTx("500", .income, date(2026, 7, 2)),
            try makeTx("200", .expense, date(2026, 7, 3)),
        ]
        // 12000 + 500 − 200 = 12300
        XCTAssertEqual(BalanceCalculator.remaining(transactions: txs, baseline: baseline),
                       Decimal(string: "12300")!)
    }

    func testRemainingDecimalPrecision() throws {
        // 0.1 + 0.2 在 Double 下为 0.30000...4；纯 Decimal 必须精确。
        let baseline = makeBaseline("0", date(2026, 7, 1))
        let txs = [
            try makeTx("0.1", .income, date(2026, 7, 2)),
            try makeTx("0.2", .income, date(2026, 7, 3)),
            try makeTx("35.55", .expense, date(2026, 7, 4)),
        ]
        // 0 + (0.1 + 0.2) − 35.55 = −35.25，精确无误差
        XCTAssertEqual(BalanceCalculator.remaining(transactions: txs, baseline: baseline),
                       Decimal(string: "-35.25")!)
    }

    // MARK: - 验证点 3：基线后边界 `>=`（同刻计入，早 1 秒不计，晚 1 秒计）

    func testBaselineBoundaryInclusive() throws {
        let established = date(2026, 7, 10, 12, 0, 0)
        let baseline = makeBaseline("1000", established)
        let txs = [
            try makeTx("100", .income, established),                          // 同刻 → 计入
            try makeTx("50", .income, date(2026, 7, 10, 11, 59, 59)),         // 早 1 秒 → 不计
            try makeTx("30", .income, date(2026, 7, 10, 12, 0, 1)),          // 晚 1 秒 → 计入
        ]
        // 1000 + 100 + 30 = 1130（早 1 秒的 50 被排除）
        XCTAssertEqual(BalanceCalculator.remaining(transactions: txs, baseline: baseline),
                       Decimal(string: "1130")!)
    }

    // MARK: - 验证点 4：写侧唯一化，连续设置收敛到一条且为最新值

    func testSetBalanceBaselineUniqueness() throws {
        let store = LedgerStore(container.mainContext)
        try store.setBalanceBaseline(initialAmount: Decimal(string: "8000")!,
                                     establishedAt: date(2026, 7, 1))
        try store.setBalanceBaseline(initialAmount: Decimal(string: "12000")!,
                                     establishedAt: date(2026, 7, 2))

        XCTAssertEqual(try store.fetch(BalanceBaseline.self).count, 1)
        XCTAssertEqual(try store.currentBaseline()?.initialAmount, Decimal(string: "12000")!)
    }

    func testCurrentBaselinePicksLatest() throws {
        let store = LedgerStore(container.mainContext)
        // 直接建两条（绕过唯一化）模拟历史脏数据，currentBaseline 应取 establishedAt 最新。
        try store.createBalanceBaseline(initialAmount: Decimal(string: "5000")!,
                                        establishedAt: date(2026, 7, 1))
        try store.createBalanceBaseline(initialAmount: Decimal(string: "9000")!,
                                        establishedAt: date(2026, 7, 5))
        XCTAssertEqual(try store.currentBaseline()?.initialAmount, Decimal(string: "9000")!)
    }

    // MARK: - 验证点 5：本月合计 sum 按 .thisMonth 过滤 + 按方向求和

    func testMonthlySum() throws {
        let now = date(2026, 7, 15)
        _ = try makeTx("100", .expense, date(2026, 7, 3))    // 本月支出
        _ = try makeTx("200", .expense, date(2026, 7, 20))   // 本月支出
        _ = try makeTx("300", .income, date(2026, 7, 10))    // 本月收入
        _ = try makeTx("999", .expense, date(2026, 6, 30))   // 上月 → 排除
        _ = try makeTx("888", .income, date(2026, 8, 1))     // 下月 → 排除

        let all = try LedgerStore(container.mainContext).fetch(Transaction.self)
        let month = LedgerFilter.apply(all, category: .all, dateRange: .thisMonth,
                                       now: now, calendar: cal)

        XCTAssertEqual(BalanceCalculator.sum(month, direction: .expense),
                       Decimal(string: "300")!)   // 100 + 200
        XCTAssertEqual(BalanceCalculator.sum(month, direction: .income),
                       Decimal(string: "300")!)   // 300
    }

    // MARK: - 补充：sum 空集为 0

    func testSumEmptyIsZero() {
        XCTAssertEqual(BalanceCalculator.sum([], direction: .expense), Decimal(0))
    }
}
