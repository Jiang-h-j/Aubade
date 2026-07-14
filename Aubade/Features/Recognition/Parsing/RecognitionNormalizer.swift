import Foundation

/// 把 DeepSeek 的原始解析结果归一成可落库字段的无状态纯函数集合。
/// 注入 now（测试可固定时刻），不触库、不联网——正确性全由单测焊死。
enum RecognitionNormalizer {

    /// 金额：ParsedTransaction.amountText → Decimal（元，不经 Double，对齐 TransactionDraft.parsedAmount）。
    /// 空 / 非数 / <= 0 → 抛 .noAmount（"无金额 = 失败"的落点，调用方捕获转手动）。
    static func amount(_ text: String) throws -> Decimal {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Decimal(string: trimmed), value > 0 else {
            throw RecognitionError.noAmount
        }
        return value
    }

    /// 时间：nil → now；晚于 now → clamp 到 now（禁未来，对齐 N01 编辑器 DatePicker(in: ...now)）。
    static func occurredAt(_ date: Date?, now: Date) -> Date {
        guard let date else { return now }
        return date > now ? now : date
    }

    /// 分类兜底：按 name+direction 精确匹配库中分类；不匹配 → 该方向兜底（支出"其他"/收入"其他收入"）。
    /// 方向与分类矛盾（匹配到的分类方向 ≠ direction）也以 direction 为准取兜底。
    /// 库中缺兜底分类（异常态）返回 nil，落库为未分类（Transaction.category 可空）。
    static func category(name: String?, direction: TransactionDirection,
                         in categories: [LedgerCategory]) -> LedgerCategory? {
        if let name, let hit = categories.first(where: { $0.name == name && $0.direction == direction }) {
            return hit
        }
        let fallbackName = (direction == .expense) ? "其他" : "其他收入"
        return categories.first { $0.name == fallbackName && $0.direction == direction }
    }
}
