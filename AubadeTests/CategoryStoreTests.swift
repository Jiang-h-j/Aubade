import XCTest
import SwiftData
@testable import Aubade

/// 验收 4/7/8/9/10：分类 Store 的改/删能力（预置保护、同方向重名拒绝、删已引用先按方向转兜底再删、引用计数）。
/// 纯逻辑，单测焊死；不涉及 UI（UI 在切片 03 消费）。
@MainActor
final class CategoryStoreTests: XCTestCase {

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

    // MARK: - updateCategory

    /// 验证点 1：改自定义分类的名称/图标/色，字段更新、save 成功。
    func testUpdateCustomCategory() throws {
        let store = LedgerStore(container.mainContext)
        let category = try store.createCategory(name: "宠物", direction: .expense,
                                                icon: "🐾", color: "#111111")

        try store.updateCategory(category, name: "萌宠", icon: "🐶", color: "#222222")

        XCTAssertEqual(category.name, "萌宠")
        XCTAssertEqual(category.icon, "🐶")
        XCTAssertEqual(category.color, "#222222")
    }

    /// 验证点 2：对预置分类调用 → 抛 presetImmutable，字段不变。
    func testUpdatePresetCategoryRejected() throws {
        let context = container.mainContext
        PresetCategories.seedIfNeeded(context)
        let store = LedgerStore(context)
        let preset = try XCTUnwrap(try store.presetCategories().first { $0.name == "食" })

        XCTAssertThrowsError(try store.updateCategory(preset, name: "美食", icon: nil, color: nil)) { error in
            XCTAssertEqual(error as? CategoryError, .presetImmutable)
        }
        XCTAssertEqual(preset.name, "食")
    }

    /// 验证点 3：同方向已有"宠物"，另一分类改名"宠物" → 抛 duplicateName，不改。
    func testUpdateDuplicateNameSameDirectionRejected() throws {
        let store = LedgerStore(container.mainContext)
        _ = try store.createCategory(name: "宠物", direction: .expense)
        let other = try store.createCategory(name: "零食", direction: .expense)

        XCTAssertThrowsError(try store.updateCategory(other, name: "宠物", icon: nil, color: nil)) { error in
            XCTAssertEqual(error as? CategoryError, .duplicateName)
        }
        XCTAssertEqual(other.name, "零食")
    }

    /// 验证点 4：跨方向同名允许（支出有"其他"、收入建/改"其他"不冲突，判重限定同 direction）。
    func testUpdateSameNameDifferentDirectionAllowed() throws {
        let context = container.mainContext
        PresetCategories.seedIfNeeded(context)   // 支出有预置"其他"
        let store = LedgerStore(context)
        let incomeCategory = try store.createCategory(name: "零花", direction: .income)

        XCTAssertNoThrow(try store.updateCategory(incomeCategory, name: "其他", icon: nil, color: nil))
        XCTAssertEqual(incomeCategory.name, "其他")
    }

    // MARK: - deleteCategory

    /// 验证点 5：删预置分类 → 抛 presetUndeletable，分类仍在。
    func testDeletePresetCategoryRejected() throws {
        let context = container.mainContext
        PresetCategories.seedIfNeeded(context)
        let store = LedgerStore(context)
        let preset = try XCTUnwrap(try store.presetCategories().first { $0.name == "食" })

        XCTAssertThrowsError(try store.deleteCategory(preset)) { error in
            XCTAssertEqual(error as? CategoryError, .presetUndeletable)
        }
        XCTAssertNotNil(try store.fetch(LedgerCategory.self).first { $0.name == "食" })
    }

    /// 验证点 6：删无账单引用的自定义分类 → 分类消失，无账单受影响。
    func testDeleteUnreferencedCustomCategory() throws {
        let store = LedgerStore(container.mainContext)
        let category = try store.createCategory(name: "宠物", direction: .expense)

        try store.deleteCategory(category)

        XCTAssertTrue(try store.fetch(LedgerCategory.self).allSatisfy { $0.name != "宠物" })
    }

    /// 验证点 7：自定义支出分类记 2 笔 → 删 → 分类消失，那 2 笔 category?.name == "其他"（非 nil）。
    func testDeleteReferencedExpenseCategoryTransfersToOther() throws {
        let context = container.mainContext
        PresetCategories.seedIfNeeded(context)   // 建预置"其他"
        let store = LedgerStore(context)
        let pet = try store.createCategory(name: "宠物", direction: .expense)
        let id1 = try store.createTransaction(amount: Decimal(string: "20.00")!, direction: .expense,
                                              occurredAt: Date(), category: pet, source: .manual).id
        let id2 = try store.createTransaction(amount: Decimal(string: "30.00")!, direction: .expense,
                                              occurredAt: Date(), category: pet, source: .manual).id

        try store.deleteCategory(pet)

        XCTAssertTrue(try store.fetch(LedgerCategory.self).allSatisfy { $0.name != "宠物" })
        for id in [id1, id2] {
            let tx = try XCTUnwrap(try store.fetch(Transaction.self, predicate: #Predicate { $0.id == id }).first)
            XCTAssertEqual(tx.category?.name, "其他")
        }
    }

    /// 验证点 8：自定义收入分类记 1 笔 → 删 → 该笔 category?.name == "其他收入"（方向兜底，非"其他"、非 nil）。
    /// 独立验证方向兜底，是对原型统一转"其他"的纠偏。
    func testDeleteReferencedIncomeCategoryTransfersToOtherIncome() throws {
        let context = container.mainContext
        PresetCategories.seedIfNeeded(context)   // 建预置"其他收入"
        let store = LedgerStore(context)
        let bonus = try store.createCategory(name: "外快", direction: .income)
        let id = try store.createTransaction(amount: Decimal(string: "500.00")!, direction: .income,
                                             occurredAt: Date(), category: bonus, source: .manual).id

        try store.deleteCategory(bonus)

        let tx = try XCTUnwrap(try store.fetch(Transaction.self, predicate: #Predicate { $0.id == id }).first)
        XCTAssertEqual(tx.category?.name, "其他收入")
    }

    // MARK: - 引用计数

    /// 验证点 9：category.transactions.count 在记 N 笔后等于 N。
    func testReferenceCountEqualsTransactionCount() throws {
        let store = LedgerStore(container.mainContext)
        let category = try store.createCategory(name: "宠物", direction: .expense)
        for _ in 0..<3 {
            _ = try store.createTransaction(amount: Decimal(string: "10.00")!, direction: .expense,
                                            occurredAt: Date(), category: category, source: .manual)
        }
        XCTAssertEqual(category.transactions.count, 3)
    }

    // MARK: - 自定义分类进入识别候选

    /// 验证点 11（PRD 需求 14）：建自定义支出分类后，RecognitionNormalizer 能按 name+direction 命中它，
    /// 说明新增分类天然进入识别候选，不需改识别逻辑。
    func testCustomCategoryMatchedByRecognition() throws {
        let store = LedgerStore(container.mainContext)
        let pet = try store.createCategory(name: "宠物", direction: .expense)
        let categories = try store.fetch(LedgerCategory.self)

        let hit = RecognitionNormalizer.category(name: "宠物", direction: .expense, in: categories)
        XCTAssertEqual(hit?.id, pet.id)
    }
}
