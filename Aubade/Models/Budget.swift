import Foundation
import SwiftData

@Model
final class Budget {
    @Attribute(.unique) var id: UUID
    var periodType: BudgetPeriodType
    var amount: Decimal

    // 周/月各一条、可同时存在。本片不加"唯一 periodType"约束
    //（N02/N07 负责"每种周期仅一条"的业务保证），仅建表。
    init(id: UUID = UUID(), periodType: BudgetPeriodType, amount: Decimal) {
        self.id = id
        self.periodType = periodType
        self.amount = amount
    }
}
