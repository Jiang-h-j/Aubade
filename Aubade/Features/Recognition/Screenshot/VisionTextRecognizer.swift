import Foundation
import Vision
import CoreGraphics
import ImageIO

/// 真实「图片 → 本机中文 OCR 文本」实现（Vision）。图片不外传：Vision 文本识别纯本机、无上云路径。
/// perform 派后台队列执行（同步阻塞调用，不占主线程）；无存储状态。
@MainActor
final class VisionTextRecognizer: TextRecognizing {
    func recognizeText(in imageData: Data) async throws -> String {
        // 1) Data → CGImage（解码失败 = .failed，不外传、不误记）
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TextRecognizeError.failed
        }
        // 2) 后台执行 Vision（perform 同步阻塞→派 global 队列，不卡主线程）；同步读 results，单次 resume
        let lines: [String] = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLanguages = ["zh-Hans", "zh-Hant"]
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])          // 同步阻塞直到识别完成（后台线程）
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    let texts = observations.compactMap { $0.topCandidates(1).first?.string }
                    cont.resume(returning: texts)           // 成功：单次 resume
                } catch {
                    cont.resume(throwing: TextRecognizeError.failed)   // 失败：单次 resume
                }
            }
        }
        // 3) 多行拼成一段（行序即 Vision 返回序）→ trim；空 = .empty（没读出字，不误记）
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { throw TextRecognizeError.empty }
        return joined
    }
}
