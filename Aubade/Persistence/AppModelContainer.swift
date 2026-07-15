import SwiftData

/// 全 App 唯一的 ModelContainer 持有者。in-app App Intents 路线：主 App 与后台唤醒的
/// perform() 共享同一实例（PRD 已确认约定 1），后台经它拿到与主 App 同一账本的 ModelContext。
///
/// 持有容器（let container）再取 mainContext，绝不链式 makeContainer().mainContext——
/// 容器被 ARC 释放会导致 insert/save SIGTRAP（见 memory swiftdata-dangling-context-crash）。
@MainActor
final class AppModelContainer {
    static let shared = AppModelContainer()
    let container: ModelContainer = PersistenceController.makeContainer()
    private init() {}
}
