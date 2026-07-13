import XCTest
import SwiftData
@testable import Aubade

/// 切片 02：编辑表单值模型 `TransactionDraft`。
/// 验证金额解析（合法/空/零/负/非数字）、isValid 校验、商户备注归一、edit 模式回填正确性（验收 1/9）。
@MainActor
final class TransactionDraftTests: XCTestCase {

    // 持有容器：ModelContext 不强引用 ModelContainer，链式 mainContext 会致悬垂 context 崩溃（N00 SIGTRAP 坑）。
    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        container = PersistenceController.makeInMemoryContainer()
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    // MARK: - 金额解析与校验

    func testValidAmountParses() {
        var draft = TransactionDraft(direction: .expense, occurredAt: Date())
        draft.amountText = "35.55"
        XCTAssertEqual(draft.parsedAmount, Decimal(string: "35.55"))
        XCTAssertTrue(draft.isValid)
    }

    func testEmptyAmountInvalid() {
        var draft = TransactionDraft(direction: .expense, occurredAt: Date())
        draft.amountText = ""
        XCTAssertNil(draft.parsedAmount)
        XCTAssertFalse(draft.isValid)
    }

    func testWhitespaceOnlyAmountInvalid() {
        var draft = TransactionDraft(direction: .expense, occurredAt: Date())
        draft.amountText = "   "
        XCTAssertNil(draft.parsedAmount)
        XCTAssertFalse(draft.isValid)
    }

    func testZeroAmountInvalid() {
        var draft = TransactionDraft(direction: .expense, occurredAt: Date())
        draft.amountText = "0"
        XCTAssertEqual(draft.parsedAmount, Decimal(0))
        XCTAssertFalse(draft.isValid, "金额为 0 不允许保存")
    }

    func testNegativeAmountInvalid() {
        var draft = TransactionDraft(direction: .expense, occurredAt: Date())
        draft.amountText = "-10"
        XCTAssertEqual(draft.parsedAmount, Decimal(-10))
        XCTAssertFalse(draft.isValid, "负数金额不允许保存（方向由 direction 表达，amount 存正值）")
    }

    func testNonNumericAmountInvalid() {
        var draft = TransactionDraft(direction: .expense, occurredAt: Date())
        draft.amountText = "abc"
        XCTAssertNil(draft.parsedAmount)
        XCTAssertFalse(draft.isValid)
    }

    func testAmountKeepsDecimalPrecision() {
        var draft = TransactionDraft(direction: .expense, occurredAt: Date())
        draft.amountText = "0.1"
        // Decimal 无浮点误差：0.1 精确表示。
        XCTAssertEqual(draft.parsedAmount, Decimal(string: "0.1"))
    }

    // MARK: - 商户 / 备注归一

    func testMerchantAndNoteNormalization() {
        var draft = TransactionDraft(direction: .expense, occurredAt: Date())
        draft.merchant = "  "
        draft.note = " 午餐 "
        XCTAssertNil(draft.normalizedMerchant, "纯空白商户归一为 nil")
        XCTAssertEqual(draft.normalizedNote, "午餐", "备注去除首尾空白")
    }

    func testEmptyMerchantAndNoteAreNil() {
        let draft = TransactionDraft(direction: .expense, occurredAt: Date())
        XCTAssertNil(draft.normalizedMerchant)
        XCTAssertNil(draft.normalizedNote)
    }

    // MARK: - 新建默认

    func testCreateInitDefaults() {
        let now = Date()
        let draft = TransactionDraft(direction: .income, occurredAt: now)
        XCTAssertEqual(draft.amountText, "")
        XCTAssertEqual(draft.direction, .income)
        XCTAssertNil(draft.category)
        XCTAssertEqual(draft.occurredAt, now)
        XCTAssertFalse(draft.isValid, "空表单不可保存")
    }

    // MARK: - edit 模式回填（验收 9）

    func testEditInitBackfillsAllFields() throws {
        let store = LedgerStore(container.mainContext)
        let category = try store.createCategory(name: "食", direction: .expense, sortOrder: 1)
        let occurred = Date(timeIntervalSince1970: 1_700_000_000)
        let tx = try store.createTransaction(
            amount: Decimal(string: "88.80")!, direction: .expense,
            occurredAt: occurred, category: category,
            merchant: "麦当劳", note: "午餐", source: .manual)

        let draft = TransactionDraft(from: tx)
        XCTAssertEqual(draft.parsedAmount, Decimal(string: "88.80"))
        XCTAssertEqual(draft.direction, .expense)
        XCTAssertEqual(draft.category?.name, "食")
        XCTAssertEqual(draft.occurredAt, occurred)
        XCTAssertEqual(draft.merchant, "麦当劳")
        XCTAssertEqual(draft.note, "午餐")
        XCTAssertTrue(draft.isValid)
    }

    func testEditInitWithNilMerchantNoteBackfillsEmpty() throws {
        let store = LedgerStore(container.mainContext)
        let tx = try store.createTransaction(
            amount: Decimal(string: "10")!, direction: .income,
            occurredAt: Date(), source: .manual)

        let draft = TransactionDraft(from: tx)
        XCTAssertEqual(draft.merchant, "", "nil 商户回填为空串")
        XCTAssertEqual(draft.note, "", "nil 备注回填为空串")
        XCTAssertNil(draft.category)
        XCTAssertEqual(draft.direction, .income)
    }

    // MARK: - EditorActions 编辑落库（验收 9 编辑保存闭环）

    func testEditorActionsUpdatePersistsChanges() throws {
        let store = LedgerStore(container.mainContext)
        let tx = try store.createTransaction(
            amount: Decimal(string: "20")!, direction: .expense,
            occurredAt: Date(), source: .manual)
        let originalUpdatedAt = tx.updatedAt

        var draft = TransactionDraft(from: tx)
        draft.amountText = "99.90"
        draft.note = "改后备注"
        let onSave = EditorActions.makeUpdate(store: store, tx: tx)
        try onSave(draft)

        let reloaded = try store.fetch(Transaction.self)
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.amount, Decimal(string: "99.90"))
        XCTAssertEqual(reloaded.first?.note, "改后备注")
        XCTAssertGreaterThanOrEqual(reloaded.first!.updatedAt, originalUpdatedAt, "更新刷新 updatedAt")
    }
}
