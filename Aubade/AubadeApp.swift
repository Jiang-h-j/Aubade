import SwiftUI
import SwiftData

@main
struct AubadeApp: App {
    // 共享持有点：主 App 与后台 App Intent（N06）用同一容器实例（见 AppModelContainer）。
    let container = AppModelContainer.shared.container

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { PresetCategories.seedIfNeeded(container.mainContext) }
        }
        .modelContainer(container)
    }
}
