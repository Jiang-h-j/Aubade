import SwiftUI
import SwiftData

/// 手动记账入口：以 `TransactionEditor` 的 create 模式呈现手动表单（原型 §4.4，不含商户）。
///
/// 保存经 `LedgerStore.createTransaction(... source: .manual)`。商户在手动模式恒为 nil、
/// cardTail/rawText/imageRef 留 nil。保存成功后记账页 `@Query` 自动刷新（同一注入 context，验收 1/7）。
struct ManualEntryView: View {
    @Environment(\.modelContext) private var modelContext
    // 分类选择器查全部分类（对 N07 自建分类前向兼容），组件内按当前方向过滤。
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    var body: some View {
        TransactionEditor(
            mode: .create(direction: .expense),
            categories: categories,
            onSave: { draft in
                // isValid 已保证 parsedAmount 非 nil、> 0；此处兜底防御。
                guard let amount = draft.parsedAmount, amount > 0 else { return }
                let store = LedgerStore(modelContext)
                try store.createTransaction(
                    amount: amount,
                    direction: draft.direction,
                    occurredAt: draft.occurredAt,
                    category: draft.category,
                    merchant: nil,               // 手动模式恒不采集商户
                    note: draft.normalizedNote,
                    source: .manual
                )
            }
        )
    }
}
