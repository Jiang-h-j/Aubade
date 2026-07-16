import SwiftUI
import SwiftData

/// 底部四 Tab 标识。用可绑定 selection 而非无状态 TabView，为切片 03
/// 「最近记录『全部 ›』跳账单 Tab」预留跨 Tab 跳转能力（本片即引入绑定）。
enum AppTab: Hashable {
    case record   // 记账
    case ledger   // 账单
    case analytics // 统计
    case profile  // 我的
}

/// App 主框架：底部四 Tab（记账 · 账单 · 统计 · 我的），默认落「记账」（验收 8）。
/// 记账/账单/统计为真实视图；我的为正式占位（顶部剩余总额已接，完整设置 N07 才填）。
struct RootTabView: View {
    @State private var selectedTab: AppTab = .record
    // 深链意图来源（N06 切片 02）：通知点击 → AppDelegate 写 router.pending → 此处消费 → 切记账 Tab + 下传。
    @Environment(DeepLinkRouter.self) private var router
    // 待 RecordTabView 承接的深链意图；消费后由 RecordTabView 回置 nil（防重复触发）。
    @State private var pendingDeepLink: DeepLinkIntent?

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordTabView(selection: $selectedTab, deepLink: $pendingDeepLink)
                .tag(AppTab.record)
                .tabItem { Label("记账", systemImage: "pencil") }

            LedgerTabView()
                .tag(AppTab.ledger)
                .tabItem { Label("账单", systemImage: "list.bullet") }

            AnalyticsTabView(selection: $selectedTab)
                .tag(AppTab.analytics)
                .tabItem { Label("统计", systemImage: "chart.bar") }

            ProfilePlaceholderView()
                .tag(AppTab.profile)
                .tabItem { Label("我的", systemImage: "person") }
        }
        // 深链承接：切记账 Tab + 把意图交给 RecordTabView。收到后清 router.pending，避免重复。
        .onChange(of: router.pending) { _, intent in
            consumeDeepLink(intent)
        }
        // 冷启动/被杀态时序：通知点击可能在订阅前就写入 router.pending，.onChange 不对"初始已有值"触发，
        // 故首个 task 也消费一次（消费后置 nil，与 onChange 分支同一路径，防双触发）。
        .task {
            consumeDeepLink(router.pending)
        }
    }

    private func consumeDeepLink(_ intent: DeepLinkIntent?) {
        guard let intent else { return }
        selectedTab = .record
        pendingDeepLink = intent
        router.pending = nil
    }
}

// MARK: - 正式占位（本节点终态）

/// 我的 Tab：顶部剩余总额 + 录入/调整初始总额（N02 M6）；完整设置（预算/Key/分类）→ N07。
/// DEBUG 构建下把 N00 的调试入口（原 `ContentView` 内）迁到这里；用 `NavigationStack`
/// 包裹以支持 `NavigationLink`（仅 DEBUG 需要）。Release 也用 `NavigationStack` 承载初始总额区块。
struct ProfilePlaceholderView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var baselines: [BalanceBaseline]
    @Query private var allTransactions: [Transaction]
    @Query private var budgets: [Budget]
    // 预置分类只读展示：isPreset==true，按 sortOrder 升序（与 LedgerStore.presetCategories 同序）。
    @Query(filter: #Predicate<LedgerCategory> { $0.isPreset == true },
           sort: \LedgerCategory.sortOrder) private var presetCategories: [LedgerCategory]

    @State private var showingInitSheet = false
    // 非 nil → 打开对应周期的预算设置 sheet。
    @State private var editingBudgetPeriod: BudgetPeriodType?
    @State private var showingKeySheet = false
    // Key 是否已配置的本地镜像：KeySetupSheet 无完成回调，靠 .sheet(onDismiss:) 重读刷新。
    @State private var keyConfigured = KeychainStore.shared.isConfigured

    /// 超支提示阈值（N07 切片 01）：与统计页共享同一 UserDefaults key，改动后统计页即时重算。
    @AppStorage(AppConfig.overspendThresholdKey) private var overspendThreshold = AppConfig.overspendThresholdDefault

    private var store: LedgerStore { LedgerStore(modelContext) }

    /// 当前某周期预算：写侧唯一化，first 即唯一值（同 AnalyticsTabView 读侧范式）。
    private func currentBudget(_ type: BudgetPeriodType) -> Budget? {
        budgets.first { $0.periodType == type }
    }

    /// 当前有效基线：取 establishedAt 最新一条（防御多条并存）。
    private var currentBaseline: BalanceBaseline? {
        baselines.max { $0.establishedAt < $1.establishedAt }
    }

    private var remaining: Decimal? {
        BalanceCalculator.remaining(transactions: allTransactions, baseline: currentBaseline)
    }

    var body: some View {
        NavigationStack {
            List {
                balanceSection
                budgetSection
                thresholdSection
                keySection
                categorySection
                #if DEBUG
                Section("开发者") {
                    NavigationLink {
                        DebugMenuView()
                    } label: {
                        Label("调试菜单", systemImage: "hammer.fill")
                    }
                }
                #endif
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showingInitSheet) {
                InitialBalanceSheet(current: currentBaseline?.initialAmount) { amount in
                    try? store.setBalanceBaseline(initialAmount: amount, establishedAt: Date())
                }
            }
            .sheet(item: $editingBudgetPeriod) { period in
                BudgetEditSheet(
                    periodType: period,
                    current: currentBudget(period)?.amount,
                    onSave: { amount in try? store.setBudget(periodType: period, amount: amount) },
                    onClear: { for b in budgets where b.periodType == period { try? store.delete(b) } })
            }
            // KeySetupSheet 无完成回调，关闭时重读 Keychain 刷新状态行。
            .sheet(isPresented: $showingKeySheet, onDismiss: { keyConfigured = KeychainStore.shared.isConfigured }) {
                KeySetupSheet()
            }
            // 兜底跨路径刷新：若在别处（如 N03 识别拦截流程）配过 Key，切回我的页时同步状态行。
            .onAppear { keyConfigured = KeychainStore.shared.isConfigured }
        }
    }

    private var balanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("剩余总额（所有账户合计）")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(remaining.map { "¥" + AmountFormat.plainString($0) } ?? "未设置")
                    .font(.system(size: 32, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(remaining == nil ? .secondary : .primary)
                Button(remaining == nil ? "录入初始总额" : "调整初始总额") {
                    showingInitSheet = true
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
    }

    /// 超支提示阈值（N07 切片 01）：Stepper 50~100 步进 5，整数百分比无键盘校验负担、范围天然受约束。
    private var thresholdSection: some View {
        Section {
            Stepper(value: $overspendThreshold,
                    in: AppConfig.overspendThresholdRange,
                    step: AppConfig.overspendThresholdStep) {
                HStack {
                    Text("超支提示阈值")
                    Spacer()
                    Text("\(overspendThreshold)%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("预算提醒")
        } footer: {
            Text("支出达到预算的该比例时，统计页预算条转为「接近」提醒。默认 80%。")
        }
    }

    // MARK: - 预算设置

    private var budgetSection: some View {
        Section("预算设置") {
            budgetRow(.weekly, "周预算")
            budgetRow(.monthly, "月预算")
        }
    }

    private func budgetRow(_ type: BudgetPeriodType, _ title: String) -> some View {
        Button {
            editingBudgetPeriod = type
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if let b = currentBudget(type) {
                    Text("¥" + AmountFormat.plainString(b.amount))
                        .foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Text("未设置").foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 智能识别（DeepSeek Key 状态行）

    private var keySection: some View {
        Section("智能识别") {
            Button {
                showingKeySheet = true
            } label: {
                HStack {
                    Text("DeepSeek API Key").foregroundStyle(.primary)
                    Spacer()
                    if keyConfigured {
                        Label("已配置", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).labelStyle(.titleAndIcon)
                    } else {
                        HStack(spacing: 2) {
                            Text("去填写").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 分类（预置，只读）

    private var categorySection: some View {
        Section {
            categoryTags(.expense, "支出")
            categoryTags(.income, "收入")
        } header: {
            Text("分类（预置）")
        }
    }

    /// 只读标签流：某方向的预置分类名铺成自适应换行的 capsule 标签，无点击、无增删改入口。
    private func categoryTags(_ direction: TransactionDirection, _ label: String) -> some View {
        let names = presetCategories.filter { $0.direction == direction }.map(\.name)
        return VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8, alignment: .leading)],
                      alignment: .leading, spacing: 8) {
                ForEach(names, id: \.self) { name in
                    Text(name)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.background.secondary, in: Capsule())
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// 录入/调整初始总额 sheet：数字输入 → `Decimal(string:)` 校验 → 回调写库。
/// 只做初始总额一项（TRD 不越界 N07）。金额纯 `Decimal` 解析，不经 `Double`。
private struct InitialBalanceSheet: View {
    let current: Decimal?
    let onSave: (Decimal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""

    /// 解析后的有效金额：非空、可转 Decimal、且 >= 0。
    /// 显式 posix locale 钉死小数点为 `.`，避免逗号小数分隔地区把 decimalPad 输入解析错。
    private var parsedAmount: Decimal? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")),
              value >= 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例如 12345", text: $input)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("你现在所有账户加起来大约有多少钱（元）")
                } footer: {
                    Text("之后每记一笔收支，剩余总额会自动加减。")
                }
            }
            .navigationTitle("设置初始总额")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let amount = parsedAmount {
                            onSave(amount)
                            dismiss()
                        }
                    }
                    .disabled(parsedAmount == nil)
                }
            }
            .onAppear {
                // 预填用无分组符纯数字串（NSDecimalNumber.stringValue），保证能被 Decimal(string:) 回读；
                // 千分位串（含逗号）会导致 decimalPad 回填后解析失败。
                if let current { input = NSDecimalNumber(decimal: current).stringValue }
            }
        }
    }
}

// `.sheet(item:)` 需要 Identifiable：rawValue（weekly/monthly）天然唯一，仅本片 UI 需要，不改模型语义。
extension BudgetPeriodType: Identifiable {
    var id: String { rawValue }
}

/// 预算设置 sheet：填周/月预算或清空。与 `InitialBalanceSheet` 校验范式相同（posix Decimal 解析），
/// 但预算须 > 0（0 等于没预算，走清空而非存 0）；带 periodType 语义标题与清空按钮，故各自内联不共类。
private struct BudgetEditSheet: View {
    let periodType: BudgetPeriodType
    let current: Decimal?
    let onSave: (Decimal) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""

    /// 解析后的有效金额：非空、可转 Decimal、且 > 0（预算 0 无意义，应走清空）。
    /// 显式 posix locale 钉死小数点为 `.`，避免逗号小数分隔地区把 decimalPad 输入解析错。
    private var parsedAmount: Decimal? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")),
              value > 0 else { return nil }
        return value
    }

    private var title: String { periodType == .weekly ? "设置周预算" : "设置月预算" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例如 800", text: $input)
                        .keyboardType(.decimalPad)
                } header: {
                    Text(periodType == .weekly ? "每周计划花多少（元）" : "每月计划花多少（元）")
                } footer: {
                    Text("统计页会按这个额度显示进度与剩余。")
                }
                if current != nil {
                    Section {
                        Button("清空预算", role: .destructive) {
                            onClear()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let amount = parsedAmount {
                            onSave(amount)
                            dismiss()
                        }
                    }
                    .disabled(parsedAmount == nil)
                }
            }
            .onAppear {
                if let current { input = NSDecimalNumber(decimal: current).stringValue }
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(DeepLinkRouter())
        .modelContainer(PersistenceController.makeInMemoryContainer())
}
