import XCTest
import SwiftData
@testable import Aubade

/// TRD 03 验证点 1-3：结果卡片「完成」回写 / 「删除这笔」撤销入账 / 失败转手动带原文预填。
/// 脱 View 测可测核心（EditorActions.makeUpdate/makeDelete、TransactionEditor.makeInitialDraft）；
/// 内存容器并持有 container（悬垂 context 会 SIGTRAP，见 memory）。
@MainActor
final class ResultCardActionsTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        container = PersistenceController.makeInMemoryContainer()
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func seededCategories() -> [LedgerCategory] {
        let context = container.mainContext
        PresetCategories.seedIfNeeded(context)
        return (try? context.fetch(FetchDescriptor<LedgerCategory>())) ?? []
    }

    private func allTransactions() throws -> [Transaction] {
        try container.mainContext.fetch(FetchDescriptor<Transaction>())
    }

    /// 入账一笔 source=.text 的账单（模拟识别成功入账，供结果卡片编辑/删除）。
    private func insertRecognizedTx(store: LedgerStore, category: LedgerCategory?) throws -> Transaction {
        try store.createTransaction(
            amount: Decimal(string: "256.00")!,
            direction: .expense,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            category: category,
            merchant: "京东商城",
            cardTail: "1234",
            source: .text,
            rawText: "工商银行 您尾号1234的卡消费256.00元")
    }

    // MARK: - 验证点 1：完成回写（改金额/分类落库，source/rawText/cardTail 不变）

    func testCompleteEditWritesBackAndKeepsSourceRawText() throws {
        let categories = seededCategories()
        let store = LedgerStore(container.mainContext)
        let expenseCats = categories.filter { $0.direction == .expense }
        let originalCat = try XCTUnwrap(expenseCats.first)
        let newCat = try XCTUnwrap(expenseCats.first { $0.id != originalCat.id })

        let tx = try insertRecognizedTx(store: store, category: originalCat)

        // 结果卡片改了金额 + 分类后点「完成」：从 tx 回填再改字段，走 makeUpdate。
        var draft = TransactionDraft(from: tx)
        draft.amountText = "300.00"
        draft.category = newCat
        try EditorActions.makeUpdate(store: store, tx: tx)(draft)

        XCTAssertEqual(tx.amount, Decimal(string: "300.00"))   // 金额已回写
        XCTAssertEqual(tx.category?.id, newCat.id)             // 分类已回写
        // makeUpdate 不碰 source/rawText/cardTail：结果卡片编辑不篡改识别来源与原文。
        XCTAssertEqual(tx.source, .text)
        XCTAssertEqual(tx.rawText, "工商银行 您尾号1234的卡消费256.00元")
        XCTAssertEqual(tx.cardTail, "1234")
    }

    // MARK: - 验证点 2：删除撤销入账（库中清空）

    func testDeleteUndoesRecognizedTransaction() throws {
        let categories = seededCategories()
        let store = LedgerStore(container.mainContext)
        let tx = try insertRecognizedTx(store: store, category: categories.first)
        XCTAssertEqual(try allTransactions().count, 1)

        // 结果卡片「删除这笔」二次确认后走 makeDelete。
        EditorActions.makeDelete(store: store, tx: tx)()

        XCTAssertTrue(try allTransactions().isEmpty)           // 撤销后库中 0 笔
    }

    // MARK: - 验证点 3：转手动预填原文（initialNote 落进 create 初始草稿；不传则空）

    func testCreateDraftPrefillsInitialNote() {
        let prefilled = TransactionEditor.makeInitialDraft(
            mode: .create(direction: .expense),
            initialNote: "工商银行 您尾号1234的卡消费256.00元")
        XCTAssertEqual(prefilled.note, "工商银行 您尾号1234的卡消费256.00元")

        // 不传 initialNote（N01 现有手动入口）：note 保持空，零影响。
        let plain = TransactionEditor.makeInitialDraft(
            mode: .create(direction: .expense), initialNote: nil)
        XCTAssertEqual(plain.note, "")
    }

    /// edit 模式忽略 initialNote：从 tx 回填 note（防御 initialNote 误污染编辑回填）。
    func testEditDraftIgnoresInitialNote() throws {
        let store = LedgerStore(container.mainContext)
        let tx = try insertRecognizedTx(store: store, category: nil)
        tx.note = "原备注"

        let draft = TransactionEditor.makeInitialDraft(
            mode: .edit(tx), initialNote: "不该出现的预填")
        XCTAssertEqual(draft.note, "原备注")                    // edit 从 tx 回填，不受 initialNote 影响
    }
}
