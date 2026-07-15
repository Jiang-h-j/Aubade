import SwiftUI
import SwiftData
import UIKit

/// 编辑组件工作模式：新建草稿（保存走 createTransaction）或编辑既有（保存走 updateTransaction）。
enum EditorMode {
    case create(direction: TransactionDirection)   // 手动新建，默认支出
    case edit(Transaction)                          // 绑定既有（切片 03 列表进编辑复用）
}

/// **可复用账单编辑组件**：手动记账（create）与改一笔既有账单（edit）共用同一表单与校验。
///
/// 做成一个组件的理由：N03~N06 的截图/语音/文本识别结果卡片直接复用它（字段集对齐原型 §4.3），
/// 不重复造。落库差异（create vs update）由调用方注入 `onSave` 闭包决定，组件本身不持有 `LedgerStore`。
///
/// 注入契约：组件不碰 ModelContainer/ModelContext，只管表单状态与校验；分类列表由调用方经 `@Query` 传入。
struct TransactionEditor: View {
    let mode: EditorMode
    /// 供分类选择器展示的候选分类（调用方经 `@Query` 传全部分类，组件内按当前方向过滤）。
    let categories: [LedgerCategory]
    /// 保存动作由调用方注入：create 走 createTransaction、edit 走 updateTransaction。
    let onSave: (TransactionDraft) throws -> Void
    /// 删除入口的占位钩子：仅 edit 模式且注入时渲染（切片 03 注入二次确认 + delete）。
    var onDelete: (() -> Void)? = nil
    /// 识别原文（原型 §4.3 折叠原文展示区）。本片手动入口恒为 nil、不渲染，结构上为 N03~N06 识别结果卡片留位（PRD §6）。
    var rawText: String? = nil
    /// 补录期临时原图（N06 切片 02 失败截图补录）。非 nil 时表单顶部展示缩略；默认 nil 不渲染，现有调用不受影响。
    var attachmentImageData: Data? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TransactionDraft
    @State private var saveError: String?

    /// 新建模式的初始备注（N03 识别失败转手动：把识别原文预填进备注，验收 6）。
    /// 向后兼容可选参数，默认 nil；仅 `.create` 分支消费，`.edit` 从 tx 回填不受影响。
    /// 现有 3 处调用（ManualEntryView / RecordTabView.editSheet / TransactionDetailView）不传，零影响。
    init(mode: EditorMode,
         categories: [LedgerCategory],
         onSave: @escaping (TransactionDraft) throws -> Void,
         onDelete: (() -> Void)? = nil,
         rawText: String? = nil,
         initialNote: String? = nil,
         attachmentImageData: Data? = nil) {
        self.mode = mode
        self.categories = categories
        self.onSave = onSave
        self.onDelete = onDelete
        self.rawText = rawText
        self.attachmentImageData = attachmentImageData
        _draft = State(initialValue: Self.makeInitialDraft(mode: mode, initialNote: initialNote))
    }

    /// 从 mode + initialNote 构造初始草稿（脱 View 的可测核心，同 `RecognitionEntry` 惯例）：
    /// `.create` 用初始方向建空草稿并把 initialNote 预填进 note；`.edit` 从既有 tx 逐字段回填、忽略 initialNote。
    static func makeInitialDraft(mode: EditorMode, initialNote: String?) -> TransactionDraft {
        switch mode {
        case .create(let direction):
            var d = TransactionDraft(direction: direction, occurredAt: Date())
            if let initialNote { d.note = initialNote }   // 仅 create 预填；edit 从 tx 回填不碰
            return d
        case .edit(let tx):
            return TransactionDraft(from: tx)
        }
    }

    /// 手动新建隐藏商户输入（原型 §4.4，保持最短路径，PRD 已确认约定 1）；编辑显示商户。
    /// 组件内部始终支持 merchant 字段（供 N03+ 识别填充），仅"手动新建"这一 UI 入口隐藏它。
    private var showsMerchant: Bool {
        if case .create = mode { return false }
        return true
    }

    private var navigationTitle: String {
        switch mode {
        case .create: return "记一笔"
        case .edit:   return "编辑账单"
        }
    }

    /// 随当前方向过滤的分类候选，按 sortOrder 升序。
    private var categoriesForDirection: [LedgerCategory] {
        categories
            .filter { $0.direction == draft.direction }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let attachmentImageData { attachmentSection(attachmentImageData) }
                amountSection
                directionSection
                categorySection
                dateSection
                if showsMerchant { merchantSection }
                noteSection
                if let rawText, !rawText.isEmpty { rawTextSection(rawText) }
                if let onDelete { deleteSection(onDelete) }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!draft.isValid)
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) { }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    // MARK: - 表单分区（原型 §4.3 字段序：金额/方向/分类/时间/商户/备注）

    private var amountSection: some View {
        Section("金额") {
            TextField("0.00", text: $draft.amountText)
                .keyboardType(.decimalPad)
                .font(.title2.monospacedDigit())
        }
    }

    private var directionSection: some View {
        Section {
            Picker("方向", selection: $draft.direction) {
                ForEach(TransactionDirection.allCases, id: \.self) { d in
                    Text(d == .expense ? "支出" : "收入").tag(d)
                }
            }
            .pickerStyle(.segmented)
            // 切换方向时若已选分类与新方向不符则清空（避免"支出选了食、切到收入仍挂食"）。
            .onChange(of: draft.direction) { _, newDirection in
                if let selected = draft.category, selected.direction != newDirection {
                    draft.category = nil
                }
            }
        }
    }

    private var categorySection: some View {
        Section("分类") {
            Picker("分类", selection: $draft.category) {
                Text("不选").tag(LedgerCategory?.none)
                ForEach(categoriesForDirection) { cat in
                    Text(cat.name).tag(LedgerCategory?.some(cat))
                }
            }
        }
    }

    private var dateSection: some View {
        // 禁未来日期（PRD 已确认约定 2）：DatePicker 限 ...Date()。
        Section("时间") {
            DatePicker("时间", selection: $draft.occurredAt, in: ...Date(),
                       displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
        }
    }

    private var merchantSection: some View {
        Section("商户") {
            TextField("商户名称", text: $draft.merchant)
        }
    }

    private var noteSection: some View {
        Section("备注") {
            TextField("备注", text: $draft.note, axis: .vertical)
                .lineLimit(1...3)
        }
    }

    /// 补录期原图展示区（N06 切片 02）：失败截图深链补录时展示留存的原图缩略，供用户对照填写。
    /// 解码失败给占位（v1 不做图库，仅临时对照用）。
    private func attachmentSection(_ data: Data) -> some View {
        Section("原截图") {
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Label("原图无法显示", systemImage: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 识别原文折叠区（原型 §4.3）：仅结果卡片注入非空 rawText 时渲染，手动入口 rawText=nil 不显示。默认收起。
    private func rawTextSection(_ raw: String) -> some View {
        Section {
            DisclosureGroup("查看识别到的原始文本") {
                Text(raw)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func deleteSection(_ delete: @escaping () -> Void) -> some View {
        Section {
            Button("删除这笔", role: .destructive) { delete() }
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 保存

    private func save() {
        guard draft.isValid else { return }
        do {
            try onSave(draft)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
