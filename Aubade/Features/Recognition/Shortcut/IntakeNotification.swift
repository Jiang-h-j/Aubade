import Foundation

/// 后台链路要发的通知意图（值类型，脱 UNUserNotificationCenter）。
/// 核心单元 BackgroundIntakeService 只产出"该发哪一类通知"，切片 02 的真实发送器据此构造系统通知。
enum IntakeNotification: Equatable {
    /// 入账成功：点通知 → 编辑这笔（切片 02 深链）。
    case success(transactionID: UUID, amountText: String, categoryName: String?, merchant: String?)
    /// 识别/解析失败：点通知 → 补录（带原图引用 + 原文带入）。OCR 本身失败时 rawText 为 nil。
    case failure(imageRef: String?, rawText: String?)
    /// 未配置 Key：点通知 → 去配置 Key。
    case missingKey
}

/// "发通知"的能力抽象。真实实现（UNUserNotificationCenter）在切片 02；单测注入 spy 断言发了哪类。
/// send 不抛错：通知权限被拒 / 发送失败绝不影响入账结果（PRD 已确认约定 9），真实实现内部吞掉发送失败。
/// @MainActor：核心单元 BackgroundIntakeService 是 @MainActor，发送器只在其调用链（主线程）被调用；
/// 标 @MainActor 而非 Sendable，spy/真实实现均可安全持有 MainActor 状态（Swift 6 并发安全）。
@MainActor
protocol NotificationSending {
    func send(_ notification: IntakeNotification) async
}

/// 失败原图临时留存抽象。真实实现（写盘 / 清理）见切片 02 TemporaryImageStore。
/// 成功入账不留存原图（imageRef 恒 nil，对齐 recognizeAndSave 不透传 imageRef）；仅失败分支调 save。
/// @MainActor：同 NotificationSending，只在 BackgroundIntakeService 调用链内被调。
@MainActor
protocol FailedImageStoring {
    /// 返回 imageRef（临时文件引用）；留存失败返回 nil。
    func save(_ imageData: Data) -> String?
}
