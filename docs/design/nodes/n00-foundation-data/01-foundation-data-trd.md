# TRD 01 - 工程骨架 + SwiftData 数据层最小闭环

## 给用户看的摘要

这一片是把 PRD 的"地基"落成**真实文件与代码结构**：建一个能在 iOS 17+ 上编译运行的空 SwiftUI 工程，写四个数据模型（账单/分类/预算/余额基线，金额全用精确的 `Decimal`），把数据库入口（`ModelContainer`）收敛到**一个封装点**，首次打开自动写入 8 条预置分类（重复打开不重复写），再提供一层薄薄的增删改查封装给以后所有页面用。验证方式是**单元测试 + 一个只在 DEBUG 出现的临时调试按钮**，用来当场证明"四张表能增删改查""预置分类写进去了且不重复""金额小数不丢精度"。

**按 PRD 评审已定的关键决策落地**：截图后台走 **in-app App Intents**，所以本片**不配置 App Group**、`ModelContainer` 用默认（非共享）配置；同时把容器创建收敛到单一工厂，日后若真要改独立扩展进程，代码只改这一处（但已有数据的目录搬迁不在对冲范围内，留待 N06 评估）。

## 本 TRD 负责什么

落地 N00 PRD「需求范围」全部 6 项 + 8 条验收标准，构成一个可编译运行、可单测验证的数据层最小闭环：

1. Xcode 工程骨架（iOS 17+、SwiftUI 生命周期、零三方依赖）。
2. 四个 SwiftData `@Model`：`Transaction`、`Category`、`Budget`、`BalanceBaseline`（技术基线 §8 逐字段）。
3. 三个可持久化枚举：`TransactionDirection`、`TransactionSource`、`BudgetPeriodType`。
4. 单一 `ModelContainer` 封装点（`PersistenceController`）并注入 SwiftUI 环境。
5. 预置分类首次幂等装载（8 条，`isPreset=true`，`sortOrder` 有序；重复启动不重复）。
6. 薄读写封装（四模型基础 CRUD），供 N01+ ViewModel 调用。
7. 验证手段：单元测试（主证据）+ DEBUG-only 临时调试入口（可观察辅证）。

## 当前代码事实与上下游

- **全新工程，零既有代码**：`find` 确认仓库无任何 `*.swift` / `*.xcodeproj` / `*.xcworkspace` / `Package.swift` / `Podfile`；无 `.codegraph/` 索引（符合预期）。本 TRD 所有符号均为**新增**，不改动任何既有入口，无共享符号影响，无需调用图/影响分析。
- **代码事实锚定技术基线**（非现有行号）：模型字段权威定义在技术基线 §8；金额 `Decimal` 约束在 §3/§8；预置分类清单在 §8 Category / 全局 PRD 业务规则 7；非实体状态不入库在 §8「非实体状态」/§7.4；App Group 路线判定在 §11 第 1 条（PRD 评审已选 in-app）。
- **`.gitignore` 已就绪**：已预置 `build/`、`DerivedData/`、`xcuserdata/`、`.swiftpm/`、`Package.resolved` 等 Xcode 忽略项，工程落地无需改动。
- **下游契约（本片对 N01~N06 的承诺，须稳定）**：
  - 四模型字段与 §8 一致、金额为 `Decimal`。
  - 存在一个可被主 App（及后续 in-app App Intent 后台链路）访问的共享 `ModelContainer` 单点。
  - 首次启动后 8 条预置分类可查询到。
  - ViewModel 只持有注入的 `ModelContext`，不自建容器（保留迁移余地的关键约束）。

## 设计方案

### 1. 工程结构与命名

Xcode 工程名 `Aubade`，Bundle ID 占位 `com.aubade.app`（真机自签名时按开发者账号调整，不影响本片验收）。目录结构：

```
Aubade.xcodeproj
Aubade/
  AubadeApp.swift                 # @main App 入口，注入 ModelContainer
  ContentView.swift               # 占位根视图（含 DEBUG-only 调试入口）
  Persistence/
    PersistenceController.swift    # 单一 ModelContainer 封装点 + schema 定义
    PresetCategories.swift         # 8 条预置分类的数据源 + 幂等装载
  Models/
    Transaction.swift
    Category.swift
    Budget.swift
    BalanceBaseline.swift
    Enums.swift                    # TransactionDirection / TransactionSource / BudgetPeriodType
  Store/
    LedgerStore.swift              # 薄读写封装（四模型 CRUD）
  Debug/
    DebugMenuView.swift            # #if DEBUG 临时验证入口
AubadeTests/
  ModelCRUDTests.swift
  PresetCategoryTests.swift
  DecimalPrecisionTests.swift
  RelationshipTests.swift
```

> 说明：Xcode 工程文件（`.xcodeproj/project.pbxproj`）在开发阶段由 Xcode 或脚手架生成；本 TRD 定结构与文件清单，不手写 pbxproj 内容。若开发时选用 `xcodegen`/`tuist` 等生成器需在开发前单独确认（默认直接用 Xcode 新建 App 模板，零额外依赖，符合"零三方依赖"）。

### 2. 枚举（`Enums.swift`）

三个枚举均 `String` RawValue + `Codable`，SwiftData 可直接持久化 `Codable`/`RawRepresentable` 枚举：

```swift
enum TransactionDirection: String, Codable, CaseIterable {
    case expense    // 支出
    case income     // 收入
}

enum TransactionSource: String, Codable, CaseIterable {
    case screenshotShortcut   // 截图·快捷指令后台
    case screenshotAlbum      // 截图·相册选图
    case voice                // 语音
    case text                 // 短信/文本  （§8 写作 "sms/text"，RawValue 取合法标识符 "text"）
    case manual               // 手动
}

enum BudgetPeriodType: String, Codable, CaseIterable {
    case weekly     // 周
    case monthly    // 月
}
```

> §8 中 source 写作 `sms/text`，含斜杠不能作 Swift case 名与稳定 RawValue，落地为 `text`（语义等价：短信/任意文本入口）。此为唯一措辞→标识符归一，记录在本片"验证点"与进度。

### 3. 四个 SwiftData 模型（逐字段，锚定 §8）

**`Category.swift`**（先定义，`Transaction` 关系依赖它）：

```swift
@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var name: String
    var direction: TransactionDirection
    var icon: String?
    var color: String?
    var isPreset: Bool
    var sortOrder: Int
    // 反向关系：该分类下的账单（可空集合）
    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []

    init(id: UUID = UUID(), name: String, direction: TransactionDirection,
         icon: String? = nil, color: String? = nil,
         isPreset: Bool = false, sortOrder: Int = 0) { ... }
}
```

- `deleteRule: .nullify`：删分类时，其账单的 `category` 置空而非级联删账单（账单是用户资产，不能因删分类而丢；N01/N07 分类管理依赖此语义）。
- `transactions` 反向关系：§8 只列了 `Transaction.category`（关系→Category）单向；此处的 `transactions` 是同一关系在 SwiftData 的**反向端声明**（`RelationshipTests` 的"经分类反查账单"依赖它），非新增业务字段。`inverse` 只在此一端声明、`Transaction.category` 保持裸 `Category?`，是 SwiftData 避免双端声明冲突的正确写法。
- `id` 用 `UUID` + `.unique`；`init` 提供默认值便于预置与测试构造。

**`Transaction.swift`**（§8 逐字段）：

```swift
@Model
final class Transaction {
    @Attribute(.unique) var id: UUID
    var amount: Decimal            // 正值，方向单独表达
    var direction: TransactionDirection
    var occurredAt: Date           // 识别不到时取当前时间（本片不含识别，由写入方传入）
    var category: Category?        // 关系 → Category（可空：分类被删后 nullify）
    var merchant: String?
    var note: String?
    var cardTail: String?          // 仅记录，不参与分账户统计
    var source: TransactionSource
    var rawText: String?
    var imageRef: String?          // 截图临时引用（本片仅建字段，清理逻辑在 N06/M9）
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), amount: Decimal, direction: TransactionDirection,
         occurredAt: Date, category: Category? = nil, merchant: String? = nil,
         note: String? = nil, cardTail: String? = nil,
         source: TransactionSource, rawText: String? = nil, imageRef: String? = nil,
         createdAt: Date, updatedAt: Date) { ... }
}
```

- `category` 声明为可空 `Category?`：与 `.nullify` 删除规则一致；本片不强制账单必须有分类（N01 表单再约束业务必填）。
- `occurredAt` / `createdAt` / `updatedAt` 由写入方显式传入（本片 `LedgerStore.createTransaction` 负责填 `createdAt=updatedAt=占位当前值`；为可测，不在模型 init 里调用 `Date()` 隐式取时——见"验证点"）。

**`Budget.swift`**：

```swift
@Model
final class Budget {
    @Attribute(.unique) var id: UUID
    var periodType: BudgetPeriodType
    var amount: Decimal
    init(id: UUID = UUID(), periodType: BudgetPeriodType, amount: Decimal) { ... }
}
```

- 周/月各一条、可同时存在：本片不加"唯一 periodType"约束（N02/N07 负责"每种周期仅一条"的业务保证），仅建表。

**`BalanceBaseline.swift`**：

```swift
@Model
final class BalanceBaseline {
    @Attribute(.unique) var id: UUID
    var initialAmount: Decimal
    var establishedAt: Date
    init(id: UUID = UUID(), initialAmount: Decimal, establishedAt: Date) { ... }
}
```

- **剩余金额是派生值，不建字段**（§8 明确）——本片只存 `initialAmount` 与 `establishedAt`，派生计算在 N02。

### 4. `ModelContainer` 单一封装点（`PersistenceController.swift`）

这是 §11 第 1 条「建库时机耦合」与 PRD 关键决策的落点，也是"迁移对冲"的唯一封装处：

```swift
struct PersistenceController {
    // 全 App 唯一 schema 定义
    static let schema = Schema([
        Transaction.self, Category.self, Budget.self, BalanceBaseline.self,
    ])

    /// 生产容器：in-app 路线 → 默认（非共享）配置，不配置 App Group。
    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        // 迁移对冲点：日后若改独立扩展进程 + App Group，只改这一处 config 的 groupContainer/url。
        return try! ModelContainer(for: schema, configurations: [config])
    }

    /// 测试/预览容器：纯内存，隔离且不落盘。
    static func makeInMemoryContainer() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
```

- **单点收敛**：全 App 仅此处构造 `ModelContainer`；`AubadeApp` 用 `makeContainer()`，测试用 `makeInMemoryContainer()`。ViewModel/Store 永不自建容器，只接收注入的 `ModelContext`——这是保留迁移余地的硬约束。
- **不配置 App Group**：`ModelConfiguration` 不传 `groupContainer`，即验收 8 的"未配置 App Group entitlement + 默认非共享配置"可审阅证据。
- **`try!` 的边界**：容器构建失败属于不可恢复的工程配置错误（schema 非法/磁盘不可用），非运行时可处理的业务错误，此处 `try!` 让其 fail-fast 暴露在开发期，符合"只在系统边界做防御、不为不可能场景加处理"。

`AubadeApp.swift` 注入并触发首启装载：

```swift
@main
struct AubadeApp: App {
    let container = PersistenceController.makeContainer()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { PresetCategories.seedIfNeeded(container.mainContext) }
        }
        .modelContainer(container)
    }
}
```

### 5. 预置分类首次幂等装载（`PresetCategories.swift`）

```swift
enum PresetCategories {
    // 顺序即 sortOrder：支出 衣/食/住/行/玩/其他，收入 工作/其他收入
    static let expense = ["衣", "食", "住", "行", "玩", "其他"]
    static let income  = ["工作", "其他收入"]

    /// 幂等：库中已存在任一预置分类则整体跳过，重复启动不重复写。
    static func seedIfNeeded(_ context: ModelContext) {
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.isPreset == true }
        )
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        guard existing == 0 else { return }

        var order = 0
        for name in expense {
            context.insert(Category(name: name, direction: .expense, isPreset: true, sortOrder: order)); order += 1
        }
        for name in income {
            context.insert(Category(name: name, direction: .income, isPreset: true, sortOrder: order)); order += 1
        }
        try? context.save()
    }
}
```

- **幂等判据 = "已存在预置分类则跳过"**（`fetchCount(isPreset==true) > 0`），而非计数是否等于 8——避免用户日后删掉某条预置分类后重启又被补回（分类可增删改是 §8/N07 语义）。验收 4「再次启动数量仍为 8」在**未经用户改动**的前提下成立，本片测试即验证该前提。
- `sortOrder` 用插入顺序 0..7，保证展示有序。

### 6. 薄读写封装（`LedgerStore.swift`）

不做仓储模式/协议抽象过度分层；一个持有 `ModelContext` 的轻量 struct，提供四模型基础 CRUD：

```swift
struct LedgerStore {
    let context: ModelContext
    init(_ context: ModelContext) { self.context = context }

    // 通用查询
    func fetch<T: PersistentModel>(_ type: T.Type,
        predicate: Predicate<T>? = nil,
        sortBy: [SortDescriptor<T>] = []) throws -> [T]

    // Category
    func createCategory(...) throws -> Category
    // Transaction（内部填 createdAt=updatedAt；更新时刷新 updatedAt）
    func createTransaction(...) throws -> Transaction
    func updateTransaction(_ tx: Transaction, apply: (Transaction) -> Void) throws
    // Budget / BalanceBaseline 的 create/fetch
    // 通用删除
    func delete<T: PersistentModel>(_ model: T) throws

    // 便捷查询（供下游）
    func presetCategories() throws -> [Category]     // isPreset==true, 按 sortOrder
}
```

- 写操作内部 `context.save()`；查询走通用 `fetch`。封装形态从简，够 N01 用即可，不预设 N02+ 的聚合查询（那是各节点自己的事）。
- **注入而非自建**：`LedgerStore` 接收 `ModelContext`，不碰 `ModelContainer`。

### 7. 验证手段

**主证据 = 单元测试**（`AubadeTests`，全部用 `makeInMemoryContainer()` 隔离）：

- `ModelCRUDTests`：四模型各跑"新增→查询到→修改→删除"（验收 2）。
- `PresetCategoryTests`：空库调 `seedIfNeeded` 后恰好 8 条且 `isPreset=true`、`sortOrder` 有序；再调一次仍 8 条（验收 4）。
- `DecimalPrecisionTests`：写 `Decimal(string: "35.55")!` 入三处金额字段，读回 `==` 严格相等、无浮点误差（验收 3）。
- `RelationshipTests`：建 `Transaction` 关联某预置分类，经分类反查到它、经账单读到分类名（验收 5）；删分类后账单 `category == nil`（验证 `.nullify`）。

**辅助可观察证据 = DEBUG-only 调试入口**（`DebugMenuView`，`#if DEBUG` 包裹，`ContentView` 内仅 DEBUG 显示按钮）：手动触发"插入一笔样例账单/列出预置分类/清库重置"，供真机/模拟器肉眼确认容器单点共享（验收 6）。Release 构建不含此入口。

## 修改点

全部为**新增文件**（无既有文件修改）：

| 文件 | 内容 |
|---|---|
| `Aubade.xcodeproj` | Xcode App 工程（iOS 17+ 部署目标、SwiftUI 生命周期、无三方依赖） |
| `Aubade/AubadeApp.swift` | `@main` App，注入 `makeContainer()`，`.task` 触发 `seedIfNeeded` |
| `Aubade/ContentView.swift` | 占位根视图 + DEBUG-only 调试入口挂载 |
| `Aubade/Models/Enums.swift` | 三枚举（String/Codable） |
| `Aubade/Models/Category.swift` | `@Model Category` + 反向关系 `.nullify` |
| `Aubade/Models/Transaction.swift` | `@Model Transaction`（§8 全字段，金额 Decimal） |
| `Aubade/Models/Budget.swift` | `@Model Budget` |
| `Aubade/Models/BalanceBaseline.swift` | `@Model BalanceBaseline`（无派生剩余字段） |
| `Aubade/Persistence/PersistenceController.swift` | 单一容器封装点 + schema + 内存容器 |
| `Aubade/Persistence/PresetCategories.swift` | 8 条预置 + 幂等 `seedIfNeeded` |
| `Aubade/Store/LedgerStore.swift` | 薄 CRUD 封装 |
| `Aubade/Debug/DebugMenuView.swift` | `#if DEBUG` 验证入口 |
| `AubadeTests/*.swift` | 4 个测试文件（CRUD/预置/精度/关系） |

## 验证点

对齐 PRD 8 条验收标准，每条给出可执行判据：

1. **工程可编译运行**：`xcodebuild -scheme Aubade -destination 'generic/platform=iOS Simulator' build` 通过（用 generic destination 避免依赖本机具体模拟器名/版本）；模拟器启动到占位根视图无崩溃。
2. **四模型可 CRUD**：`ModelCRUDTests` 全绿（每模型一轮增查改删）。
3. **金额 Decimal 无误差**：`DecimalPrecisionTests` 写 `Decimal(string: "35.55")!` 读回严格 `==`（`amount` 已是静态 `Decimal`，不做 `is` 类型断言——恒真会触发编译器 always-true 告警）。
4. **预置首装幂等**：`PresetCategoryTests` 空库 seed 后 count==8 且 `isPreset`/`sortOrder` 正确；**未经用户删改的前提下**二次 seed 仍 ==8（与 PRD 验收 4「再次启动数量仍为 8」措辞对齐；用户删改预置后不补回是设计语义，见设计方案 §5）。
5. **关系可用**：`RelationshipTests` 账单↔分类双向可达；删分类并 `context.save()` 后（必要时重新 fetch 账单）观察到账单 `category==nil`。
6. **容器单点共享**：全仓 `grep` 仅 `PersistenceController` 内构造 `ModelContainer`；DEBUG 入口与测试读到同一数据。
7. **非实体状态未入库**：模型定义审阅——无 DeepSeek Key / 通知开关 / 预算周期规则 / 超支阈值 字段；`grep` 四模型文件确认无相关属性。
8. **App Group 决策落定**：无 `.entitlements` 中的 App Group 项、`ModelConfiguration` 未传 `groupContainer`（默认配置）；本片 + `99-slice-progress.md` 记录"in-app 路线 + 迁移对冲点 + 数据搬迁不被对冲消除"边界。
9. **source 归一记录**：`sms/text` → RawValue `text` 的归一决策已在本 TRD §2 与进度记录（可追溯，非静默改动）。

## 不做什么

严格遵循 PRD「不做什么」，本片不实现：

- 任何用户可见记账/账单/统计**界面**（→ N01/N02）；`ContentView` 仅占位 + DEBUG 入口。
- 任何**业务计算**：剩余金额派生、统计聚合、预算进度（→ N02）；本片只建 `Budget`/`BalanceBaseline` 表结构，不算数。
- **Keychain / UserDefaults 封装**（→ N03 最小 / N07 收口）；仅确保这些非实体状态不进 SwiftData。
- **App Group 实际启用**（默认 in-app 路线不配置）。
- **数据迁移逻辑**：切换到 App Group 时的 store 文件搬迁（若发生，在 N06 评估实现）。
- **分类用户增删改界面**、分类兜底匹配规则（界面→N07；匹配→N03）；本片仅写入预置并保证表支持增删改。
- 手写 `project.pbxproj` 细节 / 生成器选型（默认 Xcode App 模板；如需生成器开发前单独确认）。
