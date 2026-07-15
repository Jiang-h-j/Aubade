import SwiftUI
import SwiftData

/// 语音入口的单一 fullScreenCover 驱动（避坑）：语音面板与"成功后复用的文本识别页"是先后两个全屏页，
/// 用两个独立 fullScreenCover(isPresented:) 同一事件里关一个开一个会因 SwiftUI 同时只允许一个 presentation
/// 而竞态卡住；改用单一 fullScreenCover(item:) + 换 item 在同一 presentation 内平滑切内容。
enum VoiceRoute: Identifiable {
    case panel                        // 语音面板（按住说话）
    case recognizing(spoken: String) // 转出文本 → 复用 TextRecognitionView 自动识别 → 结果卡片
    var id: String {
        switch self {
        case .panel:                 return "panel"
        case .recognizing(let s):    return "recognizing:\(s)"
        }
    }
}

/// 截图入口单一 fullScreenCover 驱动（照抄 VoiceRoute 避坑范式）：说明卡与"OCR 出文本后复用的识别页"
/// 是先后两个全屏页，换 item 在同一 presentation 内平滑切内容，规避两个独立 fullScreenCover 关一个开一个的竞态。
enum ScreenshotRoute: Identifiable {
    case intro                          // 截图识别说明卡（快捷指令讲解 + 相册选图）
    case recognizing(ocrText: String)   // OCR 出文本 → 复用 TextRecognitionView 自动识别 → 结果卡片
    var id: String {
        switch self {
        case .intro:                  return "intro"
        case .recognizing(let t):     return "recognizing:\(t)"
        }
    }
}

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
    @State private var editingTransaction: Transaction?
    @State private var voiceRoute: VoiceRoute?          // 语音单一 fullScreenCover 驱动（面板 → 复用识别页）
    @State private var showVoiceKeyBlockedAlert = false // 语音入口无 Key 拦截（对齐 demo startEntry）
    @State private var showingVoiceKeySheet = false     // 无 Key alert「去填写」→ 开 Key sheet
    @State private var screenshotRoute: ScreenshotRoute?      // 截图单一 fullScreenCover 驱动（说明卡 → 复用识别页）
    @State private var showScreenshotKeyBlockedAlert = false  // 截图入口无 Key 拦截（进说明卡前查 Key）
    @State private var showingScreenshotKeySheet = false      // 无 Key alert「去填写」→ 开 Key sheet

    #if DEBUG
    // DEBUG 运行时 mock 行为：调试菜单写、此处读，切换识别成功/无金额/网络失败等（TRD 03 §5）。
    @AppStorage(DebugMockSettings.behaviorKey) private var mockBehaviorRaw = MockTransactionParser.Behavior.success.rawValue
    // 语音 mock 行为：与文本 mock 分开一个 key，切成功/空结果/权限被拒/本机不可用。
    @AppStorage(DebugVoiceMockSettings.behaviorKey) private var voiceMockRaw = MockVoiceTranscriber.Behavior.success.rawValue
    // 截图 OCR mock 行为：与文本/语音分开一个 key，切成功/空结果/OCR 失败（TRD 02 §5）。
    @AppStorage(DebugScreenshotMockSettings.behaviorKey) private var screenshotMockRaw = MockTextRecognizer.Behavior.success.rawValue
    #endif

    /// 文本识别解析器注入：生产走 DeepSeekClient；DEBUG（模拟器/预览）走 mock。
    /// DEBUG 下 mock 行为由调试菜单经 @AppStorage 运行时切换（成功/无金额/网络失败/超时）。
    private var textParser: TransactionParsing {
        #if DEBUG
        let behavior = MockTransactionParser.Behavior(rawValue: mockBehaviorRaw) ?? .success
        return MockTransactionParser(behavior: behavior)
        #else
        return DeepSeekClient()
        #endif
    }

    /// 语音转文字 provider 注入：Release 用真实 SFSpeech（切片 02）；DEBUG 用 mock，行为由调试菜单切换。
    private func makeVoiceTranscriber() -> any VoiceTranscribing {
        #if DEBUG
        let behavior = MockVoiceTranscriber.Behavior(rawValue: voiceMockRaw) ?? .success
        let mock = MockVoiceTranscriber()
        mock.behavior = behavior
        return mock
        #else
        return SpeechVoiceTranscriber()
        #endif
    }

    /// 语音场景解析器：与文本入口分开——DEBUG 固定注入 .voiceSample（20/支出/"行"，验收 1），
    /// 不读文本 mock 的 @AppStorage，避免两入口互相污染（PRD §6）。Release 走同一 DeepSeekClient。
    private var voiceParser: TransactionParsing {
        #if DEBUG
        return MockTransactionParser(behavior: .voiceSample)
        #else
        return DeepSeekClient()
        #endif
    }

    /// 语音落库原文前缀（PRD 已确认约定 11，对齐 demo data.js:45）：`[语音转文字]\n"<口语原句>"`。
    /// parse 输入用纯口语，落库 rawText 用带前缀串，二者经 recognizeAndSave 的 text/rawText 分离。
    private func voiceRawText(spoken: String) -> String {
        "[语音转文字]\n\"\(spoken)\""
    }

    /// 截图 OCR provider 注入：Release 用真实 Vision 本机 OCR；DEBUG 用 mock，行为由调试菜单切换。
    private func makeTextRecognizer() -> any TextRecognizing {
        #if DEBUG
        let behavior = MockTextRecognizer.Behavior(rawValue: screenshotMockRaw) ?? .success
        let mock = MockTextRecognizer()
        mock.behavior = behavior
        return mock
        #else
        return VisionTextRecognizer()
        #endif
    }

    /// 截图场景解析器：与文本/语音入口分开——DEBUG 固定注入 .screenshotSample（88.5/支出/星巴克/食，验收 1），
    /// 不读文本 mock 的 @AppStorage，避免三入口互相污染（PRD §6）。Release 走同一 DeepSeekClient。
    private var screenshotParser: TransactionParsing {
        #if DEBUG
        return MockTransactionParser(behavior: .screenshotSample)
        #else
        return DeepSeekClient()
        #endif
    }

    /// 截图落库原文前缀（PRD 已确认约定 11，对齐 voiceRawText / demo data.js:44）：`[截图识别]\n<OCR 文本>`。
    /// parse 输入用纯 OCR 文本，落库 rawText 用带前缀串，二者经 recognizeAndSave 的 text/rawText 分离。
    private func screenshotRawText(ocrText: String) -> String {
        "[截图识别]\n\(ocrText)"
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
            // 语音单一 fullScreenCover：.panel 面板 →（成功回调换 item）.recognizing 复用文本识别页自动识别。
            // 同一 presentation 换 item，避免"关一个开一个"的 SwiftUI 时序竞态（验收 1）。
            .fullScreenCover(item: $voiceRoute) { route in
                switch route {
                case .panel:
                    VoiceCaptureView(transcriber: makeVoiceTranscriber()) { spoken in
                        voiceRoute = .recognizing(spoken: spoken)   // 转出文本 → 切复用识别页
                    }
                case .recognizing(let spoken):
                    // 复用 N03 整套：预置纯口语自动识别 → 识别中遮罩 → 入账(source=.voice) → 结果卡片/失败转手动。
                    // 结果卡片关闭时 TextRecognitionView 调 dismiss()，fullScreenCover 随 item 归 nil 回记账页。
                    TextRecognitionView(
                        parser: voiceParser,
                        categories: categories,
                        presetText: spoken,
                        source: .voice,
                        rawTextOverride: voiceRawText(spoken: spoken))
                }
            }
            // 截图单一 fullScreenCover：.intro 说明卡 →（OCR 出文本换 item）.recognizing 复用文本识别页自动识别。
            // 同一 presentation 换 item，避免"关一个开一个"的 SwiftUI 时序竞态（验收 1）。
            // 三个 fullScreenCover（文本/语音/截图）并存靠"入口互斥触发 + present 后盖住原页"保证同帧仅一个激活；
            // 后续若新增全屏入口需维持此互斥，防回归。
            .fullScreenCover(item: $screenshotRoute) { route in
                switch route {
                case .intro:
                    // 说明卡内 PhotosPicker 免权限选图 → 本机 OCR → onRecognized 交出文本 → 切复用识别页。
                    // 「演示」占位提示由说明卡内部自持（showDemoPlaceholder + .alert），因外层"敬请期待" alert
                    // 会被本全屏卡盖住，故不走外层。
                    ScreenshotIntakeSheet(recognizer: makeTextRecognizer()) { ocrText in
                        screenshotRoute = .recognizing(ocrText: ocrText)   // OCR 出文本 → 切复用识别页
                    }
                case .recognizing(let ocrText):
                    // 复用 N03 整套：预置 OCR 文本自动识别 → 识别中遮罩 → 入账(source=.screenshotAlbum) → 结果卡片/失败转手动。
                    // 结果卡片关闭时 TextRecognitionView 调 dismiss()，fullScreenCover 随 item 归 nil 回记账页。
                    TextRecognitionView(
                        parser: screenshotParser,
                        categories: categories,
                        presetText: ocrText,
                        source: .screenshotAlbum,
                        rawTextOverride: screenshotRawText(ocrText: ocrText))
                }
            }
            .sheet(item: $editingTransaction) { tx in
                editSheet(for: tx)
            }
            // 语音入口无 Key 拦截（复用 N03 文案范式；「去填写」开同一 KeySetupSheet）。
            .alert("需要先配置 DeepSeek", isPresented: $showVoiceKeyBlockedAlert) {
                Button("去填写") { showingVoiceKeySheet = true }
                Button("取消", role: .cancel) { }
            } message: {
                Text("语音记账要用到 DeepSeek。填入你的 API Key 即可，手动记账不受影响。")
            }
            .sheet(isPresented: $showingVoiceKeySheet) {
                KeySetupSheet()
            }
            // 截图入口无 Key 拦截（进说明卡前查 Key；「去填写」开同一 KeySetupSheet）。
            .alert("需要先配置 DeepSeek", isPresented: $showScreenshotKeyBlockedAlert) {
                Button("去填写") { showingScreenshotKeySheet = true }
                Button("取消", role: .cancel) { }
            } message: {
                Text("截图记账要用到 DeepSeek 解析识别出的文字。填入你的 API Key 即可，手动记账不受影响。")
            }
            .sheet(isPresented: $showingScreenshotKeySheet) {
                KeySetupSheet()
            }
        }
    }

    // MARK: - 四入口网格（2×2，仅手动可用）

    private var entryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            EntryButton(emoji: "📷", title: "截图识别") {
                // 对齐语音入口：先复用 N03 无 Key 拦截，有 Key 才进说明卡（卡内核心是「从相册选图」，无 Key 整卡无意义）。
                if KeychainStore.shared.isConfigured {
                    screenshotRoute = .intro
                } else {
                    showScreenshotKeyBlockedAlert = true
                }
            }
            EntryButton(emoji: "🎤", title: "语音记账") {
                // 对齐 demo startEntry：先复用 N03 无 Key 拦截，有 Key 才进语音面板。
                if KeychainStore.shared.isConfigured {
                    voiceRoute = .panel
                } else {
                    showVoiceKeyBlockedAlert = true
                }
            }
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
