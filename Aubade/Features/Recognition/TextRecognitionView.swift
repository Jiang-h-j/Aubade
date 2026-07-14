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
    /// - rawText 落用户输入的原文（不是 mock 的内部 raw）。
    @discardableResult
    static func recognizeAndSave(text: String,
                                 categories: [LedgerCategory],
                                 parser: TransactionParsing,
                                 store: LedgerStore,
                                 now: Date) async throws -> Transaction {
        let parsed = try await parser.parse(text: text, categories: categories)
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
            source: .text,
            rawText: text)
    }
}

/// 文本识别页（原型 §4.3 openTextInput）：粘贴框 + 读剪贴板 + 识别并记账。
///
/// 本片终态：识别成功即入账并 dismiss 回记账页（最近记录 +1）；
/// 结果卡片、失败转手动带原文、DEBUG 运行时 mock 开关 → 切片 03。
struct TextRecognitionView: View {
    let parser: TransactionParsing        // 注入：生产 DeepSeekClient / 测试预览 Mock
    let categories: [LedgerCategory]      // RecordTabView 的 @Query 传入

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var phase: RecognitionPhase = .idle
    @State private var showingKeySheet = false
    @State private var showKeyBlockedAlert = false

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
            // 失败提示：按 RecognitionError 分支文案（转手动 / 重试 → 切片 03）。
            .alert(failureTitle, isPresented: isFailedBinding, presenting: failedError) { _ in
                Button("好", role: .cancel) { phase = .idle }
            } message: { error in
                Text(failureMessage(for: error))
            }
            .sheet(isPresented: $showingKeySheet) {
                KeySetupSheet()
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
                try await RecognitionEntry.recognizeAndSave(
                    text: input, categories: categories,
                    parser: parser, store: store, now: Date())
                phase = .idle
                dismiss()                                                       // 本片：回记账页，最近记录 +1
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
