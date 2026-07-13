import XCTest
import SwiftData
@testable import Aubade

/// 验收 4：预置分类首次装载幂等。
@MainActor
final class PresetCategoryTests: XCTestCase {

    // 必须持有容器：ModelContext 不强引用 ModelContainer。
    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        container = PersistenceController.makeInMemoryContainer()
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testSeedInsertsEightPresets() throws {
        let context = container.mainContext
        PresetCategories.seedIfNeeded(context)

        let store = LedgerStore(context)
        let presets = try store.presetCategories()

        // 恰好 8 条且全部 isPreset。
        XCTAssertEqual(presets.count, 8)
        XCTAssertTrue(presets.allSatisfy { $0.isPreset })

        // sortOrder 有序（0..7）且展示顺序 = 支出6 + 收入2。
        XCTAssertEqual(presets.map { $0.sortOrder }, Array(0..<8))
        XCTAssertEqual(presets.map { $0.name },
                       PresetCategories.expense + PresetCategories.income)
        XCTAssertEqual(presets.prefix(6).map { $0.direction }, Array(repeating: .expense, count: 6))
        XCTAssertEqual(presets.suffix(2).map { $0.direction }, Array(repeating: .income, count: 2))
    }

    func testSeedIsIdempotent() throws {
        let context = container.mainContext

        // 未经用户删改的前提下，二次 seed 仍为 8 条（对齐 PRD 验收 4「再次启动数量仍为 8」）。
        PresetCategories.seedIfNeeded(context)
        PresetCategories.seedIfNeeded(context)

        let count = try LedgerStore(context).presetCategories().count
        XCTAssertEqual(count, 8)
    }
}
