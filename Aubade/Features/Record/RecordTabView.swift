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

/// 失败通知深链补录的 sheet 载荷（N06 切片 02）：携带原文 + 原图引用，`sheet(item:)` 驱动。
struct DeepLinkManualEntry: Identifiable {
    let id = UUID()
    let rawText: String?
    let imageRef: String?
}

/// 记账 Tab 真实视图（原型 §4.2），替换切片 01 的 `RecordTabPlaceholder`。
///
/// 组成：顶部「今日已记 N 笔」chip、四入口网格（仅手动可用，余三占位提示）、
/// 「最近记录」最近 4 笔 + 「全部 ›」跳账单 Tab。跨 Tab 跳转经 `@Binding selection` 直传（TRD §82）。
struct RecordTabView: View {
    /// 跨 Tab 跳转能力：「全部 ›」切到账单 Tab。由 RootTabView 传入 selectedTab 绑定。
    @Binding var selection: AppTab
    /// 通知点击深链意图（N06 切片 02）：RootTabView 消费 router 后下传；本视图承接后回置 nil 防重复。
    @Binding var deepLink: DeepLinkIntent?

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
    @State private var pendingDelete: Transaction?      // 最近记录左滑删除的二次确认目标（对齐账单页 pendingDelete）
    @State private var voiceRoute: VoiceRoute?          // 语音单一 fullScreenCover 驱动（面板 → 复用识别页）
    @State private var showVoiceKeyBlockedAlert = false // 语音入口无 Key 拦截（对齐 demo startEntry）
    @State private var showingVoiceKeySheet = false     // 无 Key alert「去填写」→ 开 Key sheet
    @State private var screenshotRoute: ScreenshotRoute?      // 截图单一 fullScreenCover 驱动（说明卡 → 复用识别页）
    @State private var showScreenshotKeyBlockedAlert = false  // 截图入口无 Key 拦截（进说明卡前查 Key）
    @State private var showingScreenshotKeySheet = false      // 无 Key alert「去填写」→ 开 Key sheet
    // 深链落点状态（N06 切片 02）：三类通知点击各自的呈现。
    @State private var deepLinkResultTx: Transaction?         // 成功通知 → 独立结果 sheet（注 onDelete+rawText，不动最近记录 editSheet）
    @State private var deepLinkManualEntry: DeepLinkManualEntry?  // 失败通知 → 手动补录带原文/原图
    @State private var showingDeepLinkKeySheet = false        // 无 Key 通知 → Key 配置

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

    /// 失败补录预填备注：把失败通知带回的 rawText（`[快捷指令]\n<OCR 文本>`）去掉首行前缀，只留 OCR 文本。
    /// rawText 为 nil（OCR 本身失败无文本）→ 返回 nil，备注不预填。
    static func prefillNote(fromRawText rawText: String?) -> String? {
        guard let rawText else { return nil }
        if rawText.hasPrefix("[快捷指令]\n") {
            return String(rawText.dropFirst("[快捷指令]\n".count))
        }
        return rawText
    }

    /// 「演示」按钮：真跑一遍后台核心单元（复用切片 01 BackgroundIntakeService）——
    /// 模拟器/没配快捷指令时，点一下亲眼看到"识别→入账→弹真通知→点通知跳落点"整条主链路（验收 1）。
    /// 依赖注入集中在此（对齐 makeTextRecognizer/screenshotParser 已在此），说明卡只管"点了演示"。
    /// DEBUG：OCR/解析走 mock（按调试菜单行为切成功/失败）；Release：走真实 Vision + DeepSeek（真图片由快捷指令传，演示传空图走失败分支）。
    @MainActor
    private func runBackgroundDemo() async {
        let service = BackgroundIntakeService(
            recognizer: makeTextRecognizer(),          // DEBUG=mock（按调试菜单）/ Release=Vision
            parser: screenshotParser,                  // DEBUG=.screenshotSample 定值 / Release=DeepSeek
            store: LedgerStore(modelContext),
            categories: categories,
            notifier: UNUserNotificationCenterNotifier(),   // 演示也弹真通知，可点击验证深链
            now: { Date() },
            imageStore: TemporaryImageStore())
        // DEBUG OCR mock 不解码图片，传占位空 Data 即可；Release 演示无真图 → 走 OCR 失败分支（弹失败通知）。
        await service.intake(imageData: Data())
    }

    /// 承接深链意图（通知点击）：成功→独立结果 sheet / 失败→补录带原文原图 / 无 Key→Key 配置。
    /// 消费后回置绑定 nil，防重复触发（RootTabView onChange + task 双入口已保证同一意图只下传一次）。
    private func consumeDeepLink(_ intent: DeepLinkIntent?) {
        guard let intent else { return }
        switch intent {
        case .openTransaction(let id):
            // 按 id 取回 tx；取不到（已被删）则静默忽略。
            let all = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
            deepLinkResultTx = all.first { $0.id == id }
        case let .manualEntry(rawText, imageRef):
            deepLinkManualEntry = DeepLinkManualEntry(rawText: rawText, imageRef: imageRef)
        case .configureKey:
            showingDeepLinkKeySheet = true
        }
        deepLink = nil
    }

    /// 今日已记笔数：createdAt 落在今天。
    private var todayCount: Int {
        allTransactions.filter { Calendar.current.isDateInToday($0.createdAt) }.count
    }

    private var recentFour: [Transaction] {
        Array(recentTransactions.prefix(4))
    }

    /// 最近记录单行固定高度：List 嵌在整页 ScrollView 内无法自适应内容高、会塌陷，需按「行数 × 单行高」定死高度。
    /// 取值来源：右侧文字块 `.body`(≈22) + spacing 2 + `.caption`(≈16) ≈ 40，比左侧 emoji 圆 frame 36 高，取 40；
    /// 加 `RecentTransactionRow` 上下 `.padding(.vertical, 10)` = 20，合计 60。subtitle `.lineLimit(1)` 保证单行。
    /// 脆弱点：依赖「行恒为单行定高」，若日后行内容可换行或 Dynamic Type 大字号放大，固定高会裁切/留白，须改测量/动态算高方案。
    private let recentRowHeight: CGFloat = 60

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
                    // 「演示」按钮经 onDemo 真跑一遍后台链路（依赖注入集中在 RecordTabView.runBackgroundDemo）。
                    ScreenshotIntakeSheet(recognizer: makeTextRecognizer()) { ocrText in
                        screenshotRoute = .recognizing(ocrText: ocrText)   // OCR 出文本 → 切复用识别页
                    } onDemo: {
                        await runBackgroundDemo()
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
            // 深链承接（N06 切片 02）：RootTabView 把通知点击意图经 $deepLink 下传，此处分流到三类落点。
            // onChange 覆盖"运行中收到点击"；首个 task 覆盖"冷启动订阅前已有值"（RootTabView 已按此双入口下传）。
            .onChange(of: deepLink) { _, intent in
                consumeDeepLink(intent)
            }
            .task {
                consumeDeepLink(deepLink)
            }
            // 成功通知落点：独立结果 sheet（注入 onDelete+rawText，可改/删/看原文，验收 3）。
            // 独立于最近记录的 editSheet，不给后者添删除/原文，守验收 10（不污染既有入口）。
            .sheet(item: $deepLinkResultTx) { tx in
                DeepLinkResultSheet(tx: tx, categories: categories)
            }
            // 失败通知落点：手动补录带原文（去 [快捷指令] 前缀预填备注）+ 原图（据 imageRef 取回展示）。
            .sheet(item: $deepLinkManualEntry) { entry in
                ManualEntryView(
                    prefillNote: Self.prefillNote(fromRawText: entry.rawText),
                    prefillImageRef: entry.imageRef)
            }
            // 无 Key 通知落点：开 Key 配置（复用 KeySetupSheet）。
            .sheet(isPresented: $showingDeepLinkKeySheet) {
                KeySetupSheet()
            }
            // 最近记录左滑删除的二次确认（文案/结构照抄账单页 LedgerTabView:52-58）。
            // 删除走页面级 confirmationDialog、不在 sheet 内触发，与账单页同构，无 SwiftData 悬垂风险。
            .confirmationDialog("删除这笔账单？", isPresented: deleteConfirmBinding,
                                titleVisibility: .visible, presenting: pendingDelete) { tx in
                Button("删除", role: .destructive) { delete(tx) }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: { _ in
                Text("删除后无法恢复")
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
                // List（非手搓 VStack）才能挂原生 .swipeActions；但 List 自带滚动，直接塞进整页 ScrollView 会双滚动 +
                // 高度塌陷。故 .scrollDisabled(true) 关掉 List 自身滚动交给外层 ScrollView，并用固定 .frame(height:) 撑开高度。
                // .scrollContentBackground(.hidden) 消 List 默认背景，外层保留原圆角容器维持「卡片包一组行」观感。
                List {
                    ForEach(recentFour) { tx in
                        Button {
                            editingTransaction = tx
                        } label: {
                            RecentTransactionRow(tx: tx)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = tx
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: CGFloat(recentFour.count) * recentRowHeight)
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
        // 落库逻辑走共享 EditorActions，与账单页列表进编辑单一来源。编辑 sheet 不注 onDelete：
        // 删除走最近记录行的左滑（swipeActions + 页面级 confirmationDialog），不在编辑 sheet 内触发。
        return TransactionEditor(
            mode: .edit(tx),
            categories: categories,
            onSave: EditorActions.makeUpdate(store: store, tx: tx)
        )
    }

    // MARK: - 最近记录删除（照抄账单页 LedgerTabView，走共享 EditorActions.makeDelete）

    /// confirmationDialog 的 Bool 绑定：pendingDelete 非 nil 即弹；关闭时清空。
    private var deleteConfirmBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })
    }

    private func delete(_ tx: Transaction) {
        EditorActions.makeDelete(store: LedgerStore(modelContext), tx: tx)()
        pendingDelete = nil
    }
}

// MARK: - 子视图

/// 成功通知深链结果卡片（N06 切片 02）：复用 `TransactionEditor(.edit)` 呈现已入账的截图快捷指令账单——
/// 可改（makeUpdate 回写）/ 可删（二次确认 + makeDelete）/ 看原文（rawText 折叠区），满足验收 3。
///
/// 独立于 RecordTabView 最近记录的 editSheet：那处不注 onDelete/rawText，此处才注，避免给最近记录编辑
/// 添出删除/原文（守验收 10 不污染既有入口）。删除二次确认与 RecognitionResultCard 同构
/// （confirmationDialog + 先 dismiss 再 delete，规避 SwiftData 以已删对象重建 editor 的悬垂读取）。
private struct DeepLinkResultSheet: View {
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
            rawText: tx.rawText                                        // 折叠原文 = 入账时落的带 [快捷指令] 前缀原文
        )
        .confirmationDialog("删除这笔账单？", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                // 先 dismiss 再 delete：避免 sheet 以已删 tx 重建 editor（SwiftData 敏感，见 memory）。
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
