# TRD 01 - R3 最近记录删除

## 给用户看的摘要

记账页底部"最近记录"现在只能点进去改、删不掉。这一片把它做成能左滑删除、删前弹一次确认，跟账单页完全一个手感。删掉后剩余总额和统计自动跟着变。只改记账页这一块，不碰账单页、不碰数据。

## 本 TRD 负责什么

- 把 `RecordTabView.recentSection` 从手搓的 `VStack + ForEach + Button + Divider` 改成能左滑删除的结构。
- 左滑露出"删除" → 二次确认"删除这笔账单？/删除后无法恢复" → 确认后删除，交互与账单页一致。
- 保留现有"点行进编辑 sheet"行为不变。
- 删除后 `@Query` 自动刷新，最近记录/剩余总额/统计同步更新。

## 当前代码事实与上下游

- `RecordTabView.recentSection`（`Aubade/Features/Record/RecordTabView.swift:343-377`）：`VStack(spacing:0)` + `ForEach(recentFour)` + `Button(.plain){ editingTransaction = tx }` + `Divider`，外套 `.background(.background.secondary, in: RoundedRectangle(cornerRadius:12))`。**不是 List，当前无任何删除入口。**
- 该 section 位于页面 `ScrollView { VStack(spacing:24){ entryGrid; recentSection } }` 内（`:202-208`）。**这是本片关键约束：`List` 自带滚动，直接塞进 `ScrollView` 会双层滚动 + 高度塌陷。**
- 数据源：`recentFour = Array(recentTransactions.prefix(4))`（`:196-198`），`recentTransactions` 是 `@Query(sort:\.occurredAt, order:.reverse)`（`:52`）。删除后 `@Query` 自动刷新。
- 点击进编辑：`editingTransaction = tx` → `.sheet(item:$editingTransaction)`（`:267-269`）→ `editSheet(for:)`（`:394-402`，复用 `EditorActions.makeUpdate`，明确不注 onDelete）。**本片保留此行为。**
- 账单页删除样板（对齐对象，只读参考）：`LedgerTabView.swift`
  - 删除态 `@State pendingDelete: Transaction?`（`:20`）
  - `.swipeActions(edge:.trailing){ Button(role:.destructive){ pendingDelete = tx } }`（`:219-225`）
  - `deleteConfirmBinding`（`:266-269`）+ `.confirmationDialog("删除这笔账单？", ... presenting: pendingDelete){ Button("删除",role:.destructive){ delete(tx) } Button("取消",role:.cancel){ pendingDelete=nil } } message: { Text("删除后无法恢复") }`（`:52-58`）
  - `delete(_:)`（`:271-274`）：`EditorActions.makeDelete(store:store, tx:tx)()` + `pendingDelete=nil`
- 共享删除工厂：`EditorActions.makeDelete(store:tx:)`（`Aubade/Features/Editor/EditorActions.swift:26-30`）返回 `()->Void`，内部 `try? store.delete(tx)`。直接复用。
- SwiftData 悬垂约束：本片走"列表侧滑置 `pendingDelete` → 页面级 `confirmationDialog` 确认 → 删除"，删除不在 sheet 内触发，与账单页同构，无悬垂风险（不同于 `DeepLinkResultSheet:431-441` 那种 sheet 内删除需先 dismiss）。

## 设计方案

### 双滚动问题的取舍（本片核心决策）

最近记录固定最多 4 行、且嵌在整页 `ScrollView` 内。两条可选路径：

- **方案 A（选定）：保持手搓行结构 + 每行 `.swipeActions`。** 问题是 `.swipeActions` 是 `List` 行专属修饰符，脱离 `List` 无效。故需局部引入 `List`，但用 `.frame(height:)` 固定高度 + `.scrollDisabled(true)` 关掉 `List` 自身滚动，让它作为"不滚动的静态列表"嵌进外层 `ScrollView`，规避双滚动。
- **方案 B（弃用）：整页从 `ScrollView` 改 `List`。** 改动面过大，牵动 `entryGrid` 布局与页面所有 sheet/alert 修饰符挂载点，超出 R3 范围、风险高。

**选定方案 A**：`recentSection` 内容区从 `VStack` 换成 `List`：

```
List {
    ForEach(recentFour) { tx in
        Button { editingTransaction = tx } label: { RecentTransactionRow(tx: tx) }
            .buttonStyle(.plain)
            .listRowInsets(...)          // 贴合原 padding 观感
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { pendingDelete = tx } label: { Label("删除", systemImage: "trash") }
            }
    }
}
.listStyle(.plain)
.scrollDisabled(true)                    // 关 List 自身滚动，交给外层 ScrollView
.frame(height: CGFloat(recentFour.count) * 行高)   // 固定高度，避免 List 在 ScrollView 内高度塌陷
```

- 行高常量在本片内定义（估算单行高度，含垂直 padding），TRD 不写死数值，实现时按 `RecentTransactionRow` 实际观感取值并注释来源。
- **固定行高的前提与脆弱点**：`.frame(height: count * 行高)` 依赖"最近记录行恒为单行定高"。`RecentTransactionRow`（`:465-502`）当前 subtitle `.lineLimit(1)`、单行结构，此假设成立；但若日后行内容可换行或遇 Dynamic Type 大字号放大，固定高度会裁切/留白。实现时若观感失准，改用 `.fixedSize`/测量方案或按行内容动态算高。此约束写进实现注释。
- `.listStyle(.plain)` 去掉 insetGrouped 的卡片描边，尽量维持原"圆角卡片包一组行"的观感；若 `.plain` 与原 `.background.secondary` 圆角容器观感差异明显，实现时保留外层圆角容器包住 `List`，并加 `.scrollContentBackground(.hidden)` 消 `List` 默认背景（视觉细节归实现，本片不做视觉重做）。

### 删除态与二次确认（照抄账单页）

- 新增 `@State private var pendingDelete: Transaction?`。
- 新增页面级 `.confirmationDialog`，文案与账单页完全一致（"删除这笔账单？" / "删除后无法恢复"），`presenting: pendingDelete`，确认调用 `delete(_:)`，取消置 nil。
- 新增私有 `delete(_ tx:)`：`EditorActions.makeDelete(store:LedgerStore(modelContext), tx:tx)()` + `pendingDelete = nil`。store 构造沿用本视图既有 `LedgerStore(modelContext)` 用法（如 `editSheet` 内 `:395`）。
- `confirmationDialog` 挂在 `NavigationStack` 层级（与既有 `.sheet`/`.alert` 并列，`:217-312` 那一串修饰符之后追加），保证任意删除态都能弹出。

## 修改点

| 文件 | 动作 |
|---|---|
| `RecordTabView.swift:56-68 附近` | 新增 `@State private var pendingDelete: Transaction?` |
| `RecordTabView.swift:343-377`（`recentSection`） | 内容区 `VStack+ForEach+Button+Divider` 改 `List + ForEach + .swipeActions`，`.scrollDisabled(true)` + 固定 `.frame(height:)`；保留点击 `editingTransaction = tx` |
| `RecordTabView.swift`（`body` 修饰符串，`:217-312` 之后） | 追加 `.confirmationDialog`（文案/结构照抄账单页 `:52-58`）+ `deleteConfirmBinding`（或直接用 `presenting:` 形态，与账单页一致） |
| `RecordTabView.swift`（新增私有方法） | `delete(_ tx: Transaction)`：复用 `EditorActions.makeDelete` + 清 `pendingDelete` |

- 不改 `RecentTransactionRow`（`:465-502`）、不改 `recentFour`/`@Query`、不改 `editSheet`。
- 不动账单页、不动 `EditorActions`。

## 验证点

对齐 PRD 验收 1、2、11：

1. **左滑删除主路径**：记账页最近记录左滑露出"删除" → 点击弹二次确认"删除这笔账单？" → 确认后该笔从最近记录消失，剩余总额与统计同步更新。
2. **取消不误删**：左滑 → 删除 → 二次确认点"取消"，该笔保留、无变化。
3. **点击进编辑仍在**：点行（非左滑）仍打开编辑 sheet，行为不变。
4. **不双滚动**：最近记录区不出现内层独立滚动；整页仍由外层 `ScrollView` 统一滚动；4 行以下时列表高度不塌陷、无多余空白。
5. **空态不回归**：`recentFour` 为空时仍显示 `emptyRecent`，不显示空 `List`。
6. **手动验证**（本片为 UI 改造，须在模拟器实机走一遍）：记 2 笔 → 记账页最近记录左滑删 1 笔 → 确认后消失、账单页对应消失、我的页剩余总额同步变化。

> UI 正确性靠模拟器手动验证（左滑手势、双滚动、高度塌陷是编译期/单测无法覆盖的）。若届时无法跑模拟器，如实说明未实机验证。

## 不做什么

- 不给最近记录编辑 sheet 加删除入口/原文（那是 `DeepLinkResultSheet` 的职责，守 N06 验收 10 不污染既有入口）。
- 不引入原型 `swipeRow` 自造手势，用原生 `.swipeActions`。
- 不改账单页删除。
- 不做视觉重做（配色/圆角风格沿用现有系统语义）。
