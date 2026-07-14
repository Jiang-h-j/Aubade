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
/// 记账/账单为真实视图（切片 02/03）；统计/我的为正式占位（本节点终态，N02/N07 才填）。
struct RootTabView: View {
    @State private var selectedTab: AppTab = .record

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordTabView(selection: $selectedTab)
                .tag(AppTab.record)
                .tabItem { Label("记账", systemImage: "pencil") }

            LedgerTabView()
                .tag(AppTab.ledger)
                .tabItem { Label("账单", systemImage: "list.bullet") }

            AnalyticsPlaceholderView()
                .tag(AppTab.analytics)
                .tabItem { Label("统计", systemImage: "chart.bar") }

            ProfilePlaceholderView()
                .tag(AppTab.profile)
                .tabItem { Label("我的", systemImage: "person") }
        }
    }
}

// MARK: - 正式占位（本节点终态）

/// 统计 Tab 正式占位：N02 才提供实际功能。
struct AnalyticsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView("统计", systemImage: "chart.bar",
                               description: Text("统计功能即将在后续版本提供"))
    }
}

/// 我的 Tab：顶部剩余总额 + 录入/调整初始总额（N02 M6）；完整设置（预算/Key/分类）→ N07。
/// DEBUG 构建下把 N00 的调试入口（原 `ContentView` 内）迁到这里；用 `NavigationStack`
/// 包裹以支持 `NavigationLink`（仅 DEBUG 需要）。Release 也用 `NavigationStack` 承载初始总额区块。
struct ProfilePlaceholderView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var baselines: [BalanceBaseline]
    @Query private var allTransactions: [Transaction]

    @State private var showingInitSheet = false

    private var store: LedgerStore { LedgerStore(modelContext) }

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

#Preview {
    RootTabView()
        .modelContainer(PersistenceController.makeInMemoryContainer())
}
