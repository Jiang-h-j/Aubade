import SwiftUI

/// 占位根视图。本片不实现任何用户可见记账/统计界面（→ N01/N02）。
/// DEBUG 构建下额外挂载临时调试入口，用于肉眼确认容器单点共享；Release 不含此入口。
struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sunrise.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Aubade")
                .font(.largeTitle.bold())
            Text("数据层已就绪")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            #if DEBUG
            NavigationLink {
                DebugMenuView()
            } label: {
                Label("调试菜单", systemImage: "hammer.fill")
            }
            .padding(.top, 24)
            #endif
        }
        .padding()
        .modifier(DebugNavigationWrapper())
    }
}

/// DEBUG 下用 NavigationStack 包裹以支持 NavigationLink；Release 下透传，避免多余容器。
private struct DebugNavigationWrapper: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        NavigationStack { content }
        #else
        content
        #endif
    }
}

#Preview {
    ContentView()
        .modelContainer(PersistenceController.makeInMemoryContainer())
}
