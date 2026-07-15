import XCTest
@testable import Aubade

/// TRD 01 验证点：MockTextRecognizer 三态可区分（对齐 PRD 验收 9 provider 分支）。
/// 脱真图片、脱 Vision：纯 behavior 驱动，供模拟器/CI 走通全流程与降级。
@MainActor
final class ScreenshotOCRProviderTests: XCTestCase {

    /// mock 忽略图片内容，恒返定值；用空 Data 即可驱动。
    private let anyImageData = Data()

    // MARK: - success：返样例 OCR 文本（非空、不含前缀）

    func testSuccessReturnsSampleRecognizedText() async throws {
        let provider = MockTextRecognizer()
        provider.behavior = .success
        let text = try await provider.recognizeText(in: anyImageData)
        XCTAssertEqual(text, MockTextRecognizer.sampleRecognizedText)
        XCTAssertFalse(text.isEmpty)
        XCTAssertFalse(text.hasPrefix("[截图识别]"))              // 纯识别文本，前缀在入口层拼
    }

    // MARK: - empty：没读出字 → 抛 .empty

    func testEmptyThrowsEmpty() async {
        let provider = MockTextRecognizer()
        provider.behavior = .empty
        await assertThrowsOCRError(.empty) {
            _ = try await provider.recognizeText(in: anyImageData)
        }
    }

    // MARK: - failed：解码/OCR 失败 → 抛 .failed

    func testFailedThrowsFailed() async {
        let provider = MockTextRecognizer()
        provider.behavior = .failed
        await assertThrowsOCRError(.failed) {
            _ = try await provider.recognizeText(in: anyImageData)
        }
    }

    // MARK: - 三态齐备（防御后续增删漏改分支）

    func testBehaviorCoversExactThreeCases() {
        // 断言具体集合而非仅计数：增删各一仍能被此断言捕获（防切片02 漏改分支）。
        XCTAssertEqual(
            Set(MockTextRecognizer.Behavior.allCases.map(\.rawValue)),
            ["success", "empty", "failed"])
    }

    // MARK: - Helper

    private func assertThrowsOCRError(
        _ expected: TextRecognizeError,
        _ body: () async throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("应抛 \(expected)，但未抛错", file: file, line: line)
        } catch let error as TextRecognizeError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("应抛 TextRecognizeError.\(expected)，实际抛 \(error)", file: file, line: line)
        }
    }
}
