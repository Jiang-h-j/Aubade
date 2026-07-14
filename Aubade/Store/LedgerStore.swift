import Foundation
import SwiftData

/// 薄读写封装：持有注入的 ModelContext，提供四模型基础 CRUD，供 N01+ ViewModel 调用。
///
/// 注入而非自建：LedgerStore 只接收 ModelContext，不碰 ModelContainer——保留迁移余地的硬约束。
/// 不做仓储模式/协议抽象过度分层；封装形态从简，够 N01 用即可，不预设 N02+ 的聚合查询。
struct LedgerStore {
    let context: ModelContext

    init(_ context: ModelContext) {
        self.context = context
    }

    // MARK: - 通用查询

    func fetch<T: PersistentModel>(_ type: T.Type,
                                   predicate: Predicate<T>? = nil,
                                   sortBy: [SortDescriptor<T>] = []) throws -> [T] {
        let descriptor = FetchDescriptor<T>(predicate: predicate, sortBy: sortBy)
        return try context.fetch(descriptor)
    }

    // MARK: - LedgerCategory

    @discardableResult
    func createCategory(name: String, direction: TransactionDirection,
                        icon: String? = nil, color: String? = nil,
                        isPreset: Bool = false, sortOrder: Int = 0) throws -> LedgerCategory {
        let category = LedgerCategory(name: name, direction: direction, icon: icon,
                                      color: color, isPreset: isPreset, sortOrder: sortOrder)
        context.insert(category)
        try context.save()
        return category
    }

    /// 预置分类：isPreset==true，按 sortOrder 升序。
    func presetCategories() throws -> [LedgerCategory] {
        try fetch(LedgerCategory.self,
                  predicate: #Predicate { $0.isPreset == true },
                  sortBy: [SortDescriptor(\.sortOrder)])
    }

    // MARK: - Transaction

    /// 创建账单。内部填 createdAt=updatedAt=当前值；occurredAt 由写入方传入。
    @discardableResult
    func createTransaction(amount: Decimal, direction: TransactionDirection,
                          occurredAt: Date, category: LedgerCategory? = nil,
                          merchant: String? = nil, note: String? = nil,
                          cardTail: String? = nil, source: TransactionSource,
                          rawText: String? = nil, imageRef: String? = nil) throws -> Transaction {
        let now = Date()
        let tx = Transaction(amount: amount, direction: direction, occurredAt: occurredAt,
                             category: category, merchant: merchant, note: note,
                             cardTail: cardTail, source: source, rawText: rawText,
                             imageRef: imageRef, createdAt: now, updatedAt: now)
        context.insert(tx)
        try context.save()
        return tx
    }

    /// 更新账单：apply 内修改字段后刷新 updatedAt。
    func updateTransaction(_ tx: Transaction, apply: (Transaction) -> Void) throws {
        apply(tx)
        tx.updatedAt = Date()
        try context.save()
    }

    // MARK: - Budget

    @discardableResult
    func createBudget(periodType: BudgetPeriodType, amount: Decimal) throws -> Budget {
        let budget = Budget(periodType: periodType, amount: amount)
        context.insert(budget)
        try context.save()
        return budget
    }

    // MARK: - BalanceBaseline

    @discardableResult
    func createBalanceBaseline(initialAmount: Decimal, establishedAt: Date) throws -> BalanceBaseline {
        let baseline = BalanceBaseline(initialAmount: initialAmount, establishedAt: establishedAt)
        context.insert(baseline)
        try context.save()
        return baseline
    }

    /// 设置/调整唯一初始总额基线：删除所有既有 BalanceBaseline，再插入一条新的。
    /// 唯一化用"清空+插入"而非 update——基线无业务主键、量极小（0~1 条），清插最简单且天然收敛到一条。
    /// establishedAt 显式传入以便测试注入；生产传 Date()，语义为"此刻账户合计的新起点"。
    func setBalanceBaseline(initialAmount: Decimal, establishedAt: Date) throws {
        let existing = try fetch(BalanceBaseline.self)
        for baseline in existing {
            context.delete(baseline)
        }
        try createBalanceBaseline(initialAmount: initialAmount, establishedAt: establishedAt)
    }

    /// 读当前有效基线：取 establishedAt 最新一条（防御多条并存）。
    func currentBaseline() throws -> BalanceBaseline? {
        try fetch(BalanceBaseline.self,
                  sortBy: [SortDescriptor(\.establishedAt, order: .reverse)]).first
    }

    // MARK: - 通用删除

    func delete<T: PersistentModel>(_ model: T) throws {
        context.delete(model)
        try context.save()
    }
}
