import SwiftUI

/// 底部四 Tab 标识。用可绑定 selection 而非无状态 TabView，为切片 03
/// 「最近记录『全部 ›』跳账单 Tab」预留跨 Tab 跳转能力（本片即引入绑定）。
enum AppTab: Hashable {
    case record   // 记账
    case ledger   // 账单
    case analytics // 统计
    case profile  // 我的
}

/// App 主框架：底部四 Tab（记账 · 账单 · 统计 · 我的），默认落「记账」（验收 8）。
/// 记账/账单为临时占位（切片 02/03 替换）；统计/我的为正式占位（本节点终态，N02/N07 才填）。
struct RootTabView: View {
    @State private var selectedTab: AppTab = .record

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordTabView(selection: $selectedTab)
                .tag(AppTab.record)
                .tabItem { Label("记账", systemImage: "pencil") }

            LedgerTabPlaceholder()
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

// MARK: - 临时占位（切片 03 替换为真实视图）

/// TODO(N01-03) 替换为账单 Tab 真实视图（流水列表 / 筛选 / 编辑删除）。
private struct LedgerTabPlaceholder: View {
    var body: some View {
        ContentUnavailableView("账单", systemImage: "list.bullet",
                               description: Text("账单列表即将上线"))
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

/// 我的 Tab 正式占位：N07 才提供设置功能。
/// DEBUG 构建下把 N00 的调试入口（原 `ContentView` 内）迁到这里；用 `NavigationStack`
/// 包裹以支持 `NavigationLink`（仅 DEBUG 需要）。Release 直接展示占位内容。
struct ProfilePlaceholderView: View {
    var body: some View {
        #if DEBUG
        NavigationStack {
            List {
                Section {
                    Text("设置功能即将在后续版本提供")
                        .foregroundStyle(.secondary)
                }
                Section("开发者") {
                    NavigationLink {
                        DebugMenuView()
                    } label: {
                        Label("调试菜单", systemImage: "hammer.fill")
                    }
                }
            }
            .navigationTitle("我的")
        }
        #else
        ContentUnavailableView("我的", systemImage: "person",
                               description: Text("设置功能即将在后续版本提供"))
        #endif
    }
}

#Preview {
    RootTabView()
        .modelContainer(PersistenceController.makeInMemoryContainer())
}
