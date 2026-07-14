import XCTest
import SwiftData
@testable import Aubade

/// TRD 01 验证点：recognizeAndSave 语音路径（source=.voice / rawText 前缀）+ 向后兼容默认 .text。
/// 脱 View、脱网、脱 Keychain；内存容器并持有 container（悬垂 context 会 SIGTRAP，见 N00 陷阱）。
@MainActor
final class RecognitionEntryVoiceTests: XCTestCase {

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

    // MARK: - 语音落库：source=.voice、金额 20、分类"行"、rawText 带前缀

    func testVoiceRecognitionSavesWithVoiceSourceAndPrefixedRawText() async throws {
        let categories = seededCategories()
        let store = LedgerStore(container.mainContext)
        let now = Date(timeIntervalSince1970: 2_000_000_000)   // 远晚于样例时间，不触发 clamp
        let spoken = "打车花了 20 块"                             // parse 输入 = 纯口语
        let rawWithPrefix = "[语音转文字]\n\"\(spoken)\""          // 落库原文 = 带前缀

        try await RecognitionEntry.recognizeAndSave(
            text: spoken, categories: categories,
            parser: MockTransactionParser(behavior: .voiceSample), store: store, now: now,
            source: .voice, rawText: rawWithPrefix)

        let txs = try allTransactions()
        XCTAssertEqual(txs.count, 1)
        let tx = try XCTUnwrap(txs.first)
        XCTAssertEqual(tx.source, .voice)                       // 来源落语音
        XCTAssertEqual(tx.amount, Decimal(20))                  // Decimal 精确，无浮点误差
        XCTAssertEqual(tx.direction, .expense)
        XCTAssertEqual(tx.category?.name, "行")                  // 命中预置支出"行"
        XCTAssertEqual(tx.category?.direction, .expense)
        XCTAssertEqual(tx.rawText, rawWithPrefix)               // 落库原文保留前缀（非纯口语）
        XCTAssertNotEqual(tx.rawText, spoken)                   // parse 输入与落库原文确已分离
        XCTAssertNil(tx.merchant)
        XCTAssertNil(tx.cardTail)
        XCTAssertNil(tx.imageRef)                               // 语音不涉图片
    }

    // MARK: - 向后兼容：不传 source/rawText → .text + rawText=输入 text（N03 行为不回归）

    func testBackwardCompatibleDefaultsToTextSource() async throws {
        let categories = seededCategories()
        let store = LedgerStore(container.mainContext)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let input = "工商银行 您尾号1234的卡消费256.00元"

        // 不传 source/rawText，与 N03 现有调用逐字节等价。
        try await RecognitionEntry.recognizeAndSave(
            text: input, categories: categories,
            parser: MockTransactionParser(behavior: .success), store: store, now: now)

        let tx = try XCTUnwrap(try allTransactions().first)
        XCTAssertEqual(tx.source, .text)                        // 默认来源 .text
        XCTAssertEqual(tx.rawText, input)                       // 默认 rawText = 输入 text
        XCTAssertEqual(tx.amount, Decimal(string: "256.00"))
        XCTAssertEqual(tx.category?.name, "其他")
    }

    // MARK: - rawText 显式为 nil 时回落 text（语义等价 N03）

    func testNilRawTextFallsBackToText() async throws {
        let categories = seededCategories()
        let store = LedgerStore(container.mainContext)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let input = "打车花了 20 块"

        // 传 source=.voice 但 rawText=nil：落库原文回落 text（验证 rawText ?? text 分支）。
        try await RecognitionEntry.recognizeAndSave(
            text: input, categories: categories,
            parser: MockTransactionParser(behavior: .voiceSample), store: store, now: now,
            source: .voice, rawText: nil)

        let tx = try XCTUnwrap(try allTransactions().first)
        XCTAssertEqual(tx.source, .voice)
        XCTAssertEqual(tx.rawText, input)                       // nil → 落 text
        XCTAssertEqual(tx.amount, Decimal(20))                  // 顺带守住 voiceSample 金额落库
        XCTAssertEqual(tx.category?.name, "行")
    }
}
