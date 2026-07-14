import SwiftUI

/// 金额的**展示层**格式化：`Decimal` + 方向 → 带符号千分位串 + 方向色。
///
/// PRD 验收 1 要求金额千分位统一（`-35.55` / `+8,000.00`）；已确认约定 4 定方向色（收入绿 / 支出主文本色）。
/// 记账页最近记录（切片 02）与账单列表（切片 03）统一取用。纯展示、不触库。
enum AmountFormat {

    /// 千分位、固定 2 位小数。用 NSDecimalNumber 喂 formatter 保 Decimal 精度，不经 Double。
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        f.decimalSeparator = "."
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    /// 带方向符号的千分位串：支出前缀 `-`、收入前缀 `+`。amount 存正值，符号由 direction 决定。
    /// 例：`(35.55, .expense)` → `-35.55`；`(8000, .income)` → `+8,000.00`。
    static func signedString(_ amount: Decimal, direction: TransactionDirection) -> String {
        let number = NSDecimalNumber(decimal: amount)
        let body = formatter.string(from: number) ?? number.stringValue
        let sign = direction == .income ? "+" : "-"
        return sign + body
    }

    /// 无符号千分位串（如需纯数值展示时用）。
    static func plainString(_ amount: Decimal) -> String {
        let number = NSDecimalNumber(decimal: amount)
        return formatter.string(from: number) ?? number.stringValue
    }

    /// 方向色：收入绿、支出主文本色（已确认约定 4）。
    static func color(for direction: TransactionDirection) -> Color {
        switch direction {
        case .income:  return .green
        case .expense: return .primary
        }
    }
}
