import UIKit
import UserNotifications

/// 深链意图（通知点击 → 路由目标）。
enum DeepLinkIntent: Equatable {
    case openTransaction(UUID)                              // 成功通知 → 结果卡片（可改/删/看原文）
    case manualEntry(rawText: String?, imageRef: String?)  // 失败通知 → 手动补录带原文/原图
    case configureKey                                      // 无 Key 通知 → Key 配置
}

/// 观察型单例：AppDelegate 收到点击写入 pending；根视图订阅并消费后置 nil。
@Observable @MainActor
final class DeepLinkRouter {
    var pending: DeepLinkIntent?
}

/// 承接本地通知点击 → 路由深链意图。用 @UIApplicationDelegateAdaptor 挂到 AubadeApp。
///
/// 只做通知交付/点击这一件事：SwiftData / 业务逻辑全不碰，路由目标由根视图消费 router.pending 决定。
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// 全 App 唯一深链路由；根视图订阅，delegate 点击回调写入。
    static let router = DeepLinkRouter()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// 点击通知 → 解析 userInfo → 写路由意图。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if let intent = Self.intent(from: response.notification.request.content.userInfo) {
            Self.router.pending = intent
        }
    }

    /// 前台也展示横幅：演示按钮在前台运行（ScreenshotIntakeSheet 内），iOS 默认抑制前台通知，
    /// 不实现此方法则「点演示亲眼看到弹通知」（验收 1）在前台看不到横幅。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// 纯函数：通知 userInfo → 深链意图。脱 UNNotification，供单测直接构造 dict 断言映射。
    static func intent(from userInfo: [AnyHashable: Any]) -> DeepLinkIntent? {
        switch userInfo[UNUserNotificationCenterNotifier.Key.kind] as? String {
        case UNUserNotificationCenterNotifier.Kind.success:
            guard let raw = userInfo[UNUserNotificationCenterNotifier.Key.txID] as? String,
                  let id = UUID(uuidString: raw) else { return nil }
            return .openTransaction(id)
        case UNUserNotificationCenterNotifier.Kind.failure:
            // 空串视作 nil（发送侧用空串占位 optional，见 makeContent）。
            let rawText = (userInfo[UNUserNotificationCenterNotifier.Key.rawText] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let imageRef = (userInfo[UNUserNotificationCenterNotifier.Key.imageRef] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .manualEntry(rawText: rawText, imageRef: imageRef)
        case UNUserNotificationCenterNotifier.Kind.missingKey:
            return .configureKey
        default:
            return nil
        }
    }
}
