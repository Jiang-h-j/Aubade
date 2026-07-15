import AppIntents

/// App Shortcuts 提供者：让"记录 Aubade 截图"动作出现在快捷指令 App 与 Spotlight，
/// 用户可把它接到"截图后自动运行"的自动化里（真机接线属用户自测）。
struct AubadeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordAubadeScreenshotIntent(),
            phrases: ["用 \(.applicationName) 记这张截图"],
            shortTitle: "记录截图",
            systemImageName: "camera.viewfinder")
    }
}
