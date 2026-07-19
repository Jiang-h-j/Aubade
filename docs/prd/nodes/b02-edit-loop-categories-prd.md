# B02 编辑闭环：最近记录删除 + 自定义分类

> 批次 `batch01-feedback-fixes` 第二个开发节点（对应批次需求 **R3 + R4**）。模式 `existing_batch`：在 Aubade v1（N00~N07 已合并 main）既有链路上补齐编辑闭环，不从 0 到 1。B01 已完成合入 main。
> 上游事实来源：批次 PRD `docs/prd/batch01-feedback-fixes-prd.md`（R3、R4 段）、批次原型 `docs/design/batch01-feedback-fixes-prototype.md`、批次技术基线 `docs/design/batch01-feedback-fixes-technical-baseline.md`、批次 DAG `docs/design/batch01-feedback-fixes-dev-dag.md`（B02 节点详情、决策 D1/D2/D3）。
> 代码事实来源：本仓库无 `.codegraph/`，以下行号来自本次手动阅读源码核实，可能 ±1 漂移。

## 给用户看的摘要

这个节点把两条"记完账之后还想改改删删"的基本盘补齐，都属于编辑闭环、触点也挨在一起，所以合成一个节点：

**R3 · 记账页最近记录能删了。** 现在记账页底部那块"最近记录"只能点进去改，删不掉——因为它跟账单页不是一套结构（账单页是能左滑删的列表，最近记录是手搭的几行）。这次把它也做成能左滑删除、删前弹一次确认，跟账单页完全一致。删掉后剩余总额和统计会自动跟着变。

**R4 · 分类可以自己增删改了。** 现在"我的"页里分类只能看（还只显示预置那 8 个），自定义分类根本进不来。这次做成一个能管理的列表：预置分类（衣/食/住/行等）标上"预置·锁定"、点了只提示不可改；自定义分类可以新增（选方向/名称/图标/颜色）、可以编辑、可以删除。**删一个已经被账单用过的分类时**，会先告诉你"有 N 笔账单会转到『其他』"，你确认后这些账单转到"其他"分类、分类才删掉——不会让账单变成没有分类。

**一个需要你拍板的开放项**：预置分类除了"禁删、禁改名"，**要不要允许改它们的图标/颜色**？DAG 阶段把这项留为开放，本 PRD 暂按"预置分类锁全部字段（图标色也不给改）"推进。你若希望预置能换图标/色，评审时说一声，我调范围。

范围锁在 R3 + R4，**不改数据模型、不动识别链路、不做 UI 视觉重做**（视觉是 B04）。做完的可观察标准见下方验收。

## 目标

1. **R3**：记账页「最近记录」支持左滑删除 + 二次确认，交互与账单页一致；删除后 `@Query` 自动刷新，剩余总额/统计同步更新。
2. **R4 分类管理 UI**：我的页分类区从"只读、仅预置"改为"可管理、含自定义"——预置锁定标记、自定义增删改入口、分类编辑器（方向/名称/图标/颜色）。
3. **R4 Store 能力**：`LedgerStore` 补齐分类的更新（`updateCategory`）、删除（预置保护 + 引用计数 + 删已引用先转"其他"再删）方法。
4. 同步更新受影响的单测（`RelationshipTests.testDeleteCategoryNullifiesTransaction` 语义随 D2 改变），并新增覆盖上述能力的用例，保持测试全绿。

## 当前理解

### R3 最近记录删除

- **现状**：记账页最近记录区 `RecordTabView.recentSection`（`Aubade/Features/Record/RecordTabView.swift:343-377`）是 `VStack(spacing:0)` + `ForEach` + `Button(.plain)` + `Divider` 的手搓结构，**不是 `List`**；点击只触发 `editingTransaction = tx` 进编辑 sheet，该 sheet（`:394-402`）注释明说"本片不注入 onDelete"——**当前最近记录根本无法删除**。数据源 `recentFour = Array(recentTransactions.prefix(4))`（`:196-198`），`recentTransactions` 是 `@Query(sort: \.occurredAt, order: .reverse)`（`:52`）。
- **样板（要对齐/复用的对象）**：账单页 `LedgerTabView.ledgerList`（`:208-231`）是标准 `List` + `.swipeActions(edge:.trailing)` + `role:.destructive` → 置 `pendingDelete` → `confirmationDialog`（`:52-58`"删除这笔账单？/删除后无法恢复"）→ `delete(_:)`（`:271-274`）调 `EditorActions.makeDelete(store:tx:)()`。删除态 `@State pendingDelete: Transaction?`（`:20`）+ `deleteConfirmBinding`（`:266-269`）。
- **共享删除工厂**：`EditorActions.makeDelete(store:tx:)`（`Aubade/Features/Editor/EditorActions.swift:26-30`）返回 `() -> Void`，内部 `try? store.delete(tx)`；二次确认 UI 由调用方在外面套。R3 直接复用。
- **关键约束（SwiftData 悬垂）**：从 sheet 内删除须"先 `dismiss()` 再执行 delete"，规避 SwiftData 以已删对象重建视图导致的悬垂读取（`DeepLinkResultSheet:431-441` 已有此范式）。R3 若走列表侧滑（非 sheet），置 `pendingDelete` → 确认 → 删除的路径与账单页一致，无此风险。
- **技术选型（DAG 决策 D1）**：最近记录改成 `List` 以启用 `.swipeActions`。原型侧另有 `swipeRow` 自造手势组件（`prototype/app/app.js:519-566`，记账页/账单页共用），但**真实端账单页已用原生 `List.swipeActions` 且工作良好**，本节点对齐原生方案，不引入自造手势（与账单页单一交互来源）。

### R4 自定义分类

- **模型现状（不需改）**：`LedgerCategory`（`Aubade/Models/LedgerCategory.swift:7-33`）已有 `isPreset: Bool`（区分预置/自定义）、`sortOrder: Int`、以及到账单的反向关系 `transactions: [Transaction]`（`:20-21`，可用于引用计数 `category.transactions.count`）。**字段已够，本节点不改模型、无迁移。**
- **删除规则冲突点（R4 核心）**：`LedgerCategory.transactions` 的 `@Relationship` 删除规则当前是 **`.nullify`**（`:20`，删分类→账单 `category` 置 nil = 未分类）。而 R4（DAG 决策 D2）要"删已引用分类时转到『其他』"。二者语义冲突——实现上**必须在删除前手动把该分类的账单逐个改指"其他"，再删分类**，不能只靠 `.nullify`。`.nullify` 保留为底层兜底。
- **Store 缺口（已核实全库零命中）**：`LedgerStore`（`Aubade/Store/LedgerStore.swift`）分类相关只有 `createCategory`（`:26-35`，含 isPreset/sortOrder 参数）和只读 `presetCategories()`（`:38-42`）；**缺 `updateCategory`、缺分类专用删除、缺引用计数**。删除目前只能走通用泛型 `delete<T>`（`:120-123`，直接 `context.delete`）。已有 `setBudget`/`setBalanceBaseline`（`:83-110`）的"写侧收敛"范式可参考风格。
- **"其他"兜底分类定位方式**：预置 seed 中支出侧兜底叫 **"其他"**、收入侧叫 **"其他收入"**（`Aubade/Persistence/PresetCategories.swift:7-8`），**无稳定标志位，只能按 `name + direction` 定位**。已有成熟范式 `RecognitionNormalizer.category(name:direction:in:)`（`Aubade/Features/Recognition/Parsing/RecognitionNormalizer.swift:26-33`）：`fallbackName = (direction == .expense) ? "其他" : "其他收入"`，删除转移逻辑应复用同一口径（按被删分类的 `direction` 选对应兜底分类）。
- **我的页分类区现状**：在 `RootTabView.swift` 的 `ProfilePlaceholderView` 内，`categorySection`（符号本体 `:270-277`，含两次 `categoryTags` 调用 + header"分类（预置）"）当前 `@Query(filter: isPreset==true)`（`:71-72`）**只取预置**、辅助函数 `categoryTags`（`:280-296`）渲染成**只读 capsule 标签流**（注释明说"无点击、无增删改入口"）。自定义分类根本不展示。同文件已有 `InitialBalanceSheet`（`:301`）、`BudgetEditSheet`（`:362`）的成熟 sheet 编辑范式可仿写分类编辑器；`ProfilePlaceholderView` 已持有 `store`（`:90`）与 `modelContext`（`:66`）。
- **原型交互规格（行为事实来源）**：`prototype/app/app.js:826-945` + `data.js:27-49`：
  - 分类管理区：支出分类组 + 收入分类组，预置行标"预置·锁定"、自定义行标"编辑 ›"，底部"＋ 新增自定义分类"；点预置 toast"预置分类不可修改"、不进编辑器。
  - 编辑器：新增可选方向（编辑时方向锁定）；名称 `maxlength=6`；图标 16 选一（`CAT_ICON_CHOICES`）、颜色 8 选一（`CAT_COLOR_CHOICES`）。
  - 新增校验：**同方向重名拒绝**（`addCategory` 返回 null → toast"该方向已有同名分类"）。
  - 删除自定义分类：`categoryUsageCount` 引用计数；有引用时二次确认文案带引用数"有 N 笔账单用了这个分类，删除后这些账单会转到『其他』"，确认后先把账单转"其他"再删。
- **自动分类无需改（DAG 已定）**：DeepSeek 识别的"可选分类"清单由全量分类 `@Query` 喂入，新增自定义分类后天然带上，识别逻辑不用动（该验证归 B03）。本节点只在"分类可增改"后，补一条命中自定义分类的单测即可。

### 与其他节点边界

- 触点与 B01（Analytics 层 `BalanceCalculator`）**不重叠**；与 B03（识别解析链、`Transaction` 模型加字段）**不重叠**。
- **不做 UI 视觉重做**（暖白/晨曦/珊瑚青绿是 B04），本节点只改结构与交互，样式沿用现有 `.background.secondary` 等系统语义。B04 依赖本节点定稿的最近记录 `List` 结构与分类管理区形态。

## 涉及的现有链路

| 关注点 | 文件:行号 | 本节点动作 |
|---|---|---|
| 记账页最近记录区 | `RecordTabView.swift:343-377` | VStack 结构改 `List` + `.swipeActions`；加 `pendingDelete` 态 + `confirmationDialog` |
| 记账页删除态 | `RecordTabView.swift`（新增 `@State`） | 仿账单页 `pendingDelete`/`deleteConfirmBinding` |
| 账单页删除样板 | `LedgerTabView.swift:52-58, 208-231, 266-274` | 只读参考，不改 |
| 共享删除工厂 | `EditorActions.swift:26-30` | 复用 `makeDelete` |
| 分类 Store | `LedgerStore.swift:26-42, 120-123` | 新增 `updateCategory`、分类删除（预置保护+引用计数+转"其他"） |
| 分类模型 | `LedgerCategory.swift:7-33` | 不改（字段/关系已够） |
| "其他"兜底定位 | `RecognitionNormalizer.swift:26-33`、`PresetCategories.swift:7-8` | 复用 `name+direction` 口径 |
| 我的页分类区 | `RootTabView.swift:71-72, 270-296` | `@Query` 放开到全部分类；只读标签流改可管理列表 + 编辑器 sheet |
| 受影响测试 | `RelationshipTests.swift:36-51`、`PresetCategoryTests.swift` | 前者随 D2 改断言；后者幂等保持 |

## 需求范围

### R3 最近记录删除
1. `RecordTabView.recentSection` 从 `VStack+ForEach+Button+Divider` 改为 `List + ForEach + .swipeActions(edge:.trailing)`，左滑露出"删除"（`role:.destructive`）。
2. 新增 `@State pendingDelete: Transaction?` + `confirmationDialog`（文案与账单页一致："删除这笔账单？"/"删除后无法恢复"），确认后复用 `EditorActions.makeDelete` 执行删除。
3. 保留现有点击进编辑 sheet 的行为（`editingTransaction`）；删除后 `@Query` 自动刷新，最近记录、剩余总额、统计同步更新。
4. `List` 需与页面既有滚动结构协调（最近记录在记账页 `ScrollView` 内，改 `List` 后处理高度/嵌套，避免双滚动；具体形态在 TRD 定）。

### R4 分类 Store 能力
5. `LedgerStore.updateCategory(_:name:icon:color:)`：更新自定义分类的名称/图标/颜色；**预置分类（isPreset==true）拒绝改名**（图标/色按开放项"暂锁全部字段"一并拒绝，待评审拍板）。同方向重名拒绝。
6. `LedgerStore` 分类删除方法（如 `deleteCategory(_:)`）：**预置分类拒删**；删除前用反向关系统计引用数；有引用时**先把该分类的账单逐笔转到对应方向的兜底分类**（支出→"其他"、收入→"其他收入"，按 `name+direction` 定位，复用 `RecognitionNormalizer` 口径），再删分类。
7. 引用计数能力：`category.transactions.count`（或等价查询），供 UI 展示"N 笔将转移"。

### R4 分类管理 UI
8. 我的页 `categorySection` 的 `@Query` 从"仅预置"放开到**全部分类**（含自定义），按 `direction` 分组 + `sortOrder` 排序。
9. 只读标签流改为**可管理列表**：预置行标"预置·锁定"、点击提示"预置分类不可修改"不进编辑；自定义行标"编辑 ›"、点击进编辑器；底部"＋ 新增自定义分类"入口。
10. 分类编辑器 sheet（仿 `InitialBalanceSheet`/`BudgetEditSheet`）：新增时可选方向（编辑时方向锁定）、名称输入（限 6 字）、图标网格选择（16 选一，对齐原型 `CAT_ICON_CHOICES`）、颜色网格选择（8 选一，对齐原型 `CAT_COLOR_CHOICES`）；保存走 Store 新方法；新增重名 → 拒绝提示。
11. 删除自定义分类：编辑器内提供删除入口，被引用时二次确认文案带引用数与"转到『其他』"说明，确认后走 Store 删除方法（转移 + 删）。

### 测试
12. 新增/更新：`updateCategory`（含预置拒改名、同方向重名拒绝）、分类删除（预置拒删、引用计数、删已引用先转对应兜底分类）用例。
13. `RelationshipTests.testDeleteCategoryNullifiesTransaction`（`:36-51`）：现锁"删分类后 category 变 nil"。**厘清两条删除路径**——泛型 `store.delete(category)` 仍走 `.nullify`（此测试可保留或改名说明"底层泛型删除仍 nullify"）；R4 新分类删除方法走"转其他"，新增对应断言测试。TRD 阶段定具体保留/改写策略。
14. 补一条命中自定义分类的自动分类单测（验证新增自定义分类后能被识别选中；不改识别逻辑）。
15. `PresetCategoryTests` 幂等保持（本节点不动预置 seed 逻辑）。

## 不做什么

- **不改数据模型**：不给 `LedgerCategory`/`Transaction` 加字段，无 SwiftData 迁移（迁移是 B03）。
- **不动识别链路**：不改 DeepSeek prompt、`RecognitionEntry`、`RecognitionNormalizer` 逻辑（R4 自动分类天然生效，验证归 B03）。
- **不做 UI 视觉重做**：不引入暖白/晨曦/珊瑚青绿 token，不改现有配色与圆角风格（R6/B04 范畴）。
- **不改账单页删除**：账单页已有侧滑删除，仅作 R3 对齐样板，不改动。
- **不引入自造侧滑手势**：对齐账单页原生 `List.swipeActions`，不移植原型 `swipeRow`。
- **不放开预置分类图标/颜色编辑**（开放项，暂锁；待用户评审拍板后再定是否调整）。
- **不改预置分类 seed / 幂等逻辑**。

## 验收标准

1. **最近记录左滑删除**：记账页最近记录左滑露出"删除"→ 点击弹二次确认"删除这笔账单？"→ 确认后该笔从最近记录消失，剩余总额与统计同步更新，交互与账单页一致。
2. **删除取消不误删**：左滑→删除→二次确认弹窗点"取消"，该笔保留、无变化。
3. **新增自定义分类**：我的页分类管理区"＋ 新增自定义分类"→ 选方向"支出"、名称"宠物"、选图标与颜色 → 保存后出现在支出分类组；回记账页手动记账，分类选择器可见"宠物"。
4. **同方向重名拒绝**：新增分类填一个该方向已存在的名称 → 提示"该方向已有同名分类"，不创建。
5. **编辑自定义分类**：点自定义分类"编辑 ›"→ 改名称/换图标/换颜色 → 保存后列表与记账选择器同步更新。
6. **预置分类锁定**：点任一预置分类（如"食"）→ 提示"预置分类不可修改"，不进编辑器；无删除入口。
7. **删除未引用自定义分类**：删一个没有账单引用的自定义分类 → 二次确认"确定删除这个自定义分类？"→ 确认后消失。
8. **删除已引用自定义分类转"其他"（支出）**：给自定义支出分类"宠物"记 2 笔支出，删"宠物"→ 提示"有 2 笔账单用了这个分类，删除后这些账单会转到『其他』"→ 确认后：分类删除，那 2 笔账单分类变为支出兜底"其他"（**非未分类/nil**）。
9. **删除已引用自定义分类转"其他收入"（收入，方向兜底）**：给自定义收入分类记 1 笔收入并删除 → 该笔账单分类转为收入兜底 **"其他收入"**（而非支出"其他"、非 nil）。此条与验收 8 区分方向兜底，是对原型 `data.js:940` 统一转"其他"的方向纠偏，须独立验证不漏测。
10. **单测全绿**：`updateCategory`、分类删除（预置拒删、引用计数、删已引用转对应兜底）、命中自定义分类的自动分类用例通过；`RelationshipTests` 按厘清后的两条删除路径断言通过；`PresetCategoryTests` 幂等仍通过。
11. **无回归**：B01 的剩余总额口径、既有账单/识别/统计功能复跑单测全绿；数据模型无变更。
