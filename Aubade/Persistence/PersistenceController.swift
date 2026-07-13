import Foundation
import SwiftData

/// 全 App 唯一的 ModelContainer 封装点。
///
/// 这是技术基线 §11 第 1 条「建库时机耦合」与 PRD 关键决策的落点，也是"迁移对冲"的唯一封装处：
/// 全 App 仅此处构造 ModelContainer；ViewModel/Store 永不自建容器，只接收注入的 ModelContext。
enum PersistenceController {
    /// 全 App 唯一 schema 定义。
    static let schema = Schema([
        Transaction.self, LedgerCategory.self, Budget.self, BalanceBaseline.self,
    ])

    /// 生产容器：in-app 路线 → 默认（非共享）配置，不配置 App Group。
    /// 迁移对冲点：日后若改独立扩展进程 + App Group，只改这一处 config 的 groupContainer/url。
    /// （但已积累数据的目录搬迁不在对冲范围内，若发生在 N06 评估。）
    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        // 容器构建失败属不可恢复的工程配置错误（schema 非法/磁盘不可用），fail-fast 暴露在开发期。
        return try! ModelContainer(for: schema, configurations: [config])
    }

    /// 测试/预览容器：纯内存，隔离且不落盘。
    static func makeInMemoryContainer() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
