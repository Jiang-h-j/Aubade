import XCTest
import SwiftData
@testable import Aubade

/// 验收 5：账单↔分类关系双向可达；删分类后账单 category 置空（.nullify）。
@MainActor
final class RelationshipTests: XCTestCase {

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

    func testBidirectionalRelationship() throws {
        let store = LedgerStore(container.mainContext)

        let category = try store.createCategory(name: "餐饮", direction: .expense)
        let tx = try store.createTransaction(
            amount: Decimal(string: "20.00")!, direction: .expense,
            occurredAt: Date(), category: category, source: .manual)

        // 经账单读到分类名。
        XCTAssertEqual(tx.category?.name, "餐饮")
        // 经分类反查到账单。
        XCTAssertTrue(category.transactions.contains { $0.id == tx.id })
    }

    func testDeleteCategoryNullifiesTransaction() throws {
        let store = LedgerStore(container.mainContext)

        let category = try store.createCategory(name: "餐饮", direction: .expense)
        let txID = try store.createTransaction(
            amount: Decimal(string: "20.00")!, direction: .expense,
            occurredAt: Date(), category: category, source: .manual).id

        // 删分类并 save 后，重新 fetch 账单，观察 category 被 nullify（账单本体仍在）。
        try store.delete(category)

        let transactions = try store.fetch(Transaction.self,
                                           predicate: #Predicate { $0.id == txID })
        XCTAssertEqual(transactions.count, 1)
        XCTAssertNil(transactions.first?.category)
    }
}
