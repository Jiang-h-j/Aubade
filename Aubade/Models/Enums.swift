import Foundation

/// 账单方向。金额本身存正值，方向由本枚举单独表达。
enum TransactionDirection: String, Codable, CaseIterable {
    case expense    // 支出
    case income     // 收入
}

/// 账单来源入口。
/// 技术基线 §8 将短信/文本入口写作 "sms/text"，含斜杠不能作 Swift case 名与稳定 RawValue，
/// 归一为 "text"（语义等价：短信/任意文本入口）。此为唯一措辞→标识符归一，非静默改动。
enum TransactionSource: String, Codable, CaseIterable {
    case screenshotShortcut   // 截图·快捷指令后台
    case screenshotAlbum      // 截图·相册选图
    case voice                // 语音
    case text                 // 短信/文本
    case manual               // 手动
}

/// 预算周期类型。
enum BudgetPeriodType: String, Codable, CaseIterable {
    case weekly     // 周
    case monthly    // 月
}
