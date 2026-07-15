import Foundation

/// 本机图片 OCR 的可区分失败（入口层据此分支降级；对齐 VoiceTranscribeError 范式）。
enum TextRecognizeError: Error, Equatable {
    case empty      // OCR 成功执行但没读出任何文字（空白图/无文字图）
    case failed     // 图片无法解码 / Vision 请求失败
}

/// "图片 → 本机 OCR 文本" 的能力抽象。真实（Vision）与 mock 同契约，注入以便单测脱真图片。
/// 脱 View、脱相册 UI：入参是图片数据，可被 N06 快捷指令后台链路独立调用（PRD 已确认约定 9）。
/// @MainActor：与 N04 provider 一致对齐调用方（切片 02 MainActor View 的 Task）；真实实现内部把
/// 阻塞的 Vision perform 派到后台队列，@MainActor 仅约束方法入口/出口，不在主线程跑 OCR（见 VisionTextRecognizer）。
@MainActor
protocol TextRecognizing {
    /// 识别图片中的文字（本机、中文）。读不出字 → 抛 .empty；解码/请求失败 → 抛 .failed。
    /// 返回值 = trim 后的多行识别文本（行间 \n 连接）。
    func recognizeText(in imageData: Data) async throws -> String
}
