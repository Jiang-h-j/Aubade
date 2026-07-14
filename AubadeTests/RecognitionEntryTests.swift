import XCTest
import SwiftData
@testable import Aubade

/// TRD 02 验证点 1-4：mock 注入下"识别 → 归一 → 落库"编排（RecognitionEntry.recognizeAndSave）。
/// 脱 View、脱网、脱 Keychain；内存容器并持有 container（悬垂 context 会 SIGTRAP）。
@MainActor
final class RecognitionEntryTests: XCTestCase {

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

    // MARK: - 验证点 1：成功入账，字段精确落库

    func testSuccessRecognitionSavesTransactionWithAllFields() async throws {
        let categories = seededCategories()
        let store = LedgerStore(container.mainContext)
        let now = Date(timeIntervalSince1970: 2_000_000_000)   // 远晚于样例时间，不触发 clamp
        let input = "工商银行 您尾号1234的卡消费256.00元"

        try await RecognitionEntry.recognizeAndSave(
            text: input, categories: categories,
            parser: MockTransactionParser(behavior: .success), store: store, now: now)

        let txs = try allTransactions()
        XCTAssertEqual(txs.count, 1)
        let tx = try XCTUnwrap(txs.first)
        XCTAssertEqual(tx.amount, Decimal(string: "256.00"))   // Decimal 精确，无浮点误差
        XCTAssertEqual(tx.direction, .expense)
        XCTAssertEqual(tx.merchant, "京东商城")
        XCTAssertEqual(tx.cardTail, "1234")
        XCTAssertEqual(tx.source, .text)
        XCTAssertEqual(tx.rawText, input)                      // 落用户输入原文，非 mock 内部 raw
        XCTAssertEqual(tx.category?.name, "其他")               // 命中预置"其他"
        XCTAssertEqual(tx.category?.direction, .expense)
    }

    // MARK: - 验证点 2：无金额不入账（无脏账）

    func testNoAmountDoesNotSave() async throws {
        let categories = seededCategories()
        let store = LedgerStore(container.mainContext)

        await assertThrowsRecognitionError(.noAmount) {
            try await RecognitionEntry.recognizeAndSave(
                text: "没有金额的文本", categories: categories,
                parser: MockTransactionParser(behavior: .noAmount), store: store,
                now: Date())
        }
        XCTAssertEqual(try allTransactions().count, 0)   // 库中 0 笔
    }

    // MARK: - 验证点 3：网络 / 超时 / 非法响应不入账

    func testFailureBehaviorsDoNotSave() async throws {
        let cases: [(MockTransactionParser.Behavior, RecognitionError)] = [
            (.network, .network),
            (.timeout, .timeout),
            (.invalidResponse, .invalidResponse),
        ]
        for (behavior, expected) in cases {
            let categories = seededCategories()
            let store = LedgerStore(container.mainContext)
            await assertThrowsRecognitionError(expected) {
                try await RecognitionEntry.recognizeAndSave(
                    text: "任意", categories: categories,
                    parser: MockTransactionParser(behavior: behavior), store: store,
                    now: Date())
            }
            XCTAssertEqual(try allTransactions().count, 0, "\(behavior) 不应落库")
        }
    }

    // MARK: - 验证点 4：时间不越未来

    func testOccurredAtNotInFuture() async throws {
        let categories = seededCategories()
        let store = LedgerStore(container.mainContext)
        // now 早于 mock 样例时间(2026-07-10) → occurredAt 应被 clamp 到 now。
        let now = Date(timeIntervalSince1970: 1_000_000_000)   // 2001-09，远早于样例

        try await RecognitionEntry.recognizeAndSave(
            text: "任意", categories: categories,
            parser: MockTransactionParser(behavior: .success), store: store, now: now)

        let tx = try XCTUnwrap(try allTransactions().first)
        XCTAssertLessThanOrEqual(tx.occurredAt, now)
        XCTAssertEqual(tx.occurredAt, now)                     // 未来时间被 clamp 到 now
    }

    // MARK: - Helper

    private func assertThrowsRecognitionError(
        _ expected: RecognitionError,
        _ body: () async throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("应抛 \(expected)，但未抛错", file: file, line: line)
        } catch let error as RecognitionError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("应抛 RecognitionError.\(expected)，实际抛 \(error)", file: file, line: line)
        }
    }
}
