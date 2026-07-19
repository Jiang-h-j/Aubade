# TRD 02 - R4 分类 Store 能力

## 给用户看的摘要

这一片是"看不见的地基"：给分类补上"改"和"删"两个后台能力，正确性全部用单测焊死，不涉及界面。要点：预置分类改不动也删不掉；删一个已经被账单用过的自定义分类时，先把那些账单转到对应的"其他"分类，再删——账单绝不会变成没有分类。收入的账单转到"其他收入"，支出的转到"其他"，按方向走。

## 本 TRD 负责什么

在 `LedgerStore` 新增三项能力（纯逻辑，单测覆盖）：

- `updateCategory`：改自定义分类的名称/图标/颜色；预置分类拒改；同方向重名拒绝。
- 分类删除方法：预置拒删；删前统计引用数；有引用先把账单逐笔转到"对应方向兜底分类"，再删分类。
- 引用计数：供 UI 展示"N 笔将转移"（复用反向关系，不新增查询层）。

不写任何 UI。UI 消费在切片 03。

## 当前代码事实与上下游

- `LedgerStore`（`Aubade/Store/LedgerStore.swift`）分类相关现状：
  - `createCategory(name:direction:icon:color:isPreset:sortOrder:)`（`:26-35`）
  - `presetCategories()`（`:38-42`）
  - **无 `updateCategory`、无分类专用删除、无引用计数**（全库 grep 零命中，PRD 已核实）。
  - 通用泛型删除 `delete<T>(_:)`（`:120-123`）：`context.delete(model)` + `save()`——这条**保留不动**，`RelationshipTests` 锁它走 `.nullify`。
  - 写侧收敛范式：`setBudget`（`:83-89`）、`setBalanceBaseline`（`:104-110`）——本片新方法沿用同样"改字段后 `try context.save()`"的朴素风格，不引入协议抽象。
- `LedgerCategory`（`Aubade/Models/LedgerCategory.swift:7-33`）：
  - `isPreset: Bool`（`:14`）用于预置判定。
  - `transactions: [Transaction]`（`:20-21`，`@Relationship(deleteRule:.nullify, inverse:\Transaction.category)`）→ 引用计数直接用 `category.transactions.count`；转移时遍历 `category.transactions` 逐笔改 `tx.category`。
  - `direction: TransactionDirection`（`:11`）用于选对应兜底分类。
- 兜底分类定位口径（**必须复用，禁止另立**）：`RecognitionNormalizer.category(name:direction:in:)`（`Aubade/Features/Recognition/Parsing/RecognitionNormalizer.swift:26-33`）：`fallbackName = (direction == .expense) ? "其他" : "其他收入"`，按 `name + direction` 精确匹配。
- 兜底分类种子：`PresetCategories.expense[5]="其他"`、`income[1]="其他收入"`（`Aubade/Persistence/PresetCategories.swift:7-8`），**无稳定标志位，只能按 name+direction 定位。**
- `.nullify` 删除规则 vs "转其他"的冲突（R4 核心）：`.nullify` 只在"直接删分类"时把账单 category 置 nil。要"转其他"，**必须在删分类前手动把 `category.transactions` 逐笔改指兜底分类**，改完账单已不再引用被删分类，再删分类时 `.nullify` 对空集合无影响。二者不冲突，是"先手动转移、再删"的顺序问题。

## 设计方案

### 方法一：updateCategory

```
func updateCategory(_ category: LedgerCategory, name: String, icon: String?, color: String?) throws
```

- 预置保护：`category.isPreset == true` → 抛 `CategoryError.presetImmutable`，不改任何字段。
- 同方向重名拒绝：在 `category.direction` 下、排除自身，若已存在同 `name` 分类 → 抛 `CategoryError.duplicateName`。
  - 判重实现：`fetch(LedgerCategory.self)` 内存过滤 `$0.direction == category.direction && $0.name == name && $0.id != category.id`（对齐 `setBudget` 全量 fetch 内存过滤范式，规避 `#Predicate` 对 enum/复合条件的支持限制）。
- 通过后：`category.name = name; category.icon = icon; category.color = color; try context.save()`。
- 方向不可改（原型：编辑时方向锁定）——本方法签名不含 direction，天然不改方向。

### 方法二：分类删除（预置保护 + 引用计数 + 转兜底）

```
func deleteCategory(_ category: LedgerCategory) throws
```

- 预置保护：`category.isPreset == true` → 抛 `CategoryError.presetUndeletable`，不删。
- 转移 + 删除：
  1. 若 `category.transactions` 非空，按 `category.direction` 定位兜底分类：`fallbackName = (direction == .expense) ? "其他" : "其他收入"`（**与 `RecognitionNormalizer` 同一常量口径**），`fetch` 全量内存过滤取 `name == fallbackName && direction == category.direction` 的分类。
  2. 兜底分类存在 → 遍历 `category.transactions` 逐笔 `tx.category = fallback`（快照数组后遍历，避免遍历中改关系集合的可变性问题）。
  3. 兜底分类**不存在**（异常态，预置被删光）→ 不阻塞删除，账单走 `.nullify` 置 nil（与泛型删除同结局）；这是防御分支，正常库不会触发（预置兜底不可删）。
  4. `context.delete(category); try context.save()`。
- 顺序：先转移账单引用、`save`（或同一事务内改完再删），再 `delete(category)`。实现时在同一 `save()` 前完成"改 tx.category + delete category"，一次 `save` 落库。

### 引用计数

- 不新增独立方法，UI 直接读 `category.transactions.count`（反向关系已就绪，PRD 已确认）。若切片 03 需要一个语义化入口，可加极薄 `func referenceCount(_ category:) -> Int { category.transactions.count }`，但非必须——**本片默认不加，避免过度设计**；03 若确需再补。

### 错误类型

新增 `enum CategoryError: Error`（放 `LedgerStore.swift` 内或同目录小文件）：`presetImmutable` / `presetUndeletable` / `duplicateName`。UI 层据此给 toast 文案。命名从简，不带 localizedDescription（文案由 UI 决定，对齐现有 `RecognitionError` 只做类型区分的风格）。

## 修改点

| 文件 | 动作 |
|---|---|
| `LedgerStore.swift`（`:24-42` LedgerCategory 段内） | 新增 `updateCategory(_:name:icon:color:)`、`deleteCategory(_:)` |
| `LedgerStore.swift` 或同目录 | 新增 `enum CategoryError: Error`（3 个 case） |
| `AubadeTests/`（新增测试文件，如 `CategoryStoreTests.swift`） | 覆盖下列用例 |

- 不改 `delete<T>`（`:120-123`）、不改 `createCategory`、不改模型、不改 `RecognitionNormalizer`。

## 验证点

新增单测（`@MainActor` + 持有 `container`，照 `RelationshipTests` 范式），对齐 PRD 验收 4、7、8、9、10：

1. **updateCategory 改自定义**：建自定义分类 → 改名/图标/色 → 断言字段更新、`save` 成功。
2. **updateCategory 拒预置**：对预置分类调用 → 抛 `presetImmutable`，字段不变。
3. **updateCategory 同方向重名拒绝**：同方向已有"宠物" → 另一分类改名"宠物" → 抛 `duplicateName`，不改。
4. **updateCategory 跨方向同名允许**：支出有"其他"、收入建"其他"不冲突（判重限定同 direction）。
5. **deleteCategory 拒预置**：删预置分类 → 抛 `presetUndeletable`，分类仍在。
6. **deleteCategory 未引用**：删无账单引用的自定义分类 → 分类消失，无账单受影响。
7. **deleteCategory 已引用转"其他"（支出）**：自定义支出分类"宠物"记 2 笔支出 → 删 → 分类消失，那 2 笔 `category?.name == "其他"`（**非 nil**）。
8. **deleteCategory 已引用转"其他收入"（收入，方向兜底）**：自定义收入分类记 1 笔收入 → 删 → 该笔 `category?.name == "其他收入"`（**非"其他"、非 nil**）。此条独立验证方向兜底，是对原型 `data.js:940` 统一转"其他"的纠偏，不可漏。
9. **引用计数**：`category.transactions.count` 在记 N 笔后等于 N。
10. **泛型删除仍 nullify（回归保护）**：`RelationshipTests.testDeleteCategoryNullifiesTransaction` 保持通过（走 `store.delete(category)` 泛型路径，不受本片影响）——本片不改该测试，只确认两条删除路径并存。
11. **命中自定义分类的自动分类**（PRD 需求 14）：建自定义支出分类后，`RecognitionNormalizer.category(name:"宠物", direction:.expense, in: categories)` 能命中它（验证新增分类天然进入识别候选，不改识别逻辑）。此条可放本片或独立小测。
12. **PresetCategoryTests 幂等复跑（回归保护，认领 PRD 验收 10 / 需求 15）**：本片不改 seed 逻辑，复跑 `PresetCategoryTests` 确认 8 条预置幂等仍通过。

## 不做什么

- 不改泛型 `delete<T>`，不改 `RelationshipTests` 断言（两条删除路径有意并存）。
- 不给 `LedgerCategory`/`Transaction` 加字段，无迁移。
- 不动 `RecognitionNormalizer`/识别 prompt。
- 不做 UI（切片 03）。
- 不加仓储协议/抽象分层，沿用 `LedgerStore` 现有朴素风格。
