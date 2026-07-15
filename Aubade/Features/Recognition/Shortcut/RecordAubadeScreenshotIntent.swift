import AppIntents
import SwiftData

/// "记录 Aubade 截图"后台动作（in-app，主 App target 内；PRD 已确认约定 1）。
/// perform() 在系统后台唤醒的主 App 进程内执行，共享 AppModelContainer；不弹前台 UI。
///
/// 薄壳：仅装配依赖 + 调 BackgroundIntakeService，后台链路全部逻辑在核心单元里（可脱框架单测）。
struct RecordAubadeScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "记录 Aubade 截图"
    static let description = IntentDescription("把截图交给 Aubade，后台识别并直接记一笔账。")
    static let openAppWhenRun = false   // 后台执行，不打开前台

    @Parameter(title: "截图")
    var image: IntentFile               // 快捷指令传入的图片文件

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = AppModelContainer.shared.container.mainContext   // 持有点已长期持有容器，安全取 context
        let categories = (try? context.fetch(FetchDescriptor<LedgerCategory>())) ?? []
        let service = BackgroundIntakeService(
            recognizer: VisionTextRecognizer(),
            parser: DeepSeekClient(),
            store: LedgerStore(context),
            categories: categories,
            notifier: NoOpNotifier(),                 // TODO(切片02)：换 UNUserNotificationCenterNotifier()
            now: { Date() },
            imageStore: NoOpFailedImageStore())        // TODO(切片02)：换 TemporaryImageStore()
        await service.intake(imageData: image.data)
        return .result()
    }
}
