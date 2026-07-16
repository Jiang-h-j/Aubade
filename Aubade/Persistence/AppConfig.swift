import Foundation

/// 本节点（N07）首次引入的生产配置集中定义（PRD 已确认约定 8）。
/// key 集中、默认值集中：视图用 `@AppStorage(key)` 绑定，非视图（聚合器/发送器调用方）读 `UserDefaults`。
/// Key（DeepSeek）仍走 Keychain、不在此（业务规则 12）。
enum AppConfig {
    /// 首次引导完成标志（切片 03 消费）。默认 false = 未引导。
    static let hasOnboardedKey = "config.hasOnboarded"
    static let hasOnboardedDefault = false

    /// 截图后台入账通知总开关（切片 04 消费）。默认 true = 开。
    static let notificationsEnabledKey = "config.notificationsEnabled"
    static let notificationsEnabledDefault = true

    /// 超支提示阈值（百分比整数，本片消费）。默认 80 = 与现状一致。
    static let overspendThresholdKey = "config.overspendThreshold"
    static let overspendThresholdDefault = 80

    /// 阈值合理范围（我的页 Stepper 约束 + 读取兜底）：50~100，步进 5。
    static let overspendThresholdRange = 50...100
    static let overspendThresholdStep = 5

    /// 非视图读超支阈值：未设值返回默认 80 + 兜底夹到合理范围（防脏值）。
    /// 用 `object(forKey:) as? Int ?? default` 而非 `integer(forKey:)`——后者未设值返回 0，
    /// 会让"没配过"退化成阈值 0（永远 near）。默认参数 `.standard` 便于单测注入独立 suite。
    static func overspendThreshold(_ defaults: UserDefaults = .standard) -> Int {
        let raw = defaults.object(forKey: overspendThresholdKey) as? Int ?? overspendThresholdDefault
        return min(max(raw, overspendThresholdRange.lowerBound), overspendThresholdRange.upperBound)
    }
}
