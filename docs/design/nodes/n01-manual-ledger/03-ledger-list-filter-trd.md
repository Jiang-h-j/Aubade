# TRD 03 - 账单列表 + 筛选 + 编辑删除闭环

## 给用户看的摘要

这一片把「账单」Tab 做成真正能翻的流水页，闭合"看流水 → 改 → 删"。账单按日期分组倒序排列，每笔带彩色分类标签、商户/备注摘要、醒目金额（支出 `-` 深色、收入 `+` 绿色）。顶部筛选栏能按分类筛（全部/各分类）、按时间筛（全部/本周/本月/自定义起止）。点任意一笔进编辑页（复用上一片做的编辑组件）改字段保存；也能删除，删除会二次确认防误删。空账本和筛选无结果都有对应提示。做完这片，N01 的手动记账闭环全通——你的 iPhone 上就有第一个能天天用的记账 App。

## 本 TRD 负责什么

- **账单 Tab 流水列表**（替换切片 01 的 `LedgerTabPlaceholder`）：按 `occurredAt` 日期分组、组内倒序；每项 = 分类彩色标签 + 商户/备注摘要 + 方向金额。**不含顶部汇总卡**（→ N02）。
- **筛选**：分类（全部 + 各分类）× 时间范围（全部 / 本周 / 本月 / 自定义起止），可叠加，结果与条件一致。
- **详情/编辑**：点账单进编辑页，复用切片 02 的 `TransactionEditor(.edit(tx))` 改字段，经 `updateTransaction` 保存。
- **删除**：二次确认后经 `LedgerStore.delete` 删除，返回列表。
- **空状态**：无账单引导去记账；筛选无结果显示对应空态。

对齐 PRD 需求范围 §4/§5；验收标准第 2（列表分组展示）、3（编辑同步）、4（删除+二次确认）、5（分类筛选）、6（时间筛选，叠加）、10（无汇总卡）条。

## 当前代码事实与上下游

- **读取**：`Transaction.occurredAt`（`Aubade/Models/Transaction.swift:9`）分组/排序键；`LedgerStore.fetch`（`Aubade/Store/LedgerStore.swift:17-22`）或视图层 `@Query`。删除用 `LedgerStore.delete`（`:92-95`，泛型 `context.delete + save`）。
- **编辑**：`LedgerStore.updateTransaction(_:apply:)`（`:64-68`）；apply 内改 `amount/direction/category/occurredAt/merchant/note`，内部刷新 `updatedAt`（验收 3 要求 updatedAt 刷新）。
- **分类**：筛选栏的"各分类"来自全部分类（`fetch(LedgerCategory.self, sortBy:[SortDescriptor(\.sortOrder)])`），前向兼容 N07；当前预置 8 条。
- **上游（切片 01/02）**：
  - `LedgerTabPlaceholder`（`RootTabView` 内）本片替换为 `LedgerTabView`。
  - `CategoryStyle`（切片 01）：列表标签 emoji + 色、分类筛选项配色。
  - `AmountFormat`（切片 02）：方向金额串 + 色（`-35.55` 深色 / `+8,000.00` 绿）。
  - `TransactionEditor` + `EditorMode.edit`（切片 02）：编辑页复用；本片补 `onDelete` 注入二次确认 + delete。
- **注入契约**：同切片 02——`@Environment(\.modelContext)` + `@Query`；写经 `LedgerStore`；禁链式 `container().mainContext`（N00 SIGTRAP 坑，memory `swiftdata_dangling_context`）。

## 设计方案

### 1. 筛选状态与数据获取策略

PRD §当前理解点名了 iOS 17 动态 `@Query` 的取舍。**本片决策：`@Query` 取全量 + 内存过滤/分组**，理由：

- N01 数据量小（个人手动记账），全量取 + 内存 filter 简单可靠，且增删改后 `@Query` 自动刷新（验收 2/3/7 的实时同步）。
- 动态 `FetchDescriptor`（分类/时间可变 predicate）在 iOS 17 需重建 descriptor，`#Predicate` 对可选关系 `category` 的比较、对区间的表达都更易踩坑；相比之下内存过滤直观、可单测。
- 若后续数据量增长成为问题，N02+ 可换 predicate——本片不为假想规模预造复杂度（KISS）。

**筛选模型**（值类型，可单测）：
```
enum CategoryFilter: Hashable { case all; case some(LedgerCategory) }   // 用 category.id 比较
enum DateRangeFilter: Hashable {
    case all, thisWeek, thisMonth
    case custom(start: Date, end: Date)
    func contains(_ date: Date, calendar: Calendar) -> Bool   // 纯函数，可单测边界
}
```
- `thisWeek`：`calendar.dateInterval(of: .weekOfYear, for: now)`；`thisMonth`：`.month`。**边界口径（防 off-by-one）**：`dateInterval` 返回的 `.end` 是**下一周期起点（排他）**，而 `DateInterval.contains` 含右端点——故 `contains` 判定统一用**半开区间** `interval.start <= date && date < interval.end`，不要直接用 `DateInterval.contains`（会把下周期第一刻误纳入）。自定义：`start` 取 `startOfDay(start)`、`end` 取 `startOfDay(after: end)`，同样半开 `[start, end)`（等价含用户所选止日整天）。
- 过滤链：全量 → 按 `CategoryFilter`（`all` 不筛；`some(c)` 留 `tx.category?.id == c.id`）→ 按 `DateRangeFilter.contains(tx.occurredAt)` → 结果。分类 + 时间两条件**叠加**（验收 6）。

### 2. 分组与列表 `LedgerTabView`

- 过滤后结果按 `occurredAt` 所属**自然日**分组：`Dictionary(grouping:) { calendar.startOfDay(for: $0.occurredAt) }`，日期键倒序，组内按 `occurredAt` 倒序。
- 用 `List` + `Section`（组头显示日期，如"7月10日"）。每行 `LedgerRowView`：左 `CategoryStyle` emoji + 彩色分类标签（nil 分类显示"未分类"）、中商户或备注摘要（商户优先，空则备注，再空则留白）、右 `AmountFormat` 方向金额串 + 色。
- 组头日期格式：本地化 `M月d日`（`Date.FormatStyle` 或 `DateFormatter`）。

### 3. 筛选栏 UI

- 顶部两个选择控件（原型 §4.1 `[全部分类▾] [本月▾]`）：
  - 分类：`Menu`/`Picker` 列「全部」+ 各分类（emoji + 名，`CategoryStyle`）。
  - 时间：`Menu`/`Picker` 列 全部 / 本周 / 本月 / 自定义。选「自定义」弹两个 `DatePicker`（起、止）——止不早于起；自定义**同样禁未来**（与手动记账口径一致，`in: ...Date()`）。
- 筛选栏不含汇总卡（验收 10；汇总区 → N02）。

### 4. 详情 / 编辑页

- 列表行 / 记账页最近记录点击 → push（`NavigationStack` + `NavigationLink`）呈现 `TransactionEditor(mode: .edit(tx))`。**选 push**（详情页语义，原型"点某笔进详情"），账单 Tab 用 `NavigationStack` 包裹。（记账页最近记录在切片 02 用 `.sheet` 呈现同一 editor——两处呈现容器不同但**落库逻辑同源**，见下。）
- 保存：复用切片 02 落地的 `EditorActions` 构造 `edit` 的 `onSave`（内部 `LedgerStore(context).updateTransaction(tx){ 回写 amount/direction/category/occurredAt/merchant/note }`，`updatedAt` 由 Store 内部刷新，验收 3）。**不在本片重写 update 逻辑**，避免与 02 两处重复。保存后返回列表，`@Query` 自动同步（验收 3）。
- 编辑页显示商户行（`.edit` 模式，切片 02 已定）。

### 5. 删除 + 二次确认

- 两个删除入口，都走二次确认（原型 §5「删除账单」）：
  - 列表行侧滑 `.swipeActions` → 删除按钮 → `.confirmationDialog`/`.alert` 二次确认。
  - 编辑页底部「删除这笔」（切片 02 预留的 `onDelete` 钩子，本片经 `EditorActions` 注入二次确认 + delete）→ 二次确认。
- 确认后 `LedgerStore(context).delete(tx)`；编辑页删除后 pop 回列表；列表侧滑删除后 `@Query` 自动移除该行。取消则保留（验收 4）。

## 修改点

**改**
- `Aubade/Features/AppShell/RootTabView.swift`：账单 Tab 从 `LedgerTabPlaceholder` 换为 `LedgerTabView`（用 `NavigationStack` 包裹以支持进编辑页）。
- `Aubade/Features/Record/RecordTabView.swift`（切片 02）：最近记录点击进编辑的路径，与本片列表进编辑复用同一 `TransactionEditor(.edit)`；若切片 02 已用 sheet，本片保持不破坏，仅确保编辑保存/删除逻辑一致（编辑 onSave/onDelete 抽为共享构造，避免两处重复）。

**新增**
- `Aubade/Features/Ledger/LedgerTabView.swift`：账单 Tab（筛选栏 + 分组列表 + 空态 + NavigationStack）。
- `Aubade/Features/Ledger/LedgerRowView.swift`：单行（分类标签 + 摘要 + 方向金额）。
- `Aubade/Features/Ledger/LedgerFilter.swift`：`CategoryFilter` / `DateRangeFilter` + 过滤/分组纯函数。
- `Aubade/Features/Ledger/TransactionDetailView.swift`：编辑页容器（包 `TransactionEditor(.edit)` + update onSave + delete onDelete + 二次确认）。
- `AubadeTests/LedgerFilterTests.swift`：`DateRangeFilter.contains` 本周/本月/自定义边界（区间内外各一）、分类过滤、两条件叠加、分组倒序。

**不改**
- `LedgerStore`（复用 fetch/update/delete，签名不动）、`CategoryStyle`/`AmountFormat`/`TransactionEditor`（复用，不改其对外形态）、所有 `Models/*`、`AubadeApp`、`PersistenceController`。

## 验证点

1. **编译 + 单测**：`xcodebuild build`、`xcodebuild test` 成功；`LedgerFilterTests` 全绿。边界须**钉死半开区间**：本周/本月**上边界**——落在下一周期第一刻（如本月最后一天 23:59:59 判入、下月 1 号 00:00:00 判出）；自定义起止含所选止日整天、止日次日 00:00 判出；分类过滤、两条件叠加、分组倒序各覆盖。
2. **列表分组展示（验收 2）**：多笔不同日期账单按 `occurredAt` 日期倒序分组、组内倒序；每项含分类彩标 + 方向金额（`-`深色/`+`绿）；空账本显示"去记第一笔"引导。
3. **编辑同步（验收 3）**：点一笔进编辑页改金额/分类/时间保存 → 列表对应项即时更新；`updatedAt` 刷新（DEBUG/单测佐证）。
4. **删除 + 二次确认（验收 4）**：列表侧滑删除与编辑页「删除这笔」均弹二次确认；确认后该笔消失、取消保留。
5. **分类筛选（验收 5）**：选「食」列表仅剩食类；切「全部」恢复。
6. **时间筛选 + 叠加（验收 6）**：分别选本周/本月/自定义，仅显示区间内账单（边界内外各验一笔）；分类 + 时间叠加结果一致；「全部」显示所有；自定义禁选未来。
7. **无越界（验收 10）**：账单页顶部无汇总卡（无剩余/本月支出/本月收入区）。
8. **闭环回归**：手动记一笔（切片 02）→ 账单页看到 → 改 → 删，全链路通；记账页今日已记/最近记录随删除同步变化（验收 7 的删除侧）。

## 不做什么

- 不做账单页顶部汇总卡与任何统计聚合、剩余金额计算（→ N02）。
- 不做识别相关：结果卡片识别数据填充、折叠原文渲染、"删除这笔=撤销入账"的 AI 语义（本片删除就是普通删账单）（→ N03~N06）。
- 不做统计/我的 Tab 功能（→ N02/N07，仍是切片 01 的占位）。
- 不做分类用户增删改（→ N07）；筛选分类项只读取已有。
- 不为假想大数据量引入动态 predicate / 分页（本片全量内存过滤，KISS）。
- 不自建 `ModelContainer`、不链式 `container().mainContext`；不改 `LedgerStore` 签名与任何 N00 数据层代码。
