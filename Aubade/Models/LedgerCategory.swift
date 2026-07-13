import Foundation
import SwiftData

// 命名说明：模型名不用裸 "Category"——它与 ObjC runtime 的 `typedef struct objc_category *Category`
// 冲突，会在 @testable 测试宿主里造成类型歧义与 SwiftData 运行时崩溃。故落地为 LedgerCategory。
// 技术基线 §8 的领域概念仍是"分类"，此为命名冲突规避，字段/关系/语义与 §8 一致。
@Model
final class LedgerCategory {
    @Attribute(.unique) var id: UUID
    var name: String
    var direction: TransactionDirection
    var icon: String?
    var color: String?
    var isPreset: Bool
    var sortOrder: Int

    // 该关系在 SwiftData 的反向端声明（技术基线 §8 只列了 Transaction.category 单向）。
    // inverse 只在此一端声明、Transaction.category 保持裸 LedgerCategory?，是 SwiftData 避免双端冲突的正确写法。
    // .nullify：删分类时其账单的 category 置空而非级联删账单（账单是用户资产，N01/N07 依赖此语义）。
    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []

    init(id: UUID = UUID(), name: String, direction: TransactionDirection,
         icon: String? = nil, color: String? = nil,
         isPreset: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.direction = direction
        self.icon = icon
        self.color = color
        self.isPreset = isPreset
        self.sortOrder = sortOrder
    }
}
