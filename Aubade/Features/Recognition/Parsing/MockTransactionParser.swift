import Foundation

/// 可配置行为的 mock，供单测 / 预览 / DEBUG（PRD §1、已确认约定 1）。
/// success 恒返回 data.js MOCK_RECOGNIZE.text 定值（工行短信样例，cat 为"其他"）——
/// 验收观察的是链路与字段落库，而非通用真解析。
struct MockTransactionParser: TransactionParsing {
    /// String rawValue：供 DEBUG 调试菜单经 @AppStorage 持久化选择的 mock 行为（TRD 03 §5）。
    enum Behavior: String, CaseIterable { case success, noAmount, network, timeout, invalidResponse }
    var behavior: Behavior = .success

    /// 样例时间 "2026-07-10 15:22"（对齐 demo 定值）。用 DateComponents 构造避免 locale/解析器差异。
    static let sampleOccurredAt: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 10
        components.hour = 15
        components.minute = 22
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }()

    func parse(text: String, categories: [LedgerCategory]) async throws -> ParsedTransaction {
        switch behavior {
        case .network:         throw RecognitionError.network
        case .timeout:         throw RecognitionError.timeout
        case .invalidResponse: throw RecognitionError.invalidResponse
        case .noAmount:        throw RecognitionError.noAmount
        case .success:
            return ParsedTransaction(
                amountText: "256.00",
                direction: .expense,
                occurredAt: Self.sampleOccurredAt,
                merchant: "京东商城",
                cardTail: "1234",
                categoryName: "其他"
            )
        }
    }
}
