import Foundation

/// 账单编辑的**纯值表单状态**：与视图解耦，可单测金额解析/校验与编辑回填。
///
/// 供 `TransactionEditor` 双模式共用——新建（空草稿）与编辑（从既有 `Transaction` 回填）。
/// 金额以原始输入串保存，保存时才解析为 `Decimal`，避免 UI 中间态污染落库精度。
struct TransactionDraft {
    var amountText: String        // 原始输入串，保存时解析为 Decimal
    var direction: TransactionDirection
    var category: LedgerCategory?
    var occurredAt: Date
    var merchant: String          // 空串（去空白后）视为 nil
    var note: String              // 空串（去空白后）视为 nil

    /// 新建：空表单。方向由入口决定（手动默认支出）。
    init(direction: TransactionDirection, occurredAt: Date) {
        self.amountText = ""
        self.direction = direction
        self.category = nil
        self.occurredAt = occurredAt
        self.merchant = ""
        self.note = ""
    }

    /// 编辑：从既有账单逐字段回填（验收 9 双模式回填）。金额存正值，回填为其字符串。
    init(from tx: Transaction) {
        self.amountText = NSDecimalNumber(decimal: tx.amount).stringValue
        self.direction = tx.direction
        self.category = tx.category
        self.occurredAt = tx.occurredAt
        self.merchant = tx.merchant ?? ""
        self.note = tx.note ?? ""
    }

    /// 金额解析：`Decimal(string:)` 恒以 `.` 为小数点（locale 无关；zh_CN happy path 无碍，
    /// 逗号小数区域的 i18n 留待后续换 `Decimal(string:locale:)`）。以 Decimal 落库避免浮点误差。
    /// 空串 / 非数字 → nil。
    var parsedAmount: Decimal? {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed)
    }

    /// 金额解析成功且 > 0 才允许保存。
    var isValid: Bool {
        (parsedAmount.map { $0 > 0 }) ?? false
    }

    /// 商户去空白后的可落库值（空 → nil）。手动入口恒不采集商户，由调用方决定是否使用。
    var normalizedMerchant: String? {
        let trimmed = merchant.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 备注去空白后的可落库值（空 → nil）。
    var normalizedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
