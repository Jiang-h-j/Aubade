# TRD 02 - 可复用编辑组件 + 手动记账 + 记账 Tab

## 给用户看的摘要

这一片打通"自己记一笔"的完整闭环，也是本节点技术上最关键的一片。核心是做一个**可复用的账单编辑组件**——它能以两种模式工作：「新建」（手动记账，填完保存新增一笔）和「编辑」（改一笔已有账单，下一片账单列表会用到）。之所以做成一个组件，是因为后面的截图/语音/文本识别（N03~N06）识别出结果后弹的卡片，就直接复用它，不重复造。做完这片：记账页点「手动输入」→ 填金额、选支出/收入、选分类、挑日期（不能选未来）、写备注 → 保存，立刻入账；记账页顶部「今日已记 N 笔」和下方「最近 4 笔」实时更新；另外三个入口（截图/语音/文本）先做成占位提示。

## 本 TRD 负责什么

- 新增**可复用编辑组件** `TransactionEditor`：支持「新建草稿」（无绑定 Transaction，保存时 `createTransaction`）与「编辑已有」（绑定 Transaction，保存时 `updateTransaction`）两种模式。字段集对齐原型 §4.3 结果卡片（金额/方向/分类/时间/商户/备注），为 N03~N06 预留复用点。
- **手动记账**：以 `TransactionEditor` 的"新建"模式呈现手动表单（原型 §4.4，**不含商户输入**），保存经 `LedgerStore.createTransaction(... source: .manual)`。
- **记账 Tab** 真实视图替换切片 01 临时占位：标题「记一笔」+「今日已记 N 笔」chip、四入口网格（仅手动可用，余三占位）、「最近记录」最近 4 笔 + 「全部 ›」跳账单 Tab。

对齐 PRD 需求范围 §2/§3/§6；验收标准第 1（手动新增入账）、7（记账页即时反馈）、9（编辑组件双模式可复用）、10（三占位入口不假入账）条。**本片只做"新建"模式的完整落地 + "编辑"模式的组件能力**；"从列表进编辑页"的入口在切片 03。

## 当前代码事实与上下游

- **写入 API**：`LedgerStore.createTransaction`（`Aubade/Store/LedgerStore.swift:48-61`）签名 `(amount: Decimal, direction:, occurredAt:, category: LedgerCategory? = nil, merchant: String? = nil, note: String? = nil, cardTail: String? = nil, source: TransactionSource, rawText: String? = nil, imageRef: String? = nil) throws -> Transaction`；内部 `let now = Date()` 填 `createdAt = updatedAt = now`（`:53`），`occurredAt` 由调用方传入（表单"日期"即此）。手动入口：`source: .manual`，cardTail/rawText/imageRef 留 nil。
- **更新 API**：`LedgerStore.updateTransaction(_ tx:, apply: (Transaction) -> Void)`（`:64-68`）——`apply` 内改字段，内部 `tx.updatedAt = Date()` 后 `context.save()`。编辑模式用此。
- **分类读取**：`LedgerStore.presetCategories()`（`:38-42`）返回 `isPreset==true` 按 `sortOrder` 升序。PRD §当前理解要求"分类选择器查**全部**分类而非硬编码"以对 N07 前向兼容 → 用 `fetch(LedgerCategory.self, sortBy: [SortDescriptor(\.sortOrder)])`（`:17`）取全部，再按当前 `direction` 过滤（`LedgerCategory.direction`，`Aubade/Models/LedgerCategory.swift:11`）。当前库仅预置 8 条，效果等价，但代码前向兼容 N07 自建分类。
- **模型字段**：`Transaction`（`Aubade/Models/Transaction.swift:5`）`amount: Decimal`（正值）、`direction`、`occurredAt`、`category: LedgerCategory?`、`merchant?`、`note?`、`source`、`createdAt`、`updatedAt`。金额存正值方向单列。
- **枚举**：`TransactionDirection`（`Enums.swift:4`，`.expense`/`.income`，`CaseIterable`）驱动方向选择器；`TransactionSource.manual`（`Enums.swift:17`）。
- **上游（切片 01）**：`RootTabView` 的记账 Tab 当前是 `RecordTabPlaceholder`（本片替换）；`CategoryStyle`（`Aubade/Features/Shared/CategoryStyle.swift`）供分类选择器显示 emoji + 色。
- **注入契约**（PRD §目标 8，延续 N00 §11 硬约束）：读写经注入的 `ModelContext` / `LedgerStore`，**不自建 `ModelContainer`**。视图用 `@Environment(\.modelContext)` 取 context 构造 `LedgerStore(context)`；`@Query` 取分类/最近记录。**禁止链式 `container().mainContext`**（N00 记录的 SIGTRAP 悬垂 context 坑，见 memory `swiftdata_dangling_context`）。

## 设计方案

### 1. 可复用编辑组件 `TransactionEditor`

新增 `Aubade/Features/Editor/`。分两层：**纯值模型 + 视图**，使编辑逻辑可单测、可被 N03+ 复用。

**`TransactionDraft`（值类型，可单测的表单状态）**
```
struct TransactionDraft {
    var amountText: String        // 原始输入串，保存时解析为 Decimal
    var direction: TransactionDirection
    var category: LedgerCategory?
    var occurredAt: Date
    var merchant: String          // 空串视为 nil
    var note: String
    // 校验：金额解析成功且 > 0 才允许保存
    var parsedAmount: Decimal?    // Decimal(string:) 结果，用户区域小数点兜底
    var isValid: Bool { parsedAmount.map { $0 > 0 } ?? false }
}
```
- 金额解析：`Decimal(string: amountText)`（locale 无关，恒以 `.` 为小数点；zh_CN happy path 无碍，逗号小数区域的 i18n 留待后续换 `Decimal(string:locale:)`，本片不做）；非法/空/零 → `isValid == false`，保存按钮禁用。以 `Decimal` 落库避免浮点误差（验收 1）。

**`EditorMode`（区分新建/编辑）**
```
enum EditorMode {
    case create(direction: TransactionDirection)   // 手动新建，默认支出
    case edit(Transaction)                          // 绑定已有（切片 03 用）
}
```

**`TransactionEditor`（SwiftUI View）**
- 依 `EditorMode` 初始化 `TransactionDraft`：`create` → 空表单（金额空、方向默认 `.expense`、分类 nil、`occurredAt = Date()`、商户/备注空）；`edit(tx)` → 从 `tx` 各字段回填。
- 表单区（原型 §4.3 字段序）：金额（`.keyboardType(.decimalPad)`）、方向（`Picker`/分段，`TransactionDirection.allCases`）、分类（选择器，见下）、时间（`DatePicker`，见下）、**商户**、备注。
- **商户字段的模式差异**（PRD 已确认约定 1）：`create` 模式（手动表单）**隐藏商户输入**（保持 3 步内最短路径，原型 §4.4）；`edit` 模式**显示商户**。用 `mode` 判定是否渲染商户行。组件内部始终支持 `merchant` 字段（供 N03+ 识别填充），仅"手动新建"这一 UI 入口隐藏它。
- **分类选择器**：随当前 `direction` 过滤——支出只列支出类、收入只列收入类，按 `sortOrder` 排序，每项显示 `CategoryStyle.emoji(for:)` + 名。**切换方向时若已选分类与新方向不符则清空**（避免"支出选了食、切到收入仍挂食"）。允许"不选"= category nil。
- **时间选择器**（PRD 已确认约定 2）：`DatePicker` 限 `in: ...Date()`（`PartialRangeThrough`），**禁未来**；默认今天。
- 保存动作由**调用方注入闭包** `onSave: (TransactionDraft) throws -> Void`，`TransactionEditor` 不直接持有 `LedgerStore`——这样新建（create）和编辑（update）的落库差异留在调用方，组件只管表单与校验。`isValid == false` 时保存禁用。
- `edit` 模式额外提供删除入口的**占位钩子** `onDelete: (() -> Void)?`（切片 03 注入二次确认 + `delete`）；本片 `create` 模式不传，不渲染删除。
- 原型 §4.3 的"折叠原文展示区"（rawText）：本片**预留可选属性但不渲染**（手动入口 rawText 为空），结构上为 N03+ 留位（PRD §6）。

**`EditorActions`（编辑落库的共享构造，避免 02/03 重复）**
- 新增一个轻量构造（函数或小结构），给定 `LedgerStore` + `Transaction`，产出 `edit` 模式的 `onSave`（内部 `updateTransaction(tx){ 回写 draft 各字段 }`）与 `onDelete`（切片 03 注入二次确认后 `delete(tx)`）。记账页最近记录（本片，sheet）与账单列表（切片 03，push）都用它构造编辑动作，保证两处落库逻辑单一来源。本片先落 `onSave`（update）；`onDelete` 的二次确认 UI 由切片 03 补齐。

### 2. 手动记账入口 `ManualEntryView`

- 记账页四入口点「✏️ 手动输入」→ `.sheet` 弹 `ManualEntryView`，内部用 `TransactionEditor(mode: .create(direction: .expense), onSave:)`。
- `onSave` 闭包：解析 `draft.parsedAmount!`（isValid 保证非 nil）→ `LedgerStore(context).createTransaction(amount:direction:occurredAt:category:merchant:nil,note:source:.manual)` → 成功 `dismiss()`。商户在手动模式恒为 nil。
- 保存后记账页的「今日已记」「最近记录」经 `@Query` 自动刷新（同一注入 context，验收 1/7）。

### 3. 记账 Tab `RecordTabView`（替换切片 01 的 `RecordTabPlaceholder`）

原型 §4.2 布局：
- 顶部：标题「记一笔」+ 右上「今日已记 N 笔」chip。**N = `createdAt` 落在今天的账单数**（PRD 已确认约定 3：今日已记按 createdAt）。用 `@Query` 取全部 Transaction 后在内存按 `Calendar.current.isDateInToday($0.createdAt)` 计数（当前数据量小，简单可靠；避免动态 predicate 复杂度）。
- 四入口网格 2×2：📷 截图识别 / 🎤 语音记账 / 📋 文本识别 / ✏️ 手动输入。**仅手动可用**（点开 sheet）；其余三个点击弹轻提示"该入口将在后续版本提供"（`.alert` 或短 toast），**不做假流程、不假入账**（验收 10）。
- 「最近记录」：`@Query(sort: \Transaction.occurredAt, order: .reverse)` 取前 4 笔（PRD 已确认约定 3：最近记录按 **occurredAt 倒序**）。每项显示 `CategoryStyle` 标签 + 商户/备注摘要 + 方向金额。点某笔 → `.sheet` 弹 `TransactionEditor(mode: .edit(tx))`，**本片即接 `updateTransaction` 落库**（onSave 内 `LedgerStore(context).updateTransaction(tx){ ... }`），保存后 `@Query` 自动刷新——即"编辑保存"在本片就完整闭环，不留"可进编辑但保存未接"的中间态。此编辑 onSave/onDelete 构造抽为共享 `EditorActions`（见下），切片 03 的列表进编辑（push 呈现）复用同一落库逻辑。「全部 ›」→ 切 `selectedTab = .ledger`（用切片 01 引入的 selection 绑定；本片通过 `@Binding` 传入切 Tab 的能力）。
- 空账本：最近记录区显示占位"还没有记录，点『手动输入』记第一笔"。

**跨 Tab 跳转**：记账 Tab 需要切到账单 Tab。切片 01 已在 `RootTabView` 用 `@State selectedTab`；本片把切 Tab 能力经 `@Binding var selection: AppTab` 传入 `RecordTabView`，或用一个轻量 `@Observable` 路由。选**`@Binding` 直传**（最简，无需引入路由对象）。

### 4. 金额展示辅助 `AmountFormat`

新增 `Aubade/Features/Shared/AmountFormat.swift`：把 `Decimal` + `direction` 渲染成带符号千分位串（`-35.55` / `+8,000.00`）与方向色（收入绿 / 支出 `.primary`）。PRD 验收 1 要求千分位统一、已确认约定 4 定方向色。本片记账页「最近记录」用它；切片 03 列表复用。用 `NumberFormatter`（`.decimal` + 2 位小数）或 `Decimal.formatted`。

## 修改点

**改**
- `Aubade/Features/AppShell/RootTabView.swift`：记账 Tab 从 `RecordTabPlaceholder` 换为 `RecordTabView(selection: $selectedTab)`；传入 selection 绑定。

**新增**
- `Aubade/Features/Editor/TransactionDraft.swift`：`TransactionDraft` 值模型 + 校验/解析。
- `Aubade/Features/Editor/TransactionEditor.swift`：`EditorMode` + `TransactionEditor` 视图（双模式、字段集、方向过滤分类、禁未来日期、onSave/onDelete 注入）。
- `Aubade/Features/Record/ManualEntryView.swift`：手动新建 sheet，包 `TransactionEditor(.create)` + createTransaction 落库。
- `Aubade/Features/Record/RecordTabView.swift`：记账 Tab 真实视图（今日已记/四入口/最近记录/全部跳转）。
- `Aubade/Features/Shared/AmountFormat.swift`：金额方向格式化 + 色。
- `AubadeTests/TransactionDraftTests.swift`：金额解析（合法/空/零/负/非数字）、isValid、edit 模式回填正确性。
- `AubadeTests/AmountFormatTests.swift`：`-35.55`/`+8,000.00` 千分位与符号、Decimal 无浮点误差。

**不改**
- `LedgerStore`（复用 create/update/fetch/presetCategories，签名不动）、所有 `Models/*`、`AubadeApp`、`PersistenceController`、`PresetCategories`、`CategoryStyle`（切片 01 已定）。

## 验证点

1. **编译 + 单测**：`xcodebuild build` 与 `xcodebuild test` 均成功；`TransactionDraftTests`、`AmountFormatTests` 全绿。
2. **手动新增入账（验收 1）**：记账页「手动输入」填支出 35.55 / 分类食 / 今天 / 备注"午餐"保存 → 最近记录立即出现该笔、金额显示 `-35.55`；再记收入 8000 / 分类工作 → 显示 `+8,000.00`（千分位）。金额 Decimal 写入读回无浮点误差（单测佐证）。
3. **今日已记（验收 7）**：新增一笔后「今日已记 N 笔」+1（按 createdAt=今天）；最近记录按 occurredAt 倒序、最多 4 笔。
4. **禁未来日期（已确认约定 2）**：手动表单日期选择器无法选到明天及以后。
5. **方向过滤分类**：方向切支出时分类只列支出 6 类、切收入只列收入 2 类；切换方向后原不符分类被清空。
6. **三占位入口不假入账（验收 10）**：截图/语音/文本点击仅弹"后续版本提供"提示，账单数不变。
7. **编辑回填 + 保存闭环（验收 9 双模式的完整落地）**：`TransactionEditor(.edit(tx))` 正确回填 tx 各字段（`.edit` 显示商户行、`.create` 隐藏）；记账页点最近记录一笔进 sheet 改金额/分类保存 → `updateTransaction` 落库、列表即时刷新、`updatedAt` 刷新（单测 + 肉眼确认）。即"新建 create + 编辑 update"两模式在本片均保存成功，非仅回填。
8. **全部跳转**：记账页「全部 ›」切到账单 Tab（本片账单 Tab 仍为占位，切换成功即可）。

## 不做什么

- 不做账单 Tab 的流水列表/筛选/日期分组（→ 切片 03）；本片"全部 ›"只切 Tab。
- 不做删除功能的实际落库（→ 切片 03 注入 onDelete）；本片 create 模式不含删除。
- 不做识别结果卡片的 AI 专属交互：折叠原文的**渲染**、"删除这笔=撤销入账"、rawText/imageRef 填充（→ N03~N06）；本片仅预留结构。
- 不做手动表单的商户输入（PRD 已确认约定 1，手动 create 隐藏商户）；组件内部保留字段供 N03+。
- 不自建 `ModelContainer`；不使用链式 `container().mainContext`（N00 SIGTRAP 坑）。
- 不改 `LedgerStore` 方法签名、不动任何 N00 数据层代码。
