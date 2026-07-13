import Foundation
import SwiftData

/// 预置分类的数据源 + 首次幂等装载。
enum PresetCategories {
    // 顺序即 sortOrder：支出 衣/食/住/行/玩/其他，收入 工作/其他收入。
    static let expense = ["衣", "食", "住", "行", "玩", "其他"]
    static let income  = ["工作", "其他收入"]

    /// 幂等装载：库中已存在任一预置分类则整体跳过，重复启动不重复写。
    ///
    /// 幂等判据 = "已存在预置分类则跳过"（fetchCount(isPreset==true) > 0），而非计数是否等于 8——
    /// 避免用户日后删掉某条预置分类后重启又被补回（分类可增删改是 §8/N07 语义）。
    static func seedIfNeeded(_ context: ModelContext) {
        let descriptor = FetchDescriptor<LedgerCategory>(
            predicate: #Predicate { $0.isPreset == true }
        )
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        guard existing == 0 else { return }

        var order = 0
        for name in expense {
            context.insert(LedgerCategory(name: name, direction: .expense, isPreset: true, sortOrder: order))
            order += 1
        }
        for name in income {
            context.insert(LedgerCategory(name: name, direction: .income, isPreset: true, sortOrder: order))
            order += 1
        }
        try? context.save()
    }
}
