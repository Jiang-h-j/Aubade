import SwiftUI
import SwiftData

/// 手动记账入口：以 `TransactionEditor` 的 create 模式呈现手动表单（原型 §4.4，不含商户）。
///
/// 保存经 `LedgerStore.createTransaction(... source: .manual)`。商户在手动模式恒为 nil、
/// cardTail/rawText 留 nil。保存成功后记账页 `@Query` 自动刷新（同一注入 context，验收 1/7）。
///
/// N06 切片 02：失败通知深链补录时带 `prefillImageRef`——据 ref 从 `TemporaryImageStore` 取回原图展示；
/// 补录成功把 ref 落到新账单 `imageRef` 并清理临时文件，放弃（未保存关闭）则清理，成功入账后不再留临时图。
struct ManualEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    // 分类选择器查全部分类（对 N07 自建分类前向兼容），组件内按当前方向过滤。
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    /// 转手动带原文预填备注（N03 识别失败转手动，验收 6）。默认 nil：现有 `ManualEntryView()` 调用不受影响。
    private let prefillNote: String?
    /// 失败截图补录带原图引用（N06 切片 02）。默认 nil：现有调用不受影响。
    private let prefillImageRef: String?

    private let imageStore = TemporaryImageStore()
    /// 据 ref 取回的原图数据（补录期临时展示；v1 不做图库，仅此一处临时用）。
    @State private var prefillImageData: Data?

    init(prefillNote: String? = nil, prefillImageRef: String? = nil) {
        self.prefillNote = prefillNote
        self.prefillImageRef = prefillImageRef
    }

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
                    source: .manual,
                    imageRef: prefillImageRef    // 补录带原图时把临时 ref 落到新账单（无则 nil）
                )
            },
            initialNote: prefillNote,            // 转手动时预填识别原文进备注
            attachmentImageData: prefillImageData // 补录带原图时表单顶部展示（无则不渲染）
        )
        .task {
            // 据 ref 取回原图（仅补录场景 ref 非 nil）；取不到静默不展示。
            if let ref = prefillImageRef {
                prefillImageData = imageStore.loadImage(ref: ref)
            }
        }
        .onDisappear {
            // 临时原图用后即清：补录成功（已落 imageRef 到账单）或放弃（未保存）都不再需要临时文件。
            if let ref = prefillImageRef {
                imageStore.remove(ref: ref)
            }
        }
    }
}
