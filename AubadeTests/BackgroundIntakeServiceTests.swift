import XCTest
import SwiftData
@testable import Aubade

/// TRD 01 §5：BackgroundIntakeService 后台各分支落库 + "发哪类通知" 断言。
/// 脱真图片 / 真网络 / 真系统通知；内存容器并持有 container（悬垂 context 会 SIGTRAP，见 N00 陷阱）。
/// Key 造态用真实 KeychainStore.shared（MockParserTests 已证测试宿主可读写 Keychain），tearDown 清 Key 防污染。
@MainActor
final class BackgroundIntakeServiceTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        container = PersistenceController.makeInMemoryContainer()
        KeychainStore.shared.clearDeepSeekKey()   // 起点无 Key，各用例按需 set
    }

    override func tearDown() {
        KeychainStore.shared.clearDeepSeekKey()    // 清 Key，避免污染后续用例（如真实 DeepSeek 冒烟）
        container = nil
        super.tearDown()
    }

    // MARK: - Spy

    /// 记录收到的通知意图（脱真系统通知）。标 @MainActor 与 @MainActor 协议 NotificationSending 隔离一致。
    @MainActor
    final class SpyNotifier: NotificationSending {
        private(set) var received: [IntakeNotification] = []
        func send(_ notification: IntakeNotification) async { received.append(notification) }
    }

    /// 记录 save 是否被调 + 收到的数据；返回固定 imageRef 供断言透传。标 @MainActor 与 @MainActor 协议 FailedImageStoring 隔离一致。
    @MainActor
    final class SpyImageStore: FailedImageStoring {
        private(set) var saveCallCount = 0
        private(set) var lastData: Data?
        let stubRef: String?
        init(stubRef: String? = "spy-ref") { self.stubRef = stubRef }
        func save(_ imageData: Data) -> String? {
            saveCallCount += 1
            lastData = imageData
            return stubRef
        }
    }

    // MARK: - Fixtures

    private func seededCategories() -> [LedgerCategory] {
        let context = container.mainContext
        PresetCategories.seedIfNeeded(context)
        return (try? context.fetch(FetchDescriptor<LedgerCategory>())) ?? []
    }

    private func allTransactions() throws -> [Transaction] {
        try container.mainContext.fetch(FetchDescriptor<Transaction>())
    }

    private let fixedNow = Date(timeIntervalSince1970: 2_000_000_000)   // 远晚于样例时间，不触发 clamp
    private let sampleImageData = Data([0x01, 0x02, 0x03])              // 假图片数据（OCR mock 不解码它）

    /// 组装被测核心单元。recognizer/parser 行为按用例注入；notifier/imageStore 为 spy。
    private func makeService(recognizer: any TextRecognizing,
                             parser: TransactionParsing,
                             notifier: SpyNotifier,
                             imageStore: SpyImageStore) -> BackgroundIntakeService {
        BackgroundIntakeService(
            recognizer: recognizer,
            parser: parser,
            store: LedgerStore(container.mainContext),
            categories: seededCategories(),
            notifier: notifier,
            now: { self.fixedNow },
            imageStore: imageStore)
    }

    private func successRecognizer() -> MockTextRecognizer {
        let r = MockTextRecognizer(); r.behavior = .success; return r
    }

    // MARK: - 成功入账：落 .screenshotShortcut + 字段正确 + 成功通知

    func testSuccessSavesScreenshotShortcutAndSendsSuccessNotification() async throws {
        KeychainStore.shared.setDeepSeekKey("sk-test")   // 有 Key
        let notifier = SpyNotifier()
        let imageStore = SpyImageStore()
        let service = makeService(recognizer: successRecognizer(),
                                  parser: MockTransactionParser(behavior: .screenshotSample),
                                  notifier: notifier, imageStore: imageStore)

        await service.intake(imageData: sampleImageData)

        // 落库 1 笔，来源截图快捷指令，字段对齐 demo 定值
        let txs = try allTransactions()
        XCTAssertEqual(txs.count, 1)
        let tx = try XCTUnwrap(txs.first)
        XCTAssertEqual(tx.source, .screenshotShortcut)
        XCTAssertEqual(tx.amount, Decimal(string: "88.50"))
        XCTAssertEqual(tx.direction, .expense)
        XCTAssertEqual(tx.category?.name, "食")
        XCTAssertEqual(tx.merchant, "星巴克")
        XCTAssertNil(tx.imageRef)                                        // 成功不留存原图（恒 nil）
        // rawText 完整相等：带 [快捷指令] 前缀 + 纯 OCR 文本（与失败分支对称锁死落库原文）
        XCTAssertEqual(tx.rawText, "[快捷指令]\n" + MockTextRecognizer.sampleRecognizedText)
        XCTAssertNotEqual(tx.rawText, MockTextRecognizer.sampleRecognizedText)   // parse 输入与落库原文确已分离
        // 成功不留存原图：imageStore.save 未被调
        XCTAssertEqual(imageStore.saveCallCount, 0)
        // spy 收到 .success，字段正确
        XCTAssertEqual(notifier.received.count, 1)
        guard case let .success(transactionID, amountText, categoryName, merchant) = try XCTUnwrap(notifier.received.first) else {
            return XCTFail("应发 .success 通知")
        }
        XCTAssertEqual(transactionID, tx.id)
        XCTAssertEqual(amountText, "88.50")
        XCTAssertEqual(categoryName, "食")
        XCTAssertEqual(merchant, "星巴克")
    }

    // MARK: - 无 Key：不落库、发 .missingKey、不调 parser

    func testMissingKeyStopsBeforeParseAndSendsMissingKey() async throws {
        // setUp 已 clearDeepSeekKey，此处即无 Key 态
        let notifier = SpyNotifier()
        let imageStore = SpyImageStore()
        // 注入会抛错的 parser，用未落库 + 未收到失败通知反证 parser 未被调
        let service = makeService(recognizer: successRecognizer(),
                                  parser: MockTransactionParser(behavior: .network),
                                  notifier: notifier, imageStore: imageStore)

        await service.intake(imageData: sampleImageData)

        XCTAssertEqual(try allTransactions().count, 0)                   // 未落库
        XCTAssertEqual(imageStore.saveCallCount, 0)                      // 无 Key 不属"失败留原图"分支
        XCTAssertEqual(notifier.received, [.missingKey])                 // 仅 .missingKey（未走 parser 失败分支）
    }

    // MARK: - OCR 空：不落库、发 .failure、留原图、rawText=nil

    func testOCREmptySavesNothingAndSendsFailureWithImageAndNilRawText() async throws {
        KeychainStore.shared.setDeepSeekKey("sk-test")
        let notifier = SpyNotifier()
        let imageStore = SpyImageStore()
        let recognizer = MockTextRecognizer(); recognizer.behavior = .empty
        let service = makeService(recognizer: recognizer,
                                  parser: MockTransactionParser(behavior: .screenshotSample),
                                  notifier: notifier, imageStore: imageStore)

        await service.intake(imageData: sampleImageData)

        XCTAssertEqual(try allTransactions().count, 0)                   // 未落库
        XCTAssertEqual(imageStore.saveCallCount, 1)                      // 保留原图
        XCTAssertEqual(imageStore.lastData, sampleImageData)
        // OCR 本身失败：无 OCR 文本 → rawText=nil，imageRef 透传 spy 值
        XCTAssertEqual(notifier.received, [.failure(imageRef: "spy-ref", rawText: nil)])
    }

    // MARK: - OCR 失败：同 .failure（.failed 分支）

    func testOCRFailedSendsFailureWithNilRawText() async throws {
        KeychainStore.shared.setDeepSeekKey("sk-test")
        let notifier = SpyNotifier()
        let imageStore = SpyImageStore()
        let recognizer = MockTextRecognizer(); recognizer.behavior = .failed
        let service = makeService(recognizer: recognizer,
                                  parser: MockTransactionParser(behavior: .screenshotSample),
                                  notifier: notifier, imageStore: imageStore)

        await service.intake(imageData: sampleImageData)

        XCTAssertEqual(try allTransactions().count, 0)
        XCTAssertEqual(imageStore.saveCallCount, 1)
        XCTAssertEqual(notifier.received, [.failure(imageRef: "spy-ref", rawText: nil)])
    }

    // MARK: - 解析失败三态：超时 / 无网 / 无金额 → 未落库、发 .failure、rawText 带前缀非空

    func testParseTimeoutSavesNothingAndSendsFailureWithPrefixedRawText() async throws {
        try await assertParseFailureBranch(.timeout)
    }

    func testParseNetworkSavesNothingAndSendsFailure() async throws {
        try await assertParseFailureBranch(.network)
    }

    func testParseNoAmountSavesNothingAndSendsFailure() async throws {
        try await assertParseFailureBranch(.noAmount)
    }

    /// 解析层失败共用断言：OCR 成功但 parse 抛错 → 守不变量不落库、发 .failure（带前缀原文 + 留原图）。
    private func assertParseFailureBranch(_ behavior: MockTransactionParser.Behavior) async throws {
        KeychainStore.shared.setDeepSeekKey("sk-test")
        let notifier = SpyNotifier()
        let imageStore = SpyImageStore()
        let service = makeService(recognizer: successRecognizer(),
                                  parser: MockTransactionParser(behavior: behavior),
                                  notifier: notifier, imageStore: imageStore)

        await service.intake(imageData: sampleImageData)

        XCTAssertEqual(try allTransactions().count, 0, "\(behavior) 应守不变量：未落库")
        XCTAssertEqual(imageStore.saveCallCount, 1, "\(behavior) 应保留原图")
        XCTAssertEqual(notifier.received.count, 1)
        guard case let .failure(imageRef, rawText) = try XCTUnwrap(notifier.received.first) else {
            return XCTFail("\(behavior) 应发 .failure 通知")
        }
        XCTAssertEqual(imageRef, "spy-ref")
        // OCR 成功 → 失败通知带前缀原文供补录带入
        XCTAssertEqual(rawText, "[快捷指令]\n" + MockTextRecognizer.sampleRecognizedText)
    }

    // MARK: - 不回归：既有截图相册路径 source=.screenshotAlbum 落库不变（与 RecognitionEntryScreenshotTests 一致）

    func testExistingScreenshotAlbumPathUnaffected() async throws {
        let categories = seededCategories()
        let store = LedgerStore(container.mainContext)
        let ocrText = MockTextRecognizer.sampleRecognizedText
        try await RecognitionEntry.recognizeAndSave(
            text: ocrText, categories: categories,
            parser: MockTransactionParser(behavior: .screenshotSample), store: store, now: fixedNow,
            source: .screenshotAlbum, rawText: "[截图识别]\n" + ocrText)

        let tx = try XCTUnwrap(try allTransactions().first)
        XCTAssertEqual(tx.source, .screenshotAlbum)   // 新增 .screenshotShortcut 未污染相册路径
        XCTAssertEqual(tx.amount, Decimal(string: "88.50"))
    }
}
