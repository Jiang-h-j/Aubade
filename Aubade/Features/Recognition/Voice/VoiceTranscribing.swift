import Foundation

/// 语音转文字的可区分失败（入口层据此分支降级；对齐 RecognitionError 范式）。
enum VoiceTranscribeError: Error, Equatable {
    case microphoneDenied      // 麦克风权限被拒/受限
    case speechDenied          // 语音识别权限被拒/受限
    case onDeviceUnavailable   // supportsOnDeviceRecognition == false 或识别器不可用（隐私边界：不回退云端）
    case empty                 // 授权成功但没说话 / 没转出文字
    case failed                // 其他运行时失败（音频引擎/识别器错误）
}

/// "按住说话 → 本机转中文文字" 的能力抽象。真实（SFSpeech）与 mock 同契约，注入以便单测脱真麦克风。
/// @MainActor：真实实现涉 AVAudioSession/SFSpeechRecognizer，须主线程；mock 亦标注保持一致。
@MainActor
protocol VoiceTranscribing {
    /// 起录音+本机识别：内部先申请麦克风+语音识别权限、check on-device。
    /// 权限被拒/本机不可用 → 抛对应 VoiceTranscribeError（不起录音）。
    func start() async throws
    /// 结束录音并返回最终转出文本（trim 后）；无文字 → 抛 .empty。
    func finish() async throws -> String
    /// 取消并丢弃当前录音（松手前放弃 / 面板关闭）。
    func cancel()
}
