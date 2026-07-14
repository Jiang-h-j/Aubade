import SwiftUI
import SwiftData

/// 账单编辑页容器（切片 03）：复用切片 02 的 `TransactionEditor(.edit)`，注入编辑落库与删除。
///
/// 经 `.sheet` 呈现（TRD 设计方案 §4）：`TransactionEditor` 内部自带 `NavigationStack`（含自身
/// 取消/保存 toolbar），故本容器不再套导航栈，仅提供分类候选、落库闭包与删除二次确认。
/// - onSave：复用 `EditorActions.makeUpdate`（与记账页最近记录单一来源，落库刷新 updatedAt）。
/// - onDelete：本容器注入——点「删除这笔」先弹 `.confirmationDialog` 二次确认（验收 4），
///   确认后 `EditorActions.makeDelete` 真删并 `dismiss` 关闭 sheet；取消则保留。
struct TransactionDetailView: View {
    let tx: Transaction

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    // 分类候选查全部（N07 前向兼容），交 TransactionEditor 按方向过滤。
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @State private var showingDeleteConfirm = false

    private var store: LedgerStore { LedgerStore(modelContext) }

    var body: some View {
        TransactionEditor(
            mode: .edit(tx),
            categories: categories,
            onSave: EditorActions.makeUpdate(store: store, tx: tx),
            onDelete: { showingDeleteConfirm = true }
        )
        .confirmationDialog("删除这笔账单？", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                // 先 dismiss 再 delete：delete 的 save 会触发父视图 @Query 刷新，此时 sheet 已在关闭流程中、
                // item 已置 nil，避免 sheet 以已删 tx 重建 editor 读取已删对象属性（SwiftData 敏感，见 memory）。
                let performDelete = EditorActions.makeDelete(store: store, tx: tx)
                dismiss()
                performDelete()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("删除后无法恢复")
        }
    }
}
