import SwiftUI

/// 分类的**展示层**映射：分类名 / 方向 → 展示色 + emoji。
///
/// 存在理由：N00 预置分类只写 name/direction/isPreset/sortOrder，icon/color 为 nil
/// （见 `PresetCategories`），端上需要兜底的彩色标签与 emoji。本类型纯函数式、无状态、
/// 不触库、**不回写** `LedgerCategory.color/icon`（PRD §7），供切片 02/03 的表单选择器、
/// 列表标签、编辑页统一取用。
enum CategoryStyle {

    /// 未分类（账单未选分类 / 分类被 .nullify 删除）的 emoji：不按方向区分。
    private static let unassignedEmoji = "🏷️"

    /// 8 个预置分类的固定配色 + emoji（名称命中优先）。
    /// 支出「其他」用灰、收入「工作/其他收入」用绿——与各自方向兜底色同系，属设计如此。
    private static let presetStyles: [String: (emoji: String, color: Color)] = [
        "衣":   ("👕", .purple),
        "食":   ("🍜", .orange),
        "住":   ("🏠", .blue),
        "行":   ("🚗", .teal),
        "玩":   ("🎮", .pink),
        "其他": ("📦", .gray),
        "工作": ("💼", .green),
        "其他收入": ("💰", .green),
    ]

    // MARK: - 主 API（name + direction，覆盖含 nil name 的全部情况）

    /// 分类名 → emoji。
    /// - name 为 nil：未分类，统一 `🏷️`（与方向无关）。
    /// - name 命中预置：返回其固定 emoji。
    /// - name 未命中（N07 用户自建）：按方向兜底（支出 📦 / 收入 💰），前向兼容不硬崩。
    static func emoji(name: String?, direction: TransactionDirection) -> String {
        guard let name else { return unassignedEmoji }
        if let preset = presetStyles[name] { return preset.emoji }
        return fallbackEmoji(for: direction)
    }

    /// 分类名 → 展示色。
    /// - name 命中预置：返回其固定色。
    /// - name 为 nil 或未命中：按方向兜底（支出灰 / 收入绿）。
    static func color(name: String?, direction: TransactionDirection) -> Color {
        if let name, let preset = presetStyles[name] { return preset.color }
        return fallbackColor(for: direction)
    }

    // MARK: - 便利 API（LedgerCategory?）

    /// 非 nil 分类委托给主 API（分类自带 direction）；nil 分类无方向可依，emoji 统一 `🏷️`。
    static func emoji(for category: LedgerCategory?) -> String {
        guard let category else { return unassignedEmoji }
        return emoji(name: category.name, direction: category.direction)
    }

    /// 非 nil 分类委托给主 API；nil 分类无方向可依，返回中性兜底色。
    /// 账单标签需按方向兜底 nil 分类时，调用方应改用 `color(name:direction:)` 传 `tx.direction`。
    static func color(for category: LedgerCategory?) -> Color {
        guard let category else { return .gray }
        return color(name: category.name, direction: category.direction)
    }

    // MARK: - 方向兜底

    private static func fallbackEmoji(for direction: TransactionDirection) -> String {
        switch direction {
        case .expense: return "📦"
        case .income:  return "💰"
        }
    }

    private static func fallbackColor(for direction: TransactionDirection) -> Color {
        switch direction {
        case .expense: return .gray
        case .income:  return .green
        }
    }
}
