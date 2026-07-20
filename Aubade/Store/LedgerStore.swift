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

    /// 改自定义分类的名称/图标/颜色。预置拒改；同方向重名（排除自身）拒绝。方向不可改（签名不含 direction）。
    /// 判重用全量 fetch 内存过滤，对齐 setBudget 范式，规避 #Predicate 对 enum/复合条件的支持限制。
    func updateCategory(_ category: LedgerCategory, name: String,
                        icon: String?, color: String?) throws {
        guard !category.isPreset else { throw CategoryError.presetImmutable }
        let duplicate = try fetch(LedgerCategory.self).contains {
            $0.direction == category.direction && $0.name == name && $0.id != category.id
        }
        guard !duplicate else { throw CategoryError.duplicateName }
        category.name = name
        category.icon = icon
        category.color = color
        try context.save()
    }

    /// 删自定义分类。预置拒删；删前把该分类的账单逐笔按方向转兜底分类（支出"其他"/收入"其他收入"）再删，
    /// 保证账单不因删分类而丢失分类——这与泛型 delete(_:) 的 .nullify 路径有意并存。
    /// 兜底分类口径与 RecognitionNormalizer.category 同一常量。兜底缺失（异常态，预置被删光）则不阻塞删除，
    /// 账单走 .nullify 置 nil。改 tx.category 与 delete(category) 在同一 save() 前完成，一次落库。
    func deleteCategory(_ category: LedgerCategory) throws {
        guard !category.isPreset else { throw CategoryError.presetUndeletable }
        if !category.transactions.isEmpty {
            let fallbackName = (category.direction == .expense) ? "其他" : "其他收入"
            // 排除 category 自身：createCategory 不判重，用户可建出名为"其他"的自定义分类，
            // 删它时兜底不能选中它自己，否则账单会被转到即将删除的分类、随后 nullify 丢分类。
            let fallback = try fetch(LedgerCategory.self).first {
                $0.name == fallbackName && $0.direction == category.direction && $0.id != category.id
            }
            if let fallback {
                // 快照后遍历：改 tx.category 会经反向关系从 category.transactions 移除该元素，
                // 直接遍历原集合会在迭代中改动集合。
                let snapshot = category.transactions
                for tx in snapshot {
                    tx.category = fallback
                }
            }
        }
        context.delete(category)
        try context.save()
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

    /// 设置/调整某周期唯一预算：删同 periodType 旧记录再插一条（写侧唯一化，对称 setBalanceBaseline）。
    /// Budget 无时间戳、无法按时间取最新，故靠写侧收敛到"每周期至多一条"，读侧 @Query.first 即唯一值。
    /// 全量 fetch 内存过滤而非 #Predicate：Budget 量极小（至多周+月两条），且规避 Predicate 对 String enum 的支持限制。
    func setBudget(periodType: BudgetPeriodType, amount: Decimal) throws {
        let existing = try fetch(Budget.self).filter { $0.periodType == periodType }
        for budget in existing {
            context.delete(budget)
        }
        try createBudget(periodType: periodType, amount: amount)
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

/// 分类写操作的领域错误。只做类型区分，文案由 UI 层决定（对齐 RecognitionError 风格）。
enum CategoryError: Error {
    case presetImmutable    // 预置分类不可改
    case presetUndeletable  // 预置分类不可删
    case duplicateName      // 同方向已存在同名分类
}
