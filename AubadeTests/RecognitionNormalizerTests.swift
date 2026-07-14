import XCTest
import SwiftData
@testable import Aubade

/// TRD 01 验证点 1-6 + 8：归一纯函数（金额 / 时间 / 分类兜底）与端到端归一。
/// 分类测试建内存容器 + PresetCategories.seedIfNeeded，并持有 container（悬垂 context 会 SIGTRAP）。
@MainActor
final class RecognitionNormalizerTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        container = PersistenceController.makeInMemoryContainer()
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    /// 库中拉出全部分类（seed 后）。
    private func seededCategories() -> [LedgerCategory] {
        let context = container.mainContext
        PresetCategories.seedIfNeeded(context)
        let descriptor = FetchDescriptor<LedgerCategory>()
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - 验证点 1：金额 → Decimal

    func testAmountParsesToExactDecimal() throws {
        XCTAssertEqual(try RecognitionNormalizer.amount("256.00"), Decimal(string: "256.00"))
        XCTAssertEqual(try RecognitionNormalizer.amount("0.1"), Decimal(string: "0.1"))
        // 0.1 + 0.2 无浮点误差：Decimal 精确。
        let sum = try RecognitionNormalizer.amount("0.1") + RecognitionNormalizer.amount("0.2")
        XCTAssertEqual(sum, Decimal(string: "0.3"))
    }

    func testAmountRejectsInvalidValues() {
        for bad in ["", "  ", "abc", "0", "-5"] {
            XCTAssertThrowsError(try RecognitionNormalizer.amount(bad)) { error in
                XCTAssertEqual(error as? RecognitionError, .noAmount, "输入 \"\(bad)\" 应抛 .noAmount")
            }
        }
    }

    // MARK: - 验证点 2：时间兜底 / 禁未来

    func testOccurredAtFallbackAndClamp() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(RecognitionNormalizer.occurredAt(nil, now: now), now)                       // nil → now
        let past = now.addingTimeInterval(-3600)
        XCTAssertEqual(RecognitionNormalizer.occurredAt(past, now: now), past)                     // 过去保留
        let future = now.addingTimeInterval(3600)
        XCTAssertEqual(RecognitionNormalizer.occurredAt(future, now: now), now)                    // 未来 clamp 到 now
    }

    // MARK: - 验证点 3：分类精确匹配

    func testCategoryExactMatch() {
        let categories = seededCategories()
        let hit = RecognitionNormalizer.category(name: "食", direction: .expense, in: categories)
        XCTAssertEqual(hit?.name, "食")
        XCTAssertEqual(hit?.direction, .expense)
    }

    // MARK: - 验证点 4：分类兜底（不匹配）

    func testCategoryFallbackWhenUnmatched() {
        let categories = seededCategories()
        let expenseFallback = RecognitionNormalizer.category(name: "停车费", direction: .expense, in: categories)
        XCTAssertEqual(expenseFallback?.name, "其他")

        let incomeFallback = RecognitionNormalizer.category(name: "停车费", direction: .income, in: categories)
        XCTAssertEqual(incomeFallback?.name, "其他收入")
    }

    // MARK: - 验证点 5：方向矛盾以方向为准

    func testCategoryDirectionMismatchUsesFallback() {
        let categories = seededCategories()
        // "食"是支出分类；以收入方向查 → 不取"食"，兜底到"其他收入"。
        let result = RecognitionNormalizer.category(name: "食", direction: .income, in: categories)
        XCTAssertEqual(result?.name, "其他收入")
        XCTAssertEqual(result?.direction, .income)
    }

    // MARK: - 验证点 6：兜底分类缺失 → nil（落未分类，不崩）

    func testCategoryReturnsNilWhenFallbackMissing() {
        let context = container.mainContext
        // 只放一个非兜底的支出分类，库中无"其他"。
        context.insert(LedgerCategory(name: "食", direction: .expense, isPreset: true))
        let categories = (try? context.fetch(FetchDescriptor<LedgerCategory>())) ?? []
        let result = RecognitionNormalizer.category(name: "停车费", direction: .expense, in: categories)
        XCTAssertNil(result)
    }

    // MARK: - 验证点 8：端到端（mock.success → 归一）

    func testEndToEndNormalizationFromMockSuccess() async throws {
        let categories = seededCategories()
        let parsed = try await MockTransactionParser(behavior: .success).parse(text: "任意", categories: categories)

        let now = Date(timeIntervalSince1970: 2_000_000_000)   // 远晚于样例时间，不触发 clamp
        let amount = try RecognitionNormalizer.amount(parsed.amountText)
        let occurredAt = RecognitionNormalizer.occurredAt(parsed.occurredAt, now: now)
        let category = RecognitionNormalizer.category(name: parsed.categoryName,
                                                      direction: parsed.direction, in: categories)

        XCTAssertEqual(amount, Decimal(string: "256.00"))
        XCTAssertEqual(parsed.direction, .expense)
        XCTAssertEqual(occurredAt, MockTransactionParser.sampleOccurredAt)   // 样例时间不越未来
        XCTAssertLessThanOrEqual(occurredAt, now)
        XCTAssertEqual(category?.name, "其他")                                // 命中预置"其他"
        XCTAssertEqual(category?.direction, .expense)
    }
}
