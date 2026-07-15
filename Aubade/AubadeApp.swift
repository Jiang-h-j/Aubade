import SwiftUI
import SwiftData

@main
struct AubadeApp: App {
    // 共享持有点：主 App 与后台 App Intent（N06）用同一容器实例（见 AppModelContainer）。
    let container = AppModelContainer.shared.container
    // 承接本地通知点击深链（N06 切片 02）；delegate 内 UNUserNotificationCenter.delegate 挂载。
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AppDelegate.router)                     // 深链意图注入根视图（RootTabView 消费）
                .task {
                    PresetCategories.seedIfNeeded(container.mainContext)
                    TemporaryImageStore().purgeAll()                 // 清上次残留失败原图（不做跨启动补录队列）
                }
        }
        .modelContainer(container)
    }
}
