import XCTest
import SwiftData
@testable import Aubade

/// TRD 01 验证点：recognizeAndSave 截图路径（source=.screenshotAlbum / rawText 带 [截图识别] 前缀）。
/// 脱 View、脱网、脱真图片；内存容器并持有 container（悬垂 context 会 SIGTRAP，见 N00 陷阱）。
@MainActor
final class RecognitionEntryScreenshotTests: XCTestCase {

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

    // MARK: - 截图落库：source=.screenshotAlbum、金额 88.50、分类"食"、商户星巴克、rawText 带前缀

    func testScreenshotRecognitionSavesWithScreenshotSourceAndPrefixedRawText() async throws {
        let categories = seededCategories()
        let store = LedgerStore(container.mainContext)
        let now = Date(timeIntervalSince1970: 2_000_000_000)   // 远晚于样例时间，不触发 clamp
        let ocrText = MockTextRecognizer.sampleRecognizedText  // parse 输入 = 纯 OCR 文本
        let rawWithPrefix = "[截图识别]\n" + ocrText             // 落库原文 = 带前缀

        try await RecognitionEntry.recognizeAndSave(
            text: ocrText, categories: categories,
            parser: MockTransactionParser(behavior: .screenshotSample), store: store, now: now,
            source: .screenshotAlbum, rawText: rawWithPrefix)

        let txs = try allTransactions()
        XCTAssertEqual(txs.count, 1)
        let tx = try XCTUnwrap(txs.first)
        XCTAssertEqual(tx.source, .screenshotAlbum)             // 来源落截图相册
        XCTAssertEqual(tx.amount, Decimal(string: "88.50"))     // Decimal 精确，无浮点误差
        XCTAssertEqual(tx.direction, .expense)
        XCTAssertEqual(tx.category?.name, "食")                  // 命中预置支出"食"
        XCTAssertEqual(tx.category?.direction, .expense)
        XCTAssertEqual(tx.merchant, "星巴克")
        XCTAssertEqual(tx.rawText, rawWithPrefix)               // 落库原文保留前缀
        XCTAssertTrue(tx.rawText?.hasPrefix("[截图识别]") ?? false)
        XCTAssertNotEqual(tx.rawText, ocrText)                  // parse 输入与落库原文确已分离
        XCTAssertNil(tx.cardTail)
        XCTAssertNil(tx.imageRef)                               // 本节点不留存原图（恒 nil）
    }

    // MARK: - N04 语音默认不回归：传 .voice 仍落语音（与既有 RecognitionEntryVoiceTests 一致，复核不改）

    func testVoicePathStillWorksAlongsideScreenshot() async throws {
        let categories = seededCategories()
        let store = LedgerStore(container.mainContext)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let spoken = "打车花了 20 块"
        let rawWithPrefix = "[语音转文字]\n\"\(spoken)\""

        try await RecognitionEntry.recognizeAndSave(
            text: spoken, categories: categories,
            parser: MockTransactionParser(behavior: .voiceSample), store: store, now: now,
            source: .voice, rawText: rawWithPrefix)

        let tx = try XCTUnwrap(try allTransactions().first)
        XCTAssertEqual(tx.source, .voice)                       // 截图新增未污染语音路径
        XCTAssertEqual(tx.amount, Decimal(20))
        XCTAssertEqual(tx.category?.name, "行")
    }
}
