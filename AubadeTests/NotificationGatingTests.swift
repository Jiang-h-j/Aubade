import XCTest
@testable import Aubade

/// TRD 04 验证点：通知总开关 gating 判定 `UNUserNotificationCenterNotifier.notificationsEnabled(_:)`（N07 切片 04）。
///
/// `send` 真发通知依赖 UNUserNotificationCenter（系统），单测覆盖 gating 判定即可：
/// "关时 send 提前 return 不发"由判定正确 + 代码路径审阅保证，端到端由 DEBUG 演示肉眼验。
/// 注入独立 `UserDefaults(suiteName:)`，不污染 .standard（照 OnboardingRoutingTests / StatisticsAggregatorTests 范式）。
final class NotificationGatingTests: XCTestCase {

    func testNotificationsEnabledDefaultsTrueWhenUnset() throws {
        let suite = "test.NotificationGating.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        // 未设值（没配过）→ 默认 true（开）：不用 bool(forKey:)，否则"没配过"会退化成默认关。
        XCTAssertTrue(UNUserNotificationCenterNotifier.notificationsEnabled(defaults))
    }

    func testNotificationsEnabledFalseWhenTurnedOff() throws {
        let suite = "test.NotificationGating.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        // 用户关开关 → false → send 开头 guard 提前 return（不发通知，入账不受影响）。
        defaults.set(false, forKey: AppConfig.notificationsEnabledKey)
        XCTAssertFalse(UNUserNotificationCenterNotifier.notificationsEnabled(defaults))
    }

    func testNotificationsEnabledTrueWhenTurnedOn() throws {
        let suite = "test.NotificationGating.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        // 用户重开开关 → true → send 正常走后续申请权限/发送流程。
        defaults.set(true, forKey: AppConfig.notificationsEnabledKey)
        XCTAssertTrue(UNUserNotificationCenterNotifier.notificationsEnabled(defaults))
    }
}
