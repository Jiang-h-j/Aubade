import XCTest
@testable import Aubade

/// 切片 02：金额展示格式化 `AmountFormat`。
/// 验证带符号千分位串（-35.55 / +8,000.00）、Decimal 无浮点误差、方向色（验收 1、已确认约定 4）。
final class AmountFormatTests: XCTestCase {

    func testExpenseSignedString() {
        XCTAssertEqual(
            AmountFormat.signedString(Decimal(string: "35.55")!, direction: .expense),
            "-35.55")
    }

    func testIncomeSignedStringWithGrouping() {
        XCTAssertEqual(
            AmountFormat.signedString(Decimal(string: "8000")!, direction: .income),
            "+8,000.00")
    }

    func testLargeAmountGrouping() {
        XCTAssertEqual(
            AmountFormat.signedString(Decimal(string: "1234567.5")!, direction: .expense),
            "-1,234,567.50")
    }

    func testAlwaysTwoFractionDigits() {
        XCTAssertEqual(
            AmountFormat.signedString(Decimal(string: "100")!, direction: .expense),
            "-100.00", "整数金额补足 2 位小数")
    }

    func testDecimalNoFloatingPointError() {
        // 0.1 + 0.2 在 Double 下为 0.30000000000000004；Decimal 精确为 0.3。
        let sum = Decimal(string: "0.1")! + Decimal(string: "0.2")!
        XCTAssertEqual(
            AmountFormat.signedString(sum, direction: .expense),
            "-0.30")
    }

    func testPlainStringNoSign() {
        XCTAssertEqual(AmountFormat.plainString(Decimal(string: "8000")!), "8,000.00")
    }

    func testDirectionColor() {
        XCTAssertEqual(AmountFormat.color(for: .income), .green)
        XCTAssertEqual(AmountFormat.color(for: .expense), .primary)
    }
}
