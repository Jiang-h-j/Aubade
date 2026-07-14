import SwiftUI
import SwiftData

/// 记账 Tab 真实视图（原型 §4.2），替换切片 01 的 `RecordTabPlaceholder`。
///
/// 组成：顶部「今日已记 N 笔」chip、四入口网格（仅手动可用，余三占位提示）、
/// 「最近记录」最近 4 笔 + 「全部 ›」跳账单 Tab。跨 Tab 跳转经 `@Binding selection` 直传（TRD §82）。
struct RecordTabView: View {
    /// 跨 Tab 跳转能力：「全部 ›」切到账单 Tab。由 RootTabView 传入 selectedTab 绑定。
    @Binding var selection: AppTab

    @Environment(\.modelContext) private var modelContext
    // 今日已记按 createdAt=今天计数（PRD 已确认约定 3）；数据量小，取全部内存过滤，避免动态 predicate。
    @Query private var allTransactions: [Transaction]
    // 最近记录按 occurredAt 倒序（PRD 已确认约定 3），取前 4 笔。
    @Query(sort: \Transaction.occurredAt, order: .reverse) private var recentTransactions: [Transaction]
    // 分类查全部（N07 前向兼容），编辑 sheet 复用。
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    @State private var showingManualEntry = false
    @State private var showingTextRecognition = false   // 文本识别页（本片接通）
    @State private var placeholderEntryTitle: String?   // 余两占位入口点击提示（非 nil 即弹）
    @State private var editingTransaction: Transaction?

    /// 文本识别解析器注入：生产走 DeepSeekClient；DEBUG（模拟器/预览）走 mock 以便肉眼走通链路。
    /// DEBUG 运行时切换 mock 成功/失败行为在切片 03。
    private var textParser: TransactionParsing {
        #if DEBUG
        MockTransactionParser()
        #else
        DeepSeekClient()
        #endif
    }

    /// 今日已记笔数：createdAt 落在今天。
    private var todayCount: Int {
        allTransactions.filter { Calendar.current.isDateInToday($0.createdAt) }.count
    }

    private var recentFour: [Transaction] {
        Array(recentTransactions.prefix(4))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    entryGrid
                    recentSection
                }
                .padding()
            }
            .navigationTitle("记一笔")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("今日已记 \(todayCount) 笔")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showingManualEntry) {
                ManualEntryView()
            }
            .fullScreenCover(isPresented: $showingTextRecognition) {
                TextRecognitionView(parser: textParser, categories: categories)
            }
            .sheet(item: $editingTransaction) { tx in
                editSheet(for: tx)
            }
            .alert("敬请期待", isPresented: Binding(
                get: { placeholderEntryTitle != nil },
                set: { if !$0 { placeholderEntryTitle = nil } }
            )) {
                Button("好", role: .cancel) { }
            } message: {
                Text("\(placeholderEntryTitle ?? "")将在后续版本提供")
            }
        }
    }

    // MARK: - 四入口网格（2×2，仅手动可用）

    private var entryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            EntryButton(emoji: "📷", title: "截图识别") { placeholderEntryTitle = "截图识别" }
            EntryButton(emoji: "🎤", title: "语音记账") { placeholderEntryTitle = "语音记账" }
            EntryButton(emoji: "📋", title: "文本识别") { showingTextRecognition = true }
            EntryButton(emoji: "✏️", title: "手动输入") { showingManualEntry = true }
        }
    }

    // MARK: - 最近记录

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近记录").font(.headline)
                Spacer()
                if !recentFour.isEmpty {
                    Button {
                        selection = .ledger
                    } label: {
                        Text("全部 ›").font(.subheadline)
                    }
                }
            }

            if recentFour.isEmpty {
                emptyRecent
            } else {
                VStack(spacing: 0) {
                    ForEach(recentFour) { tx in
                        Button {
                            editingTransaction = tx
                        } label: {
                            RecentTransactionRow(tx: tx)
                        }
                        .buttonStyle(.plain)
                        if tx.id != recentFour.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var emptyRecent: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("还没有记录，点『手动输入』记第一笔")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - 编辑 sheet（本片即接 updateTransaction 落库，编辑保存完整闭环）

    private func editSheet(for tx: Transaction) -> some View {
        let store = LedgerStore(modelContext)
        // 落库逻辑走共享 EditorActions，与切片 03 列表进编辑单一来源。本片不注入 onDelete（删除在切片 03）。
        return TransactionEditor(
            mode: .edit(tx),
            categories: categories,
            onSave: EditorActions.makeUpdate(store: store, tx: tx)
        )
    }
}

// MARK: - 子视图

/// 四入口的方块按钮。
private struct EntryButton: View {
    let emoji: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(emoji).font(.largeTitle)
                Text(title).font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// 最近记录单行：分类标签（emoji + 名）+ 商户/备注摘要 + 方向金额。
private struct RecentTransactionRow: View {
    let tx: Transaction

    private var subtitle: String {
        // 商户 > 备注 > 兜底显示发生时间（避免与上一行分类名重复）。
        if let m = tx.merchant, !m.isEmpty { return m }
        if let n = tx.note, !n.isEmpty { return n }
        return tx.occurredAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var categoryName: String {
        tx.category?.name ?? "未分类"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(CategoryStyle.emoji(for: tx.category))
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(
                    CategoryStyle.color(name: tx.category?.name, direction: tx.direction).opacity(0.15),
                    in: Circle()
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(categoryName).font(.body)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(AmountFormat.signedString(tx.amount, direction: tx.direction))
                .font(.body.monospacedDigit())
                .foregroundStyle(AmountFormat.color(for: tx.direction))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
