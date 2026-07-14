import SwiftUI
import UIKit

/// 识别 + 归一 + 落库的可测核心（脱 View，供单测直接调用）。
///
/// 关键不变量：任何失败（parse 抛错 / 归一抛 .noAmount）都发生在 `createTransaction` **之前**，
/// 保证识别失败不产生脏账（TRD 验证点 2/3）。
///
/// 钉在 @MainActor：ModelContext 非 Sendable，落库须在创建它的主线程执行；
/// parse 的 await 挂起点恢复后仍回到 MainActor（消除 "Unbinding from the main queue" 告警）。
@MainActor
enum RecognitionEntry {
    /// - now: 注入当前时刻（测试可固定，验证时间不越未来）。
    /// - source: 账单来源入口，默认 `.text`（N03 文本识别）；语音调用传 `.voice`（切片 03）。
    /// - rawText: 落库原文，默认 `nil` = 沿用 `text`（与 N03 现状等价）；语音传带 `[语音转文字]` 前缀的原文，
    ///   使 parse 输入（纯口语）与落库原文（带前缀）分离。
    @discardableResult
    static func recognizeAndSave(text: String,
                                 categories: [LedgerCategory],
                                 parser: TransactionParsing,
                                 store: LedgerStore,
                                 now: Date,
                                 source: TransactionSource = .text,
                                 rawText: String? = nil) async throws -> Transaction {
        let parsed = try await parser.parse(text: text, categories: categories)   // parse 用纯口语 text
        let amount = try RecognitionNormalizer.amount(parsed.amountText)   // 无金额 → 抛 .noAmount（落库前）
        let occurredAt = RecognitionNormalizer.occurredAt(parsed.occurredAt, now: now)
        let category = RecognitionNormalizer.category(name: parsed.categoryName,
                                                      direction: parsed.direction, in: categories)
        return try store.createTransaction(
            amount: amount,
            direction: parsed.direction,
            occurredAt: occurredAt,
            category: category,
            merchant: parsed.merchant,
            cardTail: parsed.cardTail,
            source: source,
            rawText: rawText ?? text)
    }
}

/// 文本识别页（原型 §4.3 openTextInput）：粘贴框 + 读剪贴板 + 识别并记账。
///
/// 切片 03 终态：识别成功 → 先入账 → 弹**结果卡片**（复用 `TransactionEditor(.edit)` + 折叠原文 + 改/删撤销）；
/// 识别失败 → 按错误类型给「转手动填写（带原文）」/「重试」；关闭链经 `resultTx` 归 nil 回记账页。
struct TextRecognitionView: View {
    let parser: TransactionParsing        // 注入：生产 DeepSeekClient / 测试预览 Mock
    let categories: [LedgerCategory]      // RecordTabView 的 @Query 传入

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var phase: RecognitionPhase = .idle
    @State private var showingKeySheet = false
    @State private var showKeyBlockedAlert = false
    @State private var resultTx: Transaction?          // 识别成功入账后的账单 → 触发结果卡片
    @State private var showingManualEntry = false      // 失败转手动（带原文预填）
    @State private var retryToken = 0                  // 重试：alert 关闭后经 onChange 重新识别

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isRecognizing: Bool { phase == .recognizing }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("粘贴或输入短信 / 账单文本…\n例：工商银行 您尾号1234的卡消费256.00元")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                        .disabled(isRecognizing)
                } header: {
                    Text("待识别文本")
                }

                Section {
                    Button {
                        if let clip = UIPasteboard.general.string, !clip.isEmpty {
                            text = clip
                        }
                    } label: {
                        Label("读取剪贴板", systemImage: "doc.on.clipboard")
                    }
                    .disabled(isRecognizing)
                }
            }
            .navigationTitle("文本识别")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isRecognizing)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    recognize()
                } label: {
                    Text("识别并记账")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRecognizing || trimmed.isEmpty)   // 识别中禁重复提交 + 空文本禁提交
                .padding()
                .background(.bar)
            }
            .overlay {
                if isRecognizing { recognizingOverlay }
            }
            .animation(.default, value: phase)
            // 无 Key 拦截：先于识别，直开最小 Key sheet（已确认约定 8：不指向 N07 我的页）。
            .alert("需要先配置 DeepSeek", isPresented: $showKeyBlockedAlert) {
                Button("去填写") { showingKeySheet = true }
                Button("取消", role: .cancel) { }
            } message: {
                Text("识别类记账要用到 DeepSeek。填入你的 API Key 即可，手动记账不受影响。")
            }
            // 失败提示：按 RecognitionError 分支给「转手动填写（带原文）」/「重试」/「取消」。
            .alert(failureTitle, isPresented: isFailedBinding, presenting: failedError) { error in
                if error.isRetryable {
                    Button("重试") { phase = .idle; retryToken += 1 }           // 经 onChange 重新识别
                }
                Button("转手动填写") { phase = .idle; showingManualEntry = true }
                Button("取消", role: .cancel) { phase = .idle }
            } message: { error in
                Text(failureMessage(for: error))
            }
            .sheet(isPresented: $showingKeySheet) {
                KeySetupSheet()
            }
            // 识别成功结果卡片（复用 TransactionEditor.edit + 折叠原文 + 改/删撤销）。
            // onDismiss：结果卡片关闭（完成回写 / 删除撤销 均触发）后 dismiss 识别页回记账页（验收 2/3）。
            // 用 onDismiss 而非 onChange：Transaction 是 @Model class 未声明 Equatable，onChange(of:) 编不过。
            .sheet(item: $resultTx, onDismiss: { dismiss() }) { tx in
                RecognitionResultCard(tx: tx, categories: categories)
            }
            // 转手动带原文（识别页输入原文预填备注，验收 6）。
            .sheet(isPresented: $showingManualEntry) {
                ManualEntryView(prefillNote: trimmed)
            }
            // 重试：alert 关闭动画结束后再触发识别，避免与 alert 消失争用 phase。
            .onChange(of: retryToken) { _, _ in
                recognize()
            }
        }
    }

    // MARK: - 识别中遮罩

    private var recognizingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("正在识别文本…")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("DeepSeek 提取金额与分类")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .transition(.opacity)
    }

    // MARK: - 识别动作

    private func recognize() {
        let input = trimmed
        guard !input.isEmpty else { return }                                    // CTA 已 disable，纯防御
        guard KeychainStore.shared.isConfigured else {                          // 无 Key 拦截：不进 Task
            showKeyBlockedAlert = true
            return
        }
        guard phase != .recognizing else { return }                             // 禁重复提交
        phase = .recognizing
        Task {
            do {
                let store = LedgerStore(modelContext)
                let tx = try await RecognitionEntry.recognizeAndSave(
                    text: input, categories: categories,
                    parser: parser, store: store, now: Date())
                phase = .idle
                resultTx = tx                                                   // 成功：弹结果卡片（复用 TransactionEditor.edit）
            } catch let error as RecognitionError {
                phase = .failed(error)
            } catch {
                // 落库意外（如 save 抛错）：回滚清除可能残留的 pending insert，守"失败不产生脏账"。
                modelContext.rollback()
                phase = .failed(.invalidResponse)
            }
        }
    }

    // MARK: - 失败态派生

    private var isFailedBinding: Binding<Bool> {
        Binding(
            get: { if case .failed = phase { return true } else { return false } },
            set: { if !$0 { phase = .idle } }
        )
    }

    private var failedError: RecognitionError? {
        if case let .failed(error) = phase { return error }
        return nil
    }

    private var failureTitle: String {
        switch failedError {
        case .noAmount:        return "没识别出金额"
        case .network:         return "网络连接失败"
        case .timeout:         return "识别超时"
        case .noKey:           return "需要先配置 DeepSeek"
        case .invalidResponse, .none: return "识别失败"
        }
    }

    private func failureMessage(for error: RecognitionError) -> String {
        switch error {
        case .noAmount:        return "原文已保留，可修改后重试（或稍后转手动填写）。"
        case .network:         return "请检查网络后重试。"
        case .timeout:         return "请求超时，请重试。"
        case .noKey:           return "识别类记账要用到 DeepSeek，请先填入 API Key。"
        case .invalidResponse: return "返回内容无法解析，请重试。"
        }
    }
}

/// 识别成功结果卡片（原型 §4.3 openResultCard）：复用 `TransactionEditor(.edit)` 呈现已入账的 tx——
/// 「完成」走 `makeUpdate` 回写、「删除这笔」= 撤销这笔入账。
///
/// 删除二次确认与 N01 `TransactionDetailView` 同构（`confirmationDialog` + 先 dismiss 再 delete，
/// 规避 SwiftData 以已删对象重建 editor 的悬垂读取，见 memory）。折叠原文经 `rawText` 注入。
/// tx 已入账故走 edit 语义（demo recognizeFlow 先 push bill 再 openResultCard，账单已存在）。
private struct RecognitionResultCard: View {
    let tx: Transaction
    let categories: [LedgerCategory]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirm = false

    private var store: LedgerStore { LedgerStore(modelContext) }

    var body: some View {
        TransactionEditor(
            mode: .edit(tx),
            categories: categories,
            onSave: EditorActions.makeUpdate(store: store, tx: tx),   // 「完成」= 回写；不碰 source/rawText/cardTail
            onDelete: { showingDeleteConfirm = true },                 // 「删除这笔」= 先二次确认
            rawText: tx.rawText                                        // 折叠原文 = 入账时落的用户原文
        )
        .confirmationDialog("删除这笔账单？", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                // 先 dismiss 再 delete：与 TransactionDetailView 同构，避免 sheet 以已删 tx 重建 editor（SwiftData 敏感）。
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
