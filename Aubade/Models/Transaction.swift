import Foundation
import SwiftData

@Model
final class Transaction {
    @Attribute(.unique) var id: UUID
    var amount: Decimal            // 正值，方向由 direction 单独表达
    var direction: TransactionDirection
    var occurredAt: Date           // 识别不到时由写入方取当前时间（本片不含识别）
    var category: LedgerCategory?  // 关系 → LedgerCategory（可空：分类被删后 nullify）
    var merchant: String?
    var note: String?
    var cardTail: String?          // 仅记录，不参与分账户统计
    var source: TransactionSource
    var rawText: String?
    var imageRef: String?          // 截图临时引用（本片仅建字段，清理逻辑在 N06/M9）
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), amount: Decimal, direction: TransactionDirection,
         occurredAt: Date, category: LedgerCategory? = nil, merchant: String? = nil,
         note: String? = nil, cardTail: String? = nil,
         source: TransactionSource, rawText: String? = nil, imageRef: String? = nil,
         createdAt: Date, updatedAt: Date) {
        self.id = id
        self.amount = amount
        self.direction = direction
        self.occurredAt = occurredAt
        self.category = category
        self.merchant = merchant
        self.note = note
        self.cardTail = cardTail
        self.source = source
        self.rawText = rawText
        self.imageRef = imageRef
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
