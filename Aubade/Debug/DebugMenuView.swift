#if DEBUG
import SwiftUI
import SwiftData

/// 临时验证入口（仅 DEBUG）：手动触发插入样例账单 / 列出预置分类 / 清库重置，
/// 供真机或模拟器肉眼确认容器单点共享（PRD 验收 6）。Release 构建不含此入口。
struct DebugMenuView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query private var transactions: [Transaction]

    @State private var lastMessage: String = ""

    var body: some View {
        List {
            Section("库状态") {
                Text("预置分类：\(categories.filter { $0.isPreset }.count) 条")
                Text("账单：\(transactions.count) 笔")
                if !lastMessage.isEmpty {
                    Text(lastMessage).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("分类清单") {
                ForEach(categories) { category in
                    HStack {
                        Text(category.name)
                        Spacer()
                        Text(category.direction == .expense ? "支出" : "收入")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("操作") {
                Button("插入一笔样例账单") { insertSample() }
                Button("重新装载预置分类") {
                    PresetCategories.seedIfNeeded(context)
                    lastMessage = "已调用 seedIfNeeded（幂等）"
                }
                Button("清空全部数据", role: .destructive) { resetAll() }
            }
        }
        .navigationTitle("调试菜单")
    }

    private func insertSample() {
        let store = LedgerStore(context)
        do {
            let category = try store.presetCategories().first
            try store.createTransaction(
                amount: Decimal(string: "35.55")!, direction: .expense,
                occurredAt: Date(), category: category,
                merchant: "样例商户", source: .manual)
            lastMessage = "已插入样例账单 35.55"
        } catch {
            lastMessage = "插入失败：\(error)"
        }
    }

    private func resetAll() {
        do {
            for tx in transactions { context.delete(tx) }
            for category in categories { context.delete(category) }
            try context.save()
            lastMessage = "已清空全部数据"
        } catch {
            lastMessage = "清空失败：\(error)"
        }
    }
}
#endif
