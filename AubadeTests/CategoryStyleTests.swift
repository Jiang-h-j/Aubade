import XCTest
import SwiftUI
@testable import Aubade

/// 切片 01：分类展示映射 `CategoryStyle`。
/// 验证 8 类预置命中固定 emoji/色、nil 与未知名按 direction 兜底、便利 API 与主 API 一致。
@MainActor
final class CategoryStyleTests: XCTestCase {

    /// 8 个预置分类的期望映射：(名, 方向, emoji, 色)。与 TRD 映射表逐条对齐。
    private let presetExpectations: [(name: String, direction: TransactionDirection, emoji: String, color: Color)] = [
        ("衣", .expense, "👕", .purple),
        ("食", .expense, "🍜", .orange),
        ("住", .expense, "🏠", .blue),
        ("行", .expense, "🚗", .teal),
        ("玩", .expense, "🎮", .pink),
        ("其他", .expense, "📦", .gray),
        ("工作", .income, "💼", .green),
        ("其他收入", .income, "💰", .green),
    ]

    func testPresetNamesMapToFixedEmoji() {
        for e in presetExpectations {
            XCTAssertEqual(CategoryStyle.emoji(name: e.name, direction: e.direction), e.emoji,
                           "分类「\(e.name)」emoji 应为 \(e.emoji)")
        }
    }

    func testPresetNamesMapToFixedColor() {
        for e in presetExpectations {
            XCTAssertEqual(CategoryStyle.color(name: e.name, direction: e.direction), e.color,
                           "分类「\(e.name)」色不符预期")
        }
    }

    /// 前 5 个支出类（衣/食/住/行/玩）命中色必须不同于支出兜底灰——证明确实命中了预置表而非落兜底。
    /// （「其他/工作/其他收入」命中色恰等于各自方向兜底色，属设计如此，不在此断言。）
    func testDistinctExpensePresetsAreNotFallbackColor() {
        let expenseFallback = CategoryStyle.color(name: "未知", direction: .expense)
        for name in ["衣", "食", "住", "行", "玩"] {
            XCTAssertNotEqual(CategoryStyle.color(name: name, direction: .expense), expenseFallback,
                              "分类「\(name)」应有独立配色，而非支出兜底色")
        }
    }

    func testNilNameUsesTagEmojiRegardlessOfDirection() {
        XCTAssertEqual(CategoryStyle.emoji(name: nil, direction: .expense), "🏷️")
        XCTAssertEqual(CategoryStyle.emoji(name: nil, direction: .income), "🏷️")
    }

    func testNilNameUsesDirectionFallbackColor() {
        XCTAssertEqual(CategoryStyle.color(name: nil, direction: .expense), .gray)
        XCTAssertEqual(CategoryStyle.color(name: nil, direction: .income), .green)
    }

    /// 未知名（N07 用户自建）按方向兜底：支出 📦+灰、收入 💰+绿。前向兼容不硬崩。
    func testUnknownNameFallsBackByDirection() {
        XCTAssertEqual(CategoryStyle.emoji(name: "健身", direction: .expense), "📦")
        XCTAssertEqual(CategoryStyle.color(name: "健身", direction: .expense), .gray)
        XCTAssertEqual(CategoryStyle.emoji(name: "稿费", direction: .income), "💰")
        XCTAssertEqual(CategoryStyle.color(name: "稿费", direction: .income), .green)
    }

    // MARK: - 便利 API（LedgerCategory?）

    func testConvenienceAPIMatchesNameAPIForPresets() {
        for e in presetExpectations {
            // transient 实例（未插 context）：CategoryStyle 只读 name/direction，不触库。
            let category = LedgerCategory(name: e.name, direction: e.direction, isPreset: true)
            XCTAssertEqual(CategoryStyle.emoji(for: category), e.emoji)
            XCTAssertEqual(CategoryStyle.color(for: category), e.color)
        }
    }

    func testNilCategoryUsesTagEmojiAndNeutralColor() {
        let none: LedgerCategory? = nil
        XCTAssertEqual(CategoryStyle.emoji(for: none), "🏷️")
        XCTAssertEqual(CategoryStyle.color(for: none), .gray)
    }
}
