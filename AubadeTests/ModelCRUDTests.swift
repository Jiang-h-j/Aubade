import XCTest
import SwiftData
@testable import Aubade

/// 验收 2：四模型各跑"新增→查询到→修改→删除"。全部用内存容器隔离。
@MainActor
final class ModelCRUDTests: XCTestCase {

    // 必须持有容器：ModelContext 不强引用 ModelContainer，
    // 若写 makeInMemoryContainer().mainContext 则容器被释放、后续 insert 崩溃。
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

    func testCategoryCRUD() throws {
        let store = makeStore()

        // 新增
        let category = try store.createCategory(name: "餐饮", direction: .expense)
        // 查询到
        var all = try store.fetch(LedgerCategory.self)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "餐饮")
        // 修改
        category.name = "餐饮美食"
        try store.context.save()
        all = try store.fetch(LedgerCategory.self)
        XCTAssertEqual(all.first?.name, "餐饮美食")
        // 删除
        try store.delete(category)
        all = try store.fetch(LedgerCategory.self)
        XCTAssertTrue(all.isEmpty)
    }

    func testTransactionCRUD() throws {
        let store = makeStore()

        let tx = try store.createTransaction(
            amount: Decimal(string: "12.30")!, direction: .expense,
            occurredAt: Date(), source: .manual)
        var all = try store.fetch(Transaction.self)
        XCTAssertEqual(all.count, 1)

        let originalUpdatedAt = tx.updatedAt
        try store.updateTransaction(tx) { $0.merchant = "便利店" }
        all = try store.fetch(Transaction.self)
        XCTAssertEqual(all.first?.merchant, "便利店")
        XCTAssertGreaterThanOrEqual(all.first!.updatedAt, originalUpdatedAt)

        try store.delete(tx)
        all = try store.fetch(Transaction.self)
        XCTAssertTrue(all.isEmpty)
    }

    func testBudgetCRUD() throws {
        let store = makeStore()

        let budget = try store.createBudget(periodType: .monthly, amount: Decimal(string: "3000")!)
        var all = try store.fetch(Budget.self)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.periodType, .monthly)

        budget.amount = Decimal(string: "3500")!
        try store.context.save()
        all = try store.fetch(Budget.self)
        XCTAssertEqual(all.first?.amount, Decimal(string: "3500")!)

        try store.delete(budget)
        XCTAssertTrue(try store.fetch(Budget.self).isEmpty)
    }

    func testBalanceBaselineCRUD() throws {
        let store = makeStore()

        let baseline = try store.createBalanceBaseline(
            initialAmount: Decimal(string: "10000.50")!, establishedAt: Date())
        var all = try store.fetch(BalanceBaseline.self)
        XCTAssertEqual(all.count, 1)

        baseline.initialAmount = Decimal(string: "9999.99")!
        try store.context.save()
        all = try store.fetch(BalanceBaseline.self)
        XCTAssertEqual(all.first?.initialAmount, Decimal(string: "9999.99")!)

        try store.delete(baseline)
        XCTAssertTrue(try store.fetch(BalanceBaseline.self).isEmpty)
    }
}
