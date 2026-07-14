import Foundation

/// DeepSeek 解析出的原始中间结果（未归一：金额是串、时间可空、分类名是自由文本）。
/// 归一（→ Decimal / 兜时间 / 兜分类）由 RecognitionNormalizer 负责，协议只管"取到什么"。
struct ParsedTransaction: Equatable {
    let amountText: String        // DeepSeek 返回的金额原文（如 "256.00"）；空/非数 → 归一判无金额
    let direction: TransactionDirection
    let occurredAt: Date?         // 解析不到为 nil（归一取当前）
    let merchant: String?
    let cardTail: String?
    let categoryName: String?     // DeepSeek 给的分类名自由文本（归一按 name+direction 匹配库/兜底）
}

/// 文本 → 结构化账单的解析能力。真实（DeepSeekClient）与 mock 同契约，注入以便单测与 N04~N06 复用。
protocol TransactionParsing {
    /// - categories: 当前库中分类清单（组 prompt 的"可选分类"提示；归一兜底在 Normalizer）。
    /// - 解析不出有效金额、网络失败、超时、非法响应、无 Key 时抛 RecognitionError。
    func parse(text: String, categories: [LedgerCategory]) async throws -> ParsedTransaction
}
