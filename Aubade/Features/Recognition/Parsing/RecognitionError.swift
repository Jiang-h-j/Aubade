import Foundation

/// 识别失败的可区分类型，供入口层分支（PRD §3、技术基线 §7.2）。
///
/// 入口层映射（切片 02/03 消费）：
/// - noKey            → 拦截提示配置 Key（不进行识别）
/// - noAmount         → 保留原文转手动（PRD 已确认约定：无金额 = 失败）
/// - network/timeout/invalidResponse → 提示对应失败 + 保留原文（可重试/转手动）
enum RecognitionError: Error, Equatable {
    case noKey            // Keychain 无有效 Key
    case network          // 连接失败 / 无网络
    case timeout          // 超时
    case noAmount         // 解析不出有效金额
    case invalidResponse  // 非法响应（非 JSON / 缺字段 / HTTP 非 2xx）
}
