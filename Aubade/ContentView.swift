import SwiftUI

/// App 根视图。切片 01 起从 N00 占位页换为底部四 Tab 主框架 `RootTabView`。
/// 保留 `ContentView` 名以免改动 `AubadeApp` 的引用点（容器注入与预置分类装载不变）。
/// 原 DEBUG 调试入口已迁入 `ProfilePlaceholderView`（我的 Tab）。
struct ContentView: View {
    var body: some View {
        RootTabView()
    }
}

#Preview {
    ContentView()
        .environment(DeepLinkRouter())
        .modelContainer(PersistenceController.makeInMemoryContainer())
}
