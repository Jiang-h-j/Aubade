import XCTest
@testable import Aubade

/// TRD 01 验证点：MockVoiceTranscriber 五态可区分（对齐 PRD 验收 9 provider 分支）。
/// 脱真麦克风、脱系统 API：纯 behavior 驱动，供模拟器/CI 走通全流程与降级。
@MainActor
final class VoiceProviderTests: XCTestCase {

    // MARK: - success：start 不抛，finish 返样例口语

    func testSuccessStartsAndFinishesWithSampleText() async throws {
        let provider = MockVoiceTranscriber()
        provider.behavior = .success
        try await provider.start()                                   // 起录音成功，不抛
        let text = try await provider.finish()
        XCTAssertEqual(text, "打车花了 20 块")                        // 纯口语，不含前缀
        XCTAssertEqual(text, MockVoiceTranscriber.sampleSpokenText)
    }

    // MARK: - empty：start 成功，finish 抛 .empty

    func testEmptyStartsButFinishThrowsEmpty() async throws {
        let provider = MockVoiceTranscriber()
        provider.behavior = .empty
        try await provider.start()                                   // 授权成功、起录音成功
        await assertThrowsVoiceError(.empty) {
            _ = try await provider.finish()                          // 没说话 → 空结果
        }
    }

    // MARK: - 三类授权/能力失败：start 即抛，不起录音

    func testMicrophoneDeniedThrowsOnStart() async {
        let provider = MockVoiceTranscriber()
        provider.behavior = .microphoneDenied
        await assertThrowsVoiceError(.microphoneDenied) {
            try await provider.start()
        }
    }

    func testSpeechDeniedThrowsOnStart() async {
        let provider = MockVoiceTranscriber()
        provider.behavior = .speechDenied
        await assertThrowsVoiceError(.speechDenied) {
            try await provider.start()
        }
    }

    func testOnDeviceUnavailableThrowsOnStart() async {
        let provider = MockVoiceTranscriber()
        provider.behavior = .onDeviceUnavailable
        await assertThrowsVoiceError(.onDeviceUnavailable) {
            try await provider.start()
        }
    }

    // MARK: - 五态齐备（防御后续增删漏改分支）

    func testBehaviorCoversExactFiveCases() {
        // 断言具体集合而非仅计数：增删各一仍能被此断言捕获（防切片02/03 漏改分支）。
        XCTAssertEqual(
            Set(MockVoiceTranscriber.Behavior.allCases.map(\.rawValue)),
            ["success", "empty", "microphoneDenied", "speechDenied", "onDeviceUnavailable"])
    }

    // MARK: - Helper

    private func assertThrowsVoiceError(
        _ expected: VoiceTranscribeError,
        _ body: () async throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("应抛 \(expected)，但未抛错", file: file, line: line)
        } catch let error as VoiceTranscribeError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("应抛 VoiceTranscribeError.\(expected)，实际抛 \(error)", file: file, line: line)
        }
    }
}
