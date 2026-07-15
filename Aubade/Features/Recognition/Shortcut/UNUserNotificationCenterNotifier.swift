import UserNotifications

/// 把 IntakeNotification 构造成真实本地通知（切片 02）。
/// 发送失败 / 无权限一律吞掉——绝不影响入账（约定 9）：入账已完成，通知只是"告诉一声"。
///
/// @MainActor 与协议 NotificationSending 隔离一致（只在 BackgroundIntakeService 调用链内被调）。
struct UNUserNotificationCenterNotifier: NotificationSending {
    /// userInfo key（AppDelegate 点击路由据此解析深链意图）。
    enum Key {
        static let kind = "kind"
        static let txID = "txID"
        static let imageRef = "imageRef"
        static let rawText = "rawText"
    }

    /// kind 取值（与 AppDelegate 解析对称）。
    enum Kind {
        static let success = "success"
        static let failure = "failure"
        static let missingKey = "missingKey"
    }

    func send(_ notification: IntakeNotification) async {
        let center = UNUserNotificationCenter.current()
        // 随首次发通知申请权限（后台入账成功/失败那一刻）；已决定则立即返回当前态。
        // 被拒 → 静默不发、不抛错：入账已完成，不崩溃、不误记（约定 9）。
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: Self.makeContent(for: notification),
            trigger: nil)                                   // trigger nil = 立即
        try? await center.add(request)
    }

    /// 纯函数：IntakeNotification → 通知内容（title/body/userInfo）。脱 UNUserNotificationCenter，供单测断言。
    static func makeContent(for notification: IntakeNotification) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        switch notification {
        case let .success(txID, amountText, categoryName, merchant):
            content.title = "已记一笔"
            // "¥88.50 · 食 · 星巴克"，分类/商户为 nil 或空串时省略（对齐 PRD §3 / 技术基线）。
            let suffix = [categoryName, merchant]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .map { " · \($0)" }
                .joined()
            content.body = "¥\(amountText)" + suffix
            content.userInfo = [Key.kind: Kind.success, Key.txID: txID.uuidString]
        case let .failure(imageRef, rawText):
            content.title = "没识别出这张截图"
            content.body = "点此补录这笔账。"
            content.userInfo = [
                Key.kind: Kind.failure,
                Key.imageRef: imageRef ?? "",
                Key.rawText: rawText ?? "",
            ]
        case .missingKey:
            content.title = "请先配置 DeepSeek Key"
            content.body = "截图记账要用到 DeepSeek，点此去配置。"
            content.userInfo = [Key.kind: Kind.missingKey]
        }
        return content
    }
}
