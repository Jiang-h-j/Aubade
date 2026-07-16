import XCTest
@testable import Aubade

/// TRD 03 验证点：首次引导分流判据 `AppConfig.hasOnboarded(_:)`（N07 切片 03）。
///
/// SwiftUI View body 分流（ContentView 按标志选 OnboardingView / RootTabView）难直接单测，
/// 故把"是否进引导"的判据做成可测的 `AppConfig.hasOnboarded(_:)` 纯读取，断言标志读写正确即覆盖分流逻辑。
/// 注入独立 `UserDefaults(suiteName:)`，不污染 .standard（照 StatisticsAggregatorTests 的 AppConfig 范式）。
final class OnboardingRoutingTests: XCTestCase {

    func testHasOnboardedDefaultsFalseSoFreshInstallEntersOnboarding() throws {
        let suite = "test.Onboarding.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        // 未设值（全新安装）→ 默认 false → ContentView 选择 OnboardingView（进引导）。
        XCTAssertFalse(AppConfig.hasOnboarded(defaults))
    }

    func testHasOnboardedTrueRoutesToRootTab() throws {
        let suite = "test.Onboarding.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        // 引导走完置位 → true → ContentView 选择 RootTabView（直达主界面，不再进引导）。
        defaults.set(true, forKey: AppConfig.hasOnboardedKey)
        XCTAssertTrue(AppConfig.hasOnboarded(defaults))
    }

    func testHasOnboardedPersistsAcrossReads() throws {
        // 跨读取保持（模拟跨重启：@AppStorage 写同一 key，重启后读取仍为 true）= 验收 1/验收 8。
        let suite = "test.Onboarding.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(AppConfig.hasOnboarded(defaults))   // 初始未引导
        defaults.set(true, forKey: AppConfig.hasOnboardedKey)   // finish() 置位
        XCTAssertTrue(AppConfig.hasOnboarded(defaults))    // 再读仍为已引导（不回退）
    }
}
