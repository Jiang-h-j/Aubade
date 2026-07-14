import Foundation

/// 编辑既有账单的**共享落库构造**：把 draft 回写进 Transaction 的逻辑收敛到单一来源，
/// 供记账页最近记录（切片 02，sheet 呈现）与账单列表（切片 03，push 呈现）复用，避免两处重复。
///
/// 只负责 edit 模式（既有账单）；create 模式的落库差异（createTransaction）留在各自入口。
enum EditorActions {

    /// 构造 edit 模式的 onSave：`updateTransaction` 内把 draft 各字段回写既有账单，刷新 updatedAt。
    /// 金额以校验后的 `parsedAmount` 落库（isValid 保证非 nil，此处再兜一次防御）。
    static func makeUpdate(store: LedgerStore, tx: Transaction) -> (TransactionDraft) throws -> Void {
        return { draft in
            guard let amount = draft.parsedAmount, amount > 0 else { return }
            try store.updateTransaction(tx) { t in
                t.amount = amount
                t.direction = draft.direction
                t.category = draft.category
                t.occurredAt = draft.occurredAt
                t.merchant = draft.normalizedMerchant
                t.note = draft.normalizedNote
            }
        }
    }

    /// 构造 edit 模式的 onDelete：删除既有账单。二次确认 UI 由调用方（切片 03）在调用前套。
    static func makeDelete(store: LedgerStore, tx: Transaction) -> () -> Void {
        return {
            try? store.delete(tx)
        }
    }
}
