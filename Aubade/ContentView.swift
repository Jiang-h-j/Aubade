import SwiftUI

/// App 根视图。按 `AppConfig.hasOnboarded` 分流：未完成首次引导进 `OnboardingView`，
/// 完成进底部四 Tab 主框架 `RootTabView`。
/// 保留 `ContentView` 名以免改动 `AubadeApp` 的引用点（容器注入与预置分类装载不变）。
/// 分流挂此处而非 `AubadeApp`：`AubadeApp.task` 的 seed/purge 与容器注入引导期也需先跑并保持不动。
struct ContentView: View {
    // 引导走完（含全跳过）内部置 true → body 重算自动切 RootTabView（默认落记账 Tab），无需手动导航。
    @AppStorage(AppConfig.hasOnboardedKey) private var hasOnboarded = AppConfig.hasOnboardedDefault

    var body: some View {
        if hasOnboarded {
            RootTabView()
        } else {
            OnboardingView()
        }
    }
}

#Preview {
    ContentView()
        .environment(DeepLinkRouter())
        .modelContainer(PersistenceController.makeInMemoryContainer())
}
