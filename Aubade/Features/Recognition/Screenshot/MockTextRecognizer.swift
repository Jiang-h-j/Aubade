import Foundation

/// 图片 OCR mock（供 DEBUG / 预览 / 单测；对齐 MockVoiceTranscriber 范式）。
/// 三态覆盖成功 + 空结果 + 失败，让模拟器无真图片也能走通全流程与降级。
@MainActor
final class MockTextRecognizer: TextRecognizing {
    /// String rawValue：供 DEBUG 调试菜单经 @AppStorage 持久化（切片 02）。
    enum Behavior: String, CaseIterable {
        case success   // 读出付款截图样例文本
        case empty     // 没读出字
        case failed    // 图片无法解码 / OCR 失败
    }
    var behavior: Behavior = .success

    /// 截图成功样例 OCR 文本（纯识别文本，不含 [截图识别] 前缀；前缀在入口层拼，见切片 02）。
    /// 对齐 demo data.js 截图 raw（星巴克/88.50）；交给 parser 的 mock（.screenshotSample）解出定值。
    static let sampleRecognizedText = "星巴克咖啡\n实付金额 ¥88.50\n2026-07-10 13:10\n交易成功"

    func recognizeText(in imageData: Data) async throws -> String {
        switch behavior {
        case .success: return Self.sampleRecognizedText
        case .empty:   throw TextRecognizeError.empty
        case .failed:  throw TextRecognizeError.failed
        }
    }
}
