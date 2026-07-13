import Foundation
import SwiftData

@Model
final class BalanceBaseline {
    @Attribute(.unique) var id: UUID
    var initialAmount: Decimal
    var establishedAt: Date

    // 剩余金额是派生值，不建字段（技术基线 §8）。本片只存基线初始值与建立时间，
    // 派生计算在 N02。
    init(id: UUID = UUID(), initialAmount: Decimal, establishedAt: Date) {
        self.id = id
        self.initialAmount = initialAmount
        self.establishedAt = establishedAt
    }
}
