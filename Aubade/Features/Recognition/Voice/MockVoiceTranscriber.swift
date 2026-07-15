import Foundation

/// 语音转文字 mock（供 DEBUG / 预览 / 单测；对齐 MockTransactionParser 范式）。
/// 五态覆盖成功 + 空结果 + 三类授权/能力失败，让模拟器无真麦克风也能走通全流程与降级。
@MainActor
final class MockVoiceTranscriber: VoiceTranscribing {
    /// String rawValue：供 DEBUG 调试菜单经 @AppStorage 持久化（切片 03）。
    enum Behavior: String, CaseIterable {
        case success            // 转出"打车花了 20 块"
        case empty              // 空结果
        case microphoneDenied
        case speechDenied
        case onDeviceUnavailable
    }
    var behavior: Behavior = .success

    /// 语音成功样例口语（纯口语，不含前缀；前缀在入口层拼，见切片 03 §rawText）。
    static let sampleSpokenText = "打车花了 20 块"

    func start() async throws {
        switch behavior {
        case .microphoneDenied:    throw VoiceTranscribeError.microphoneDenied
        case .speechDenied:        throw VoiceTranscribeError.speechDenied
        case .onDeviceUnavailable: throw VoiceTranscribeError.onDeviceUnavailable
        case .success, .empty:     return   // 起录音成功
        }
    }

    func finish() async throws -> String {
        switch behavior {
        case .empty:   throw VoiceTranscribeError.empty
        case .success: return Self.sampleSpokenText
        default:       throw VoiceTranscribeError.failed   // 已在 start 抛错，防御
        }
    }

    func cancel() {}
}
