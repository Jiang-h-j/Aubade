# TRD 02 - 我的页预算设置 + Key 状态行 + 分类只读查看

## 给用户看的摘要

给「我的」页把三块设置补齐，全是**在既有页面加几行、调用已经写好的能力**，不碰任何底层逻辑：① **预算设置**——直接填周预算/月预算，设完统计页进度条立刻生效（以前只能靠开发者菜单硬塞）；② **DeepSeek Key 状态行**——一眼看到「已配置 ✓」还是「去填写 ›」，点进去填/改（填写界面 N03 已做好）；③ **分类一览**——看一眼系统预置的分类标签（衣食住行玩其他 / 工作 / 其他收入），只读。

## 本 TRD 负责什么

- `ProfilePlaceholderView` List 追加三个 Section：预算设置、智能识别（Key 状态行）、分类（预置）。
- 预算设置 sheet：周/月预算填写/清空，调既有 `LedgerStore.setBudget`。
- Key 状态行：读 `KeychainStore.isConfigured` 显示状态，点击开既有 `KeySetupSheet`，dismiss 后即时刷新。
- 分类只读查看：`@Query` 预置分类，按方向分组、sortOrder 排序，只读标签。
- 预算设置落库单测（唯一化 + Decimal 无误差）。

## 当前代码事实与上下游

- `ProfilePlaceholderView`（`RootTabView.swift:64-123`）：`@Query baselines/allTransactions`、`store: LedgerStore`、`List { balanceSection; #if DEBUG 调试入口 }`、`.sheet(isPresented: $showingInitSheet)`。本片在 List 追加 Section、在视图加对应 `@State`。
- `InitialBalanceSheet`（`RootTabView.swift:127-179`）：**`private struct`**，`Form + TextField(.decimalPad)` + posix `Decimal(string:)` 校验（`:136-142`）+ toolbar 取消/保存 + `.disabled(parsedAmount == nil)` + `.onAppear` 预填。**因是 private，切片外不可直接复用**（本片与它同文件，可见，但预算 sheet 语义不同——需选周/月，见"设计方案"）。
- `LedgerStore.setBudget(periodType:amount:)`（`:83`）：删同 periodType 旧记录再插一条（唯一化）；`createBudget`（`:73`）。
- `Budget`（`Models/Budget.swift`）：`id/periodType:BudgetPeriodType/amount:Decimal`。`BudgetPeriodType.weekly/.monthly`（`Enums.swift`）。
- 预算读侧范式：`AnalyticsTabView` `@Query budgets` + `budgets.first { $0.periodType == type }`（`:70-73`）——我的页照此读当前值展示。
- `KeychainStore.shared.isConfigured`（`:54`，非空即已配置）；`KeySetupSheet`（`KeySetupSheet.swift:6`）：保存调 `setDeepSeekKey`、只 `dismiss()`、**无完成回调**。
- `LedgerCategory`（`isPreset`/`sortOrder`/`direction`/`name`）；`PresetCategories.expense/income` 静态串；`LedgerStore.presetCategories()` 按 sortOrder 升序（`:38`）。
- 清空预算语义参考：`DebugMenuView.clearBudgets:166` 删所有 Budget。

## 设计方案

### 1. 预算设置 Section + sheet

我的页 List 追加"预算设置"Section，展示周/月当前值，点击开设置 sheet：

```swift
// ProfilePlaceholderView 加：
@Query private var budgets: [Budget]
@State private var editingBudgetPeriod: BudgetPeriodType?   // 非 nil → 开预算 sheet

private func currentBudget(_ type: BudgetPeriodType) -> Budget? {
    budgets.first { $0.periodType == type }   // 写侧唯一化，first 即唯一值（同 AnalyticsTabView 范式）
}

private var budgetSection: some View {
    Section("预算设置") {
        budgetRow(.weekly, "周预算")
        budgetRow(.monthly, "月预算")
    }
}

private func budgetRow(_ type: BudgetPeriodType, _ title: String) -> some View {
    Button {
        editingBudgetPeriod = type
    } label: {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            if let b = currentBudget(type) {
                Text("¥" + AmountFormat.plainString(b.amount)).foregroundStyle(.secondary).monospacedDigit()
            } else {
                Text("未设置").foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }
    .buttonStyle(.plain)
}
```

sheet 用 `.sheet(item: $editingBudgetPeriod)`（`BudgetPeriodType` 需 `Identifiable`——它是 String enum，加 `extension BudgetPeriodType: Identifiable { var id: String { rawValue } }`，仅本片 UI 需要，不改模型语义）。

**预算输入 sheet**：`InitialBalanceSheet` 是 private 且只做单值，预算 sheet 需带 periodType 语义（标题"设置周预算"/"设置月预算" + 清空按钮）。**方案：新写一个 `BudgetEditSheet`（private struct，同 `RootTabView.swift` 文件内），照抄 `InitialBalanceSheet` 的 Decimal 校验范式**（posix locale、`parsedAmount` computed、`.disabled`、`.onAppear` 预填）：

```swift
private struct BudgetEditSheet: View {
    let periodType: BudgetPeriodType
    let current: Decimal?
    let onSave: (Decimal) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""

    private var parsedAmount: Decimal? { /* 同 InitialBalanceSheet:136-142 posix 校验，> 0 */ }
    private var title: String { periodType == .weekly ? "设置周预算" : "设置月预算" }

    // Form: TextField(.decimalPad) + 保存(parsedAmount 有效)/取消 + 清空(current != nil 时显示, role .destructive)
    // 清空 → onClear() + dismiss；保存 → onSave(amount) + dismiss
}
```

> 不把 `InitialBalanceSheet` 提成 public/共享组件：两者虽校验相同，但初始总额允许 0（`value >= 0`）、预算应 > 0（0 等于没预算）；且预算多 periodType/清空语义。范式复用（照抄校验那 7 行），而非类型复用——避免为差异硬造参数化。校验逻辑是否抽公共 helper 视实现时重复度定，倾向各自内联（就 7 行）。

保存/清空回调：

```swift
.sheet(item: $editingBudgetPeriod) { period in
    BudgetEditSheet(
        periodType: period,
        current: currentBudget(period)?.amount,
        onSave: { amount in try? store.setBudget(periodType: period, amount: amount) },
        onClear: { for b in budgets where b.periodType == period { try? store.delete(b) } })
}
```

- 保存调 `setBudget`（唯一化，覆盖不新增第二条）。
- 清空 = 删该 periodType 的 Budget（`store.delete` 已有，`LedgerStore:120`）；清空后统计页该周期回到"未设预算 → 去我的设置"态（N02 已实现该分支）。

### 2. Key 状态行（智能识别 Section）

```swift
@State private var showingKeySheet = false
@State private var keyConfigured = KeychainStore.shared.isConfigured   // 本地镜像，sheet 关后刷新

private var keySection: some View {
    Section("智能识别") {
        Button {
            showingKeySheet = true
        } label: {
            HStack {
                Text("DeepSeek API Key").foregroundStyle(.primary)
                Spacer()
                if keyConfigured {
                    Label("已配置", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon)
                } else {
                    HStack(spacing: 2) { Text("去填写").foregroundStyle(.secondary); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// sheet：
.sheet(isPresented: $showingKeySheet, onDismiss: { keyConfigured = KeychainStore.shared.isConfigured }) {
    KeySetupSheet()
}
```

- **即时刷新机制**：`KeySetupSheet` 无完成回调、只 dismiss。用 `.sheet(onDismiss:)` 在关闭时重读 `KeychainStore.shared.isConfigured` 更新 `@State keyConfigured` → 行刷新。这是不改 `KeySetupSheet` 签名的最小手法（对齐 index 事实表）。
- 状态文案对齐原型 `app.js:684-687`「已配置 ✓」/「去填写 ›」。

### 3. 分类只读查看 Section

```swift
@Query(filter: #Predicate<LedgerCategory> { $0.isPreset == true },
       sort: \LedgerCategory.sortOrder) private var presetCategories: [LedgerCategory]

private var categorySection: some View {
    Section("分类（预置）") {
        categoryTags(.expense, "支出")
        categoryTags(.income, "收入")
    }
}

private func categoryTags(_ direction: TransactionDirection, _ label: String) -> some View {
    // 只读：一行标签流（FlowLayout 或简单 HStack wrap）；每个分类名一个 capsule 标签
    // 对齐原型 app.js:691-697 cat-tags 只读展示；无点击、无增删改入口
}
```

- 只读：无 `NavigationLink`、无编辑手势、无增删改按钮。
- 分组：按 `direction` 分两组（支出/收入），组内 `sortOrder`（`@Query` 已排序）。
- 标签布局：SwiftUI 无内置 flow，用简单 `WrappingHStack` 手写或 `LazyVGrid` 自适应；实现时选最简（就展示 8 个短标签）。

### 4. List 组装顺序

```
List {
    balanceSection            // 既有
    budgetSection             // 新增（本片）
    thresholdSection          // 切片 01 已加（预算提醒）
    keySection                // 新增（本片）
    categorySection           // 新增（本片）
    #if DEBUG 调试入口 #endif  // 既有
}
```

## 修改点

- **改** `Aubade/Features/AppShell/RootTabView.swift`：
  - `ProfilePlaceholderView` 加 `@Query budgets`、`@Query presetCategories`、`@State editingBudgetPeriod/showingKeySheet/keyConfigured`。
  - 加 `budgetSection`/`keySection`/`categorySection` 及 helper，插入 List。
  - 加两个 `.sheet`（预算 sheet item、Key sheet isPresented+onDismiss）。
  - 新增 `private struct BudgetEditSheet`（同文件）。
  - 加 `extension BudgetPeriodType: Identifiable`（`.sheet(item:)` 需要）。
- **无签名改动**：`setBudget`/`delete`/`KeySetupSheet`/`KeychainStore`/`LedgerCategory` 全部照现状调用。

## 验证点

- **可编译**：`ProfilePlaceholderView` + `BudgetEditSheet` 编译通过。
- **预算设置落库单测**（新增，in-memory 容器）：
  - 设周预算 800 → `fetch(Budget).filter { .weekly }` 唯一一条、amount == 800（Decimal 无误差）。
  - 同 periodType 再设 1000 → 仍唯一一条、amount == 1000（唯一化：覆盖不新增第二条）。
  - 清空周预算 → 该 periodType Budget 删除、月预算不受影响。
- **可观察**：
  - 我的页设周预算/月预算 → 统计页对应周/月档显示进度条与"已用/剩余"（验收 2）。
  - 未配 Key 时 Key 行「去填写」→ 点击开 `KeySetupSheet` 填写保存 → 回我的页行变「已配置 ✓」；清空后回「去填写」（验收 4，DEBUG 清 Key 可辅助验证）。
  - 分类 Section 展示衣食住行玩其他 + 工作/其他收入，只读无增删改入口（验收 5）。
- **回归**：`balanceSection` 剩余展示不变；DEBUG 入口保留；N02 统计页预算消费不受影响（同一 `setBudget`/`@Query budgets`）。

## 不做什么

- 不做超支阈值设置（切片 01 已做）、不做通知开关（切片 04）。
- 不改 `KeySetupSheet` 填写 UI、不加完成回调（用 `.sheet(onDismiss:)` 刷新即可）。
- 不做 Key 联网测活/格式校验（`isConfigured` 只判非空）。
- 不做分类增删改（只读，v1 后续澄清项）。
- 不重做统计页预算进度渲染（N02 已做）。
- 预算不做跨周期结转、不做"周月联动校验"（各自独立设置）。
