# TRD 01 - 4-Tab 主框架 + 分类展示映射

## 给用户看的摘要

把 App 从「数据层已就绪」的占位页换成真正的**底部四 Tab 主框架**（记账 · 账单 · 统计 · 我的，默认落「记账」）。这一片先把骨架立起来：记账、账单两 Tab 先放临时占位（下两片填真内容），统计、我的两 Tab 放正式占位页（说明"后续版本提供"）。同时做一个小而关键的东西——**分类的颜色和 emoji 映射**：N00 装好的 8 个分类（衣/食/住/行/玩/其他 + 工作/其他收入）在数据库里没存颜色和图标，这一片在端上给它们配好展示用的彩色标签和 emoji，后面表单选分类、账单列表标签、编辑页都用它。这片做完你能看到四个 Tab 能点能切、不崩，App 启动数据照常装载。

## 本 TRD 负责什么

- 用 `TabView` 主框架**替换** N00 占位根视图 `ContentView`，四 Tab：记账 / 账单 / 统计 / 我的，默认选中「记账」。
- 记账、账单 Tab 挂**临时占位**（切片 02/03 替换为真实视图）；统计、我的 Tab 挂**正式占位视图**（本节点终态，N02/N07 才填）。
- 新增**分类展示映射** `CategoryStyle`：`LedgerCategory`（name + direction）→ 展示色 + emoji，供 02/03 复用；不回写数据库。
- 保证替换 `ContentView` 后 N00 的预置分类装载（`AubadeApp.task`）与容器注入方式不受影响。

对齐 PRD 需求范围 §1、目标 §1/§7；验收标准第 8 条（4-Tab 框架）、第 2/5 条依赖的"分类彩色标签"派生来源。

## 当前代码事实与上下游

- **根视图现状**：`ContentView`（`Aubade/ContentView.swift:5`）是占位页（sunrise 图标 + "数据层已就绪"），DEBUG 下用私有 `DebugNavigationWrapper`（`:32`）包 `NavigationStack` 并挂 `DebugMenuView` 的 `NavigationLink`（`:18`）。`#Preview`（`:42`）注入 `PersistenceController.makeInMemoryContainer()`。
- **App 入口**：`AubadeApp`（`Aubade/AubadeApp.swift:4`）持有 `container = PersistenceController.makeContainer()`（`:6`），`body` 里 `ContentView().task { PresetCategories.seedIfNeeded(container.mainContext) }`（`:11`）并 `.modelContainer(container)`（`:13`）。**本片不改这些**——只把 `ContentView` 内部实现从占位换成 TabView。
- **分类数据事实**：`LedgerCategory`（`Aubade/Models/LedgerCategory.swift:8`）有 `name`、`direction`、`icon: String?`、`color: String?`、`isPreset`、`sortOrder`。预置分类由 `PresetCategories`（`Aubade/Persistence/PresetCategories.swift:7-8`）装载，**只写 name/direction/isPreset/sortOrder，icon/color 均为 nil**——这是 `CategoryStyle` 存在的理由（端上兜底展示）。预置名单：支出 `衣/食/住/行/玩/其他`、收入 `工作/其他收入`。
- **枚举**：`TransactionDirection`（`Aubade/Models/Enums.swift:4`）`.expense`/`.income`。
- **DEBUG 入口**：`DebugMenuView`（`Aubade/Debug/DebugMenuView.swift:7`，`#if DEBUG` 包裹）保留，PRD §当前理解约定"可从『我的』占位页 DEBUG 区进入"。
- **上游无冲突**：账单/记账/统计/我的界面均全新，除替换 `ContentView` 外不动任何 N00 模型/Store/持久化代码。

## 设计方案

### 1. 主框架 `RootTabView`

新增 `Aubade/Features/AppShell/RootTabView.swift`，`ContentView` 精简为对 `RootTabView` 的引用（保留 `ContentView` 名以免动 `AubadeApp` 的引用点）。

```
RootTabView
  TabView(selection: $selectedTab)   // selection 默认 .record
    RecordTabPlaceholder  tag(.record)   label 记账 (pencil)      // 02 换真实视图
    LedgerTabPlaceholder  tag(.ledger)   label 账单 (list.bullet) // 03 换真实视图
    AnalyticsPlaceholderView tag(.analytics) label 统计 (chart.bar) // 本片终态占位
    ProfilePlaceholderView   tag(.profile)   label 我的 (person)    // 本片终态占位
```

- Tab 标识用枚举 `AppTab: Hashable { case record, ledger, analytics, profile }`，`@State private var selectedTab: AppTab = .record`（满足验收 8"默认落记账"）。切片 03 需要"最近记录『全部 ›』跳账单 Tab"，故 selection 用可绑定状态而非无状态 TabView——**本片即引入 selection 绑定**，为 02/03 预留跨 Tab 跳转能力。
- 记账、账单两个占位是**临时**的（内部标注 `// TODO(N01-02/03) 替换`），只显示一行说明文字，让本片可独立编译运行。
- 统计、我的占位是**正式**的（本节点终态）：
  - `AnalyticsPlaceholderView`：居中说明"统计功能即将在后续版本提供"（对应 N02）。
  - `ProfilePlaceholderView`：说明"设置功能即将在后续版本提供"（对应 N07）；**DEBUG 下**在下方放一个 `NavigationLink → DebugMenuView`，把 N00 的调试入口迁到这里（PRD §当前理解允许），`#if DEBUG` 包裹。为此 `ProfilePlaceholderView` 内部用 `NavigationStack` 包裹（仅 DEBUG 需要，Release 可直接内容）。

### 2. 分类展示映射 `CategoryStyle`

新增 `Aubade/Features/Shared/CategoryStyle.swift`。纯函数式映射，无状态、不触库、不回写：

```
enum CategoryStyle {
    // 按预置分类名给定色与 emoji；未知名（N07 用户自建）按 direction 兜底。
    static func emoji(for category: LedgerCategory?) -> String
    static func color(for category: LedgerCategory?) -> Color
    // 便于列表标签统一取用
    static func emoji(name: String?, direction: TransactionDirection) -> String
    static func color(name: String?, direction: TransactionDirection) -> Color
}
```

映射规则（预置 8 类固定配色 + emoji；名称命中优先，未命中按 direction 兜底）：

| 分类名 | emoji | 色 | 分类名 | emoji | 色 |
|---|---|---|---|---|---|
| 衣 | 👕 | 紫 | 玩 | 🎮 | 粉 |
| 食 | 🍜 | 橙 | 其他(支出) | 📦 | 灰 |
| 住 | 🏠 | 蓝 | 工作 | 💼 | 绿 |
| 行 | 🚗 | 青 | 其他收入 | 💰 | 绿 |

- `category == nil`（账单未选分类 / 分类被删 nullify）：emoji 统一用 `🏷️`（未分类无需按方向区分图标），文案侧显示"未分类"，色按 direction 兜底（支出灰、收入绿）。
- 未知名（N07 用户自建分类）：按 direction 兜底色 + 通用 emoji（支出 `📦`、收入 `💰`）。**前向兼容 N07**，不硬编码只认 8 类而崩。
- 色用 SwiftUI `Color`（asset-free，直接用系统色或 `Color(red:green:blue:)` 常量），不依赖 Asset Catalog，避免动 pbxproj 资源。
- **收入方向颜色**：PRD 已确认约定 4「收入绿色 + 正号，支出默认深色 + 减号」——注意区分两个概念：分类**标签**的配色（本映射，工作/其他收入给绿系）与**金额文本**的方向色（切片 03 的金额渲染，收入绿/支出 `.primary`）。本片只提供分类标签配色；金额方向色是 03 的渲染规则，不在本映射内。

### 3. 目录组织

引入 `Aubade/Features/` 作为 N01+ 界面代码根（N00 只有 Models/Persistence/Store/Debug）：

```
Aubade/Features/
  AppShell/RootTabView.swift          + Analytics/Profile 占位（本片）
  Shared/CategoryStyle.swift          （本片，02/03 复用）
```

工程用 file-system-synchronized groups（N00 slice-progress 记载 objectVersion 77），新增 `.swift` 文件自动纳入编译，**无需手改 pbxproj**。

## 修改点

**改**
- `Aubade/ContentView.swift`：`body` 从占位 VStack 改为 `RootTabView()`；移除占位专用的 `DebugNavigationWrapper`（其 DEBUG 导航职责迁入 `ProfilePlaceholderView`）；`#Preview` 保留注入 in-memory 容器。

**新增**
- `Aubade/Features/AppShell/RootTabView.swift`：`AppTab` 枚举、`RootTabView`、`AnalyticsPlaceholderView`、`ProfilePlaceholderView`、记账/账单临时占位（`RecordTabPlaceholder`/`LedgerTabPlaceholder`）。
- `Aubade/Features/Shared/CategoryStyle.swift`：`CategoryStyle` 映射。
- `AubadeTests/CategoryStyleTests.swift`：验证 8 类预置命中固定 emoji/色、nil 兜底、未知名按 direction 兜底。

**不改**
- `AubadeApp.swift`（容器注入、`.task` 装载不动）、`PersistenceController`、`PresetCategories`、所有 `Models/*`、`LedgerStore`、`DebugMenuView`。

## 验证点

1. **编译**：`xcodebuild -scheme Aubade -destination 'generic/platform=iOS Simulator' build` → BUILD SUCCEEDED。
2. **启动落地 + 四 Tab（验收 8）**：模拟器启动默认在「记账」Tab；点四个 Tab 均可切换、无崩溃；统计/我的显示正式占位文案；记账/账单显示临时占位。
3. **N00 装载不回归（验收 8 后半）**：启动后经「我的」→ DEBUG 菜单（DEBUG 构建）确认预置分类仍为 8 条（`AubadeApp.task` 的 seed 正常执行）。
4. **CategoryStyle 单测**：`xcodebuild test` → `CategoryStyleTests` 全绿：8 类预置各自命中预期 emoji 且色非兜底色；`nil` 与未知名走 direction 兜底。
5. **审阅**：`CategoryStyle` 不含任何 `context.save` / 写库调用（纯展示映射，PRD §7"不回写数据库"）。

## 不做什么

- 不做记账/账单 Tab 的真实功能（→ 切片 02/03，本片是临时占位）。
- 不做统计/我的 Tab 的任何实际功能（→ N02/N07，本片是正式占位）。
- 不把派生色/emoji 写回 `LedgerCategory.color/icon`（PRD §7 明确不回写）。
- 不改 `AubadeApp` 的容器注入与 `.task` 装载、不改任何 N00 模型/Store/持久化。
- 不引入 Asset Catalog 颜色资源（避免手改 pbxproj，用代码常量色）。
- 不做分类的用户增删改（→ N07）；`CategoryStyle` 仅对未知名前向兜底，不提供管理界面。
