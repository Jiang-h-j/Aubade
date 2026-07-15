import XCTest
@testable import Aubade

/// TRD 01 验证点 7：mock 各行为 → 对应错误 / 成功值。附 Keychain set→get→clear 冒烟。
@MainActor
final class MockParserTests: XCTestCase {

    // MARK: - 验证点 7：mock 成功值对齐 demo 定值

    func testSuccessReturnsSampleValues() async throws {
        let parsed = try await MockTransactionParser(behavior: .success).parse(text: "任意", categories: [])
        XCTAssertEqual(parsed.amountText, "256.00")
        XCTAssertEqual(parsed.direction, .expense)
        XCTAssertEqual(parsed.merchant, "京东商城")
        XCTAssertEqual(parsed.cardTail, "1234")
        XCTAssertEqual(parsed.categoryName, "其他")
        XCTAssertEqual(parsed.occurredAt, MockTransactionParser.sampleOccurredAt)
    }

    // MARK: - 验证点 7：screenshotSample 定值对齐 demo（88.5/支出/星巴克/食）

    func testScreenshotSampleReturnsSampleValues() async throws {
        let parsed = try await MockTransactionParser(behavior: .screenshotSample).parse(text: "任意", categories: [])
        XCTAssertEqual(parsed.amountText, "88.50")
        XCTAssertEqual(parsed.direction, .expense)
        XCTAssertEqual(parsed.merchant, "星巴克")
        XCTAssertNil(parsed.cardTail)
        XCTAssertEqual(parsed.categoryName, "食")
        XCTAssertEqual(parsed.occurredAt, MockTransactionParser.sampleOccurredAt)
    }

    // MARK: - 验证点 7：各失败行为抛对应错误

    func testFailureBehaviorsThrowMatchingErrors() async {
        let cases: [(MockTransactionParser.Behavior, RecognitionError)] = [
            (.network, .network),
            (.timeout, .timeout),
            (.invalidResponse, .invalidResponse),
            (.noAmount, .noAmount),
        ]
        for (behavior, expected) in cases {
            do {
                _ = try await MockTransactionParser(behavior: behavior).parse(text: "任意", categories: [])
                XCTFail("behavior \(behavior) 应抛 \(expected)")
            } catch {
                XCTAssertEqual(error as? RecognitionError, expected)
            }
        }
    }

    // MARK: - Keychain 冒烟：set → get → clear

    func testKeychainSetGetClear() throws {
        let store = KeychainStore.shared
        store.clearDeepSeekKey()                       // 起点干净
        XCTAssertFalse(store.isConfigured)
        XCTAssertNil(store.deepSeekKey)

        store.setDeepSeekKey("sk-test-123")
        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(store.deepSeekKey, "sk-test-123")

        // 重复写覆盖（写侧唯一化）。
        store.setDeepSeekKey("sk-test-456")
        XCTAssertEqual(store.deepSeekKey, "sk-test-456")

        store.clearDeepSeekKey()
        XCTAssertFalse(store.isConfigured)
        XCTAssertNil(store.deepSeekKey)
    }
}
