# TRD 03 - R4 分类管理 UI

## 给用户看的摘要

这一片把"我的"页里那块只能看的分类，变成能管理的列表：预置分类（衣/食/住/行等）标上"预置·锁定"、点了只提示不给改；自定义分类可以新增（选方向/名称/图标/颜色）、能编辑、能删除。删一个被账单用过的分类时，先告诉你"有 N 笔会转到『其他』"，确认后账单转走、分类才删。界面样子仿照现在已有的"设置初始总额""设置预算"那两个弹窗，风格一致。

## 本 TRD 负责什么

- 我的页分类区 `@Query` 从"仅预置"放开到**全部分类**（含自定义），按 direction 分组 + sortOrder 排序。
- 只读标签流 → **可管理列表**：预置行标"预置·锁定"、点击 toast 不进编辑；自定义行标"编辑 ›"、点击进编辑器；底部"＋ 新增自定义分类"。
- 分类编辑器 sheet（仿 `InitialBalanceSheet`/`BudgetEditSheet`）：新增可选方向（编辑锁方向）、名称限 6 字、图标 16 选一、颜色 8 选一；保存走切片 02 的 Store 方法；重名/预置拒绝给 toast。
- 删除入口在编辑器内：被引用时二次确认带引用数与"转到『其他』"说明，确认走 02 的 `deleteCategory`。

依赖：切片 02 的 `updateCategory` / `deleteCategory` / `CategoryError` 已定稿。

## 当前代码事实与上下游

- 我的页整体是一个 `List`（`Aubade/Features/AppShell/RootTabView.swift:108`），各区块是 `Section`。分类区 `categorySection`（`:270-277`）是其中一个 Section——**分类管理列表要作为 Section 内容嵌进这个既有 List，不新建独立 List（无双滚动问题，与切片 01 不同）。**
- 现状 `@Query`：`presetCategories`（`:71-72`）`filter: isPreset==true, sort: sortOrder`——**只取预置**。
- 现状渲染：`categoryTags(_:_:)`（`:280-296`）把某方向预置分类名铺成只读 capsule 标签流，注释明说"无点击、无增删改入口"。自定义分类不展示。
- `ProfilePlaceholderView` 已持有：`store`（`:90` `LedgerStore(modelContext)`）、`modelContext`（`:66`）。
- 成熟 sheet 编辑范式（仿写对象）：
  - `InitialBalanceSheet`（`:301-353`）：`NavigationStack + Form`，`@Environment(\.dismiss)`，`@State input`，toolbar 取消/保存，`.disabled` 校验。
  - `BudgetEditSheet`（`:362-424`）：多一个"清空/删除"按钮（`role:.destructive`）区块——**分类编辑器的"删除"按钮仿此**。
  - `.sheet(item:)` + `Identifiable` 扩展范式（`:356-358` `BudgetPeriodType: Identifiable`）——分类编辑器用 `.sheet(item:)` 驱动同理。
- 图标/颜色候选（对齐原型 `prototype/app/data.js:21-22`）：
  - 图标 16 个：`🐾 🎓 💊 🎁 ✈️ 📚 🏋️ 🎵 🍼 🐶 💄 🔧 🌱 ☕️ 🎨 🏦`
  - 颜色 8 个：`#e8785c #f0a868 #e8a0bf #b39ddb #8fb8de #7fc8a9 #6bbf8a #c0a080`
  - 这两组常量在本片内定义（如 `CategoryEditorChoices`），是 UI 选择项，非模型数据。
- 原型交互规格（行为事实来源）`prototype/app/app.js:826-945`：
  - 列表：支出组 + 收入组，预置行"预置·锁定"、自定义行"编辑 ›"，底部"＋新增"（`:837-842`）。
  - 点预置 → `toast('预置分类不可修改')` 不进编辑器（`:847`）。
  - 编辑器：新增可选方向、编辑锁方向（`:901-904`）；名称 maxlength=6（`:905`）；图标/颜色网格（`:906-911`）。
  - 保存：新增走 `addCategory`（重名 → null → toast"该方向已有同名分类"，`:927-928`）；编辑走 `updateCategory`（`:924`）。
  - 删除（`:933-943`）：`categoryUsageCount` 引用数；有引用文案"有 N 笔账单用了这个分类，删除后这些账单会转到『其他』"（`:937`），确认后先转再删。
  - **原型 bug 纠偏**：`:940` 无论方向统一 `b.cat='其他'`。真实端走切片 02 的 `deleteCategory` 按方向兜底（收入转"其他收入"），本片删除入口直接调 Store，不复刻原型这行逻辑。

## 设计方案

### 数据放开

- `presetCategories` `@Query` 改为取全部分类：`@Query(sort:\LedgerCategory.sortOrder) private var categories: [LedgerCategory]`（去掉 `isPreset==true` filter）。
- 分组：`categories.filter{ $0.direction == .expense }` / `.income`，各自已按 sortOrder 有序（自定义 `sortOrder` 默认 0，排在预置前或后由 sortOrder 决定；本片不重排预置——新增自定义分类的 sortOrder 取值策略见下）。
- 新增自定义分类的 `sortOrder`：切片 02 `createCategory` 默认 `sortOrder=0`。为避免与预置（0..7）混序导致自定义插到中间，UI 新增时传一个大于现有最大值的 sortOrder（如 `(categories.map(\.sortOrder).max() ?? 0) + 1`），让自定义分类排在同方向末尾。**此取值在 UI 层算好传给 `createCategory`**（02 的 createCategory 已支持 sortOrder 参数，无需改 02）。

### 分类区改造（categorySection）

替换 `categoryTags` 只读标签流为可管理行列表，仍在 `Section` 内：

```
Section {
    categoryRows(.expense)   // 支出组：组内小标题 + 各行
    categoryRows(.income)    // 收入组
    Button("＋ 新增自定义分类") { editorItem = .create }   // 底部新增入口
} header: { Text("分类") }
```

- 每行 `categoryRow(_ c:)`：图标 badge（emoji + color.opacity 底色，复用 `CategoryStyle` 或本片直接用 c.icon/c.color）+ 名称 + 右侧标记。
  - 预置行：右侧 `Text("预置 · 锁定").foregroundStyle(.secondary)`，点击 → toast/轻提示"预置分类不可修改"，不进编辑器。
  - 自定义行：右侧 `"编辑 ›"`，点击 → `editorItem = .edit(c)`。
- header 文案从"分类（预置）"改为"分类"（不再只有预置）。
- 预置行图标兜底：预置分类 `icon`/`color` 为 nil（seed 未传，PresetCategories 事实），渲染走现有 `CategoryStyle.emoji(for:)` / `CategoryStyle.color(...)` 兜底口径（与最近记录行 `:482-487` 同源），不硬编码。

### 分类编辑器 sheet（新增 CategoryEditorSheet）

驱动：`@State private var editorItem: CategoryEditorRoute?` + `.sheet(item:$editorItem)`。`CategoryEditorRoute: Identifiable`：`.create` / `.edit(LedgerCategory)`。

结构仿 `BudgetEditSheet`（`NavigationStack + Form`）：

- 方向：仅 `.create` 显示 `Picker`/分段（支出/收入）；`.edit` 隐藏（方向锁定）。
- 名称：`TextField`，限 6 字（`onChange` 截断或 `maxLength` 等价处理），去空白。
- 图标：16 选一网格（`LazyVGrid`，选中高亮）。
- 颜色：8 选一网格（色块，选中描边）。
- 保存按钮：
  - `.create` → UI 层算 sortOrder → `store.createCategory(name:direction:icon:color:isPreset:false, sortOrder:)`；捕获同方向重名（02 的 createCategory 目前**不判重**——见下"依赖澄清"）。
  - `.edit` → `store.updateCategory(c, name:icon:color:)`；捕获 `CategoryError.duplicateName` → toast"该方向已有同名分类"、`presetImmutable` 理论不达（预置不进编辑器，防御性 toast）。
- 删除按钮（仅 `.edit`，仿 `BudgetEditSheet` 清空按钮，`role:.destructive`）：
  - 读引用数 `c.transactions.count`。
  - 兜底名按方向取：`fallbackName = (c.direction == .expense) ? "其他" : "其他收入"`（与切片 02 同口径）。
  - `confirmationDialog`：有引用 → "有 N 笔账单用了这个分类，删除后这些账单会转到『\(fallbackName)』"（**收入分类显示"其他收入"，纠原型 :940 统一"其他"的措辞 bug**）；无引用 → "确定删除这个自定义分类？"。
  - **删除时序（硬约束，防 SwiftData 悬垂 SIGTRAP）：确认后先 `dismiss()`，再 `store.deleteCategory(c)`——顺序不可颠倒。** 若先删后 dismiss，sheet 仍在场会以已删分类 `c` 重建 editor 导致悬垂读取崩溃（对齐 `DeepLinkResultSheet:431-441` 的"先 dismiss 再 delete"范式与 memory 悬垂陷阱）。实现形态：`let perform = { try? store.deleteCategory(c) }; dismiss(); perform()`，或把 delete 放 dismiss 后的下一 runloop。

### 依赖澄清（切片 02 边界确认）

- 02 的 `updateCategory` 已含同方向重名拒绝。**但 `createCategory`（现存，02 不改）不判重**——原型 `addCategory` 是判重的。为满足 PRD 验收 4"新增同方向重名拒绝"，有两个落点：
  - **选定**：新增判重放 UI 层（保存前 `categories.contains{ $0.direction==dir && $0.name==name }` → 拒绝 toast），不改 02 的 `createCategory` 签名/行为，保持 02 已定稿。
  - 弃用：改 02 让 `createCategory` 判重——会动已定稿的既有方法，风险大。
- **已核实**：`createCategory` 在生产源码零调用（仅测试调用），本节点 UI 是首个也是唯一生产调用方；识别落库路径 `RecognitionNormalizer.category` 只匹配已有分类、从不 insert，不会绕过 UI 判重造成同方向重名。故 UI 层用 `@Query categories` 内存快照判重充分（单用户 App 无并发写）。
- **结论**：新增重名判定在 03 UI 层做；编辑重名判定用 02 的 `updateCategory`（已内建）。两处文案统一"该方向已有同名分类"。

## 修改点

| 文件 | 动作 |
|---|---|
| `RootTabView.swift:71-72` | `@Query` 去掉 `isPreset==true` filter，取全部分类，改名 `categories` |
| `RootTabView.swift:270-296`（`categorySection` + `categoryTags`） | 只读标签流改可管理行列表：预置行"预置·锁定"、自定义行"编辑 ›"、底部"＋新增"；header 改"分类" |
| `RootTabView.swift`（新增 `@State editorItem` + `.sheet(item:)`） | 驱动分类编辑器 |
| `RootTabView.swift`（新增 `CategoryEditorSheet` + `CategoryEditorRoute` + 图标/颜色常量） | 仿 `BudgetEditSheet`；保存走 02 Store 方法；删除二次确认（先 dismiss 再 delete） |
| （引用方核对） | `presetCategories` @Query 改名后，同文件引用处（若有）同步 |

- 不改切片 02 已定稿的 Store 方法。
- 不改最近记录/账单页/识别链路。

## 验证点

对齐 PRD 验收 3、4、5、6、8、9，须模拟器手动走：

1. **新增自定义分类**：分类区"＋新增" → 选"支出"、名"宠物"、选图标色 → 保存 → 出现在支出组；回记账页手动记账，分类选择器可见"宠物"。
2. **同方向重名拒绝**：新增填该方向已存在名称 → toast"该方向已有同名分类"，不创建。
3. **跨方向同名允许**：支出已有"其他"，新增收入"其他"（若不与预置"其他收入"冲突）不被误拦（判重限定同方向）。
4. **编辑自定义**：点自定义"编辑 ›" → 改名/换图标/换色 → 保存 → 列表与记账选择器同步更新；方向栏不出现（锁定）。
5. **预置锁定**：点预置（如"食"）→ toast"预置分类不可修改"，不进编辑器；无删除入口。
6. **删除未引用**：删无引用自定义分类 → "确定删除这个自定义分类？" → 确认后消失。
7. **删除已引用转"其他"（支出）**：给"宠物"记 2 笔支出 → 删 → "有 2 笔账单用了这个分类，删除后这些账单会转到『其他』" → 确认后分类删除、那 2 笔分类变"其他"（非 nil）。
8. **删除已引用转"其他收入"（收入）**：自定义收入分类记 1 笔 → 删 → 账单转"其他收入"（走 02 的 deleteCategory 方向兜底，非"其他"）。
9. **删除不崩**：sheet 内删除先 dismiss 再 delete，无 SwiftData 悬垂崩溃。

> 本片是 UI，正确性靠模拟器手动验证；后台转移/预置保护的逻辑正确性已由切片 02 单测焊死，本片只验 UI 接线正确。无法跑模拟器时如实说明。

## 不做什么

- 不改切片 02 的 Store 方法（新增重名判定放 UI 层，不动 `createCategory`）。
- 不重排预置分类 sortOrder（自定义排同方向末尾）。
- 不做视觉重做（图标/色块用原型候选值，但整体配色/圆角沿用现有系统语义，暖白/珊瑚青绿是 B04）。
- 不改识别链路（自动分类命中自定义已由 02 验证）。
- 不给预置分类任何编辑/删除入口（开放项：预置锁全部字段）。
