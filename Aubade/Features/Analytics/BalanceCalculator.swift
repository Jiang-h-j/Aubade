import Foundation

/// 剩余金额派生计算的**无状态纯函数**（N02 M6，节点 PRD 目标 1、6）。
///
/// 无状态、注入数据、不触库，边界可单测。金额一律纯 `Decimal` reduce，不经 `Double`
/// （节点约束 2，对齐 `DecimalPrecisionTests`）。切片 02 的 `StatisticsAggregator` 同目录。
enum BalanceCalculator {

    /// 剩余 = initialAmount + Σ(全部收入) − Σ(全部支出)。对全部账单求和，
    /// 不按 occurredAt 与 establishedAt 先后过滤——早于初始总额录入时刻的账也参与加减（B01 推翻 N02 约定 2）。
    /// baseline 为 nil 时返回 nil —— 视图显示"—"，引导用户先录初始总额。
    static func remaining(transactions: [Transaction], baseline: BalanceBaseline?) -> Decimal? {
        guard let baseline else { return nil }
        return baseline.initialAmount
            + sum(transactions, direction: .income)
            - sum(transactions, direction: .expense)
    }

    /// 按方向对账单金额求和（供剩余计算与汇总卡本月支出/收入复用）。纯 `Decimal`。
    static func sum(_ transactions: [Transaction], direction: TransactionDirection) -> Decimal {
        transactions
            .filter { $0.direction == direction }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }
}
