import XCTest
import SwiftData
@testable import Aubade

/// 验收 3：金额用 Decimal 存取无浮点误差。
@MainActor
final class DecimalPrecisionTests: XCTestCase {

    // 必须持有容器：ModelContext 不强引用 ModelContainer。
    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        container = PersistenceController.makeInMemoryContainer()
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func makeStore() -> LedgerStore {
        LedgerStore(container.mainContext)
    }

    /// 写 Decimal(string: "35.55") 入三处金额字段，读回严格 == 相等、无浮点误差。
    func testDecimalRoundTripAcrossAllAmountFields() throws {
        let value = Decimal(string: "35.55")!
        let store = makeStore()

        try store.createTransaction(amount: value, direction: .expense,
                                    occurredAt: Date(), source: .manual)
        try store.createBudget(periodType: .weekly, amount: value)
        try store.createBalanceBaseline(initialAmount: value, establishedAt: Date())

        XCTAssertEqual(try store.fetch(Transaction.self).first?.amount, value)
        XCTAssertEqual(try store.fetch(Budget.self).first?.amount, value)
        XCTAssertEqual(try store.fetch(BalanceBaseline.self).first?.initialAmount, value)
    }

    /// 一个二进制浮点无法精确表示的值，Decimal 依然精确往返。
    func testHardToRepresentValueStaysExact() throws {
        let value = Decimal(string: "0.10")! + Decimal(string: "0.20")!
        XCTAssertEqual(value, Decimal(string: "0.30")!)

        let store = makeStore()
        try store.createTransaction(amount: value, direction: .expense,
                                    occurredAt: Date(), source: .manual)
        XCTAssertEqual(try store.fetch(Transaction.self).first?.amount, Decimal(string: "0.30")!)
    }
}
