import Foundation

/// 剩余金额派生计算的**无状态纯函数**（N02 M6，节点 PRD 目标 1、6）。
///
/// 无状态、注入数据、不触库，边界可单测。金额一律纯 `Decimal` reduce，不经 `Double`
/// （节点约束 2，对齐 `DecimalPrecisionTests`）。切片 02 的 `StatisticsAggregator` 同目录。
enum BalanceCalculator {

    /// 剩余 = initialAmount + Σ(基线后收入) − Σ(基线后支出)。
    /// "基线后" = `occurredAt >= establishedAt`（PRD 已确认约定 2，同刻计入）。
    /// baseline 为 nil 时返回 nil —— 视图显示"—"，引导用户先录初始总额。
    static func remaining(transactions: [Transaction], baseline: BalanceBaseline?) -> Decimal? {
        guard let baseline else { return nil }
        let after = transactions.filter { $0.occurredAt >= baseline.establishedAt }
        return baseline.initialAmount
            + sum(after, direction: .income)
            - sum(after, direction: .expense)
    }

    /// 按方向对账单金额求和（供剩余计算与汇总卡本月支出/收入复用）。纯 `Decimal`。
    static func sum(_ transactions: [Transaction], direction: TransactionDirection) -> Decimal {
        transactions
            .filter { $0.direction == direction }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }
}
