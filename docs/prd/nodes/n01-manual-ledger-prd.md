# N01 手动记账 + 账单列表/编辑

> 本节点是 Aubade v1 开发 DAG 的第二个节点，依赖 **N00 工程地基 + 数据层**（已完成，提交 a810579）。对应技术基线模块 **M2.1 手动记账** + **M3 账单列表/编辑**。
>
> 里程碑意义：**第一个可自用版本**——完全不依赖 AI、不依赖真机，装到 iPhone 上即可日常手动记账、查流水、改删。
>
> 上游事实来源：全局 PRD `docs/prd/aubade-v1-prd.md`（主流程 D 手动记账 / 辅助流程 G 账单管理 / 验收点 5、10、12）、原型 `docs/design/aubade-v1-prototype.md`（§3 页面地图 / §4.1 账单页 / §4.2 记账 Tab / §4.3 结果卡片 / §4.4 手动表单 / §5 状态与异常）、技术基线 `docs/design/aubade-v1-technical-baseline.md`（M2.1、M3）、开发 DAG `docs/design/aubade-v1-dev-dag.md`（N01 小节）。
> 代码事实来源：直接阅读 N00 已落地源码（本仓库无 `.codegraph/` 索引，代码量小，逐文件阅读，行号为本 PRD 写作时快照）。

## 给用户看的摘要

做完这个节点，你的 iPhone 上就有**第一个能天天用的记账 App**了——虽然还不能截图/语音/短信自动识别（那是后面几个节点），但"自己动手记一笔、翻账单、改错、删掉"这套最基本的闭环全通：

1. **底部四个 Tab 立起来**：打开 App 默认在「记账」页，底部是「记账 · 账单 · 统计 · 我的」。这一节点把这个主框架一次搭好；其中**记账、账单两个 Tab 能真正用**，统计和我的两个 Tab 先放占位页（下一批节点 N02/N07 再填内容）。
2. **手动记一笔**：记账页点「手动输入」，填金额、选支出还是收入、选分类（用 N00 已经装好的 衣/食/住/行/玩/其他 + 工作/其他收入）、挑日期、写备注 → 保存，立刻入账。
3. **账单页看流水**：所有账单按日期分组倒序排列，分类带彩色标签，金额醒目（支出减号、收入加号）；可以按分类筛、按时间筛（全部/本周/本月/自定义起止）；点任意一笔进去改，或删除（删除要二次确认，防误删）。
4. **记账页的两个即时反馈**：顶部「今日已记 N 笔」小卡片，下方「最近记录」最近 4 笔。

**这一节点不做什么**（都在后面节点）：账单页顶部那张「剩余总额 · 本月支出 · 本月收入」汇总卡属于 N02（要先有初始总额基线和统计聚合才能算）；截图/语音/文本三种识别记账属于 N03~N06；预算、Key、初始总额录入、首次引导属于 N07。**但我会把"改一笔账"的编辑卡片做成一个可复用组件**，后面 AI 识别出结果后弹的"结果卡片"就直接复用它，避免重复造。

## 目标

1. 用**底部 4-Tab 主框架**（记账 · 账单 · 统计 · 我的，默认落「记账」）替换 N00 的占位根视图 `ContentView`（`Aubade/ContentView.swift:5`）；统计、我的两 Tab 落占位视图，记账、账单两 Tab 落本节点实现。
2. **手动记账**：实现「金额 / 方向 / 分类 / 日期 / 备注」表单，保存时经 `LedgerStore.createTransaction`（`Aubade/Store/LedgerStore.swift:48`）以 `source: .manual` 入账；金额输入解析为 `Decimal` 正值，方向单独选。
3. **账单列表**：按 `occurredAt` 日期分组、组内倒序展示全部账单；每项显示分类彩色标签、商户/备注摘要、带方向符号的金额。
4. **筛选**：支持按分类（全部 + 各分类）与时间范围（全部 / 本周 / 本月 / 自定义起止）过滤，结果与条件一致。
5. **编辑 / 删除**：点账单进详情/编辑页改「金额/方向/分类/时间/商户/备注」，经 `LedgerStore.updateTransaction(_:apply:)`（`Aubade/Store/LedgerStore.swift:64`）保存；删除经 `LedgerStore.delete`（`:92`）并有二次确认。
6. **可复用编辑组件**：把编辑表单抽成一个独立组件（结果卡片的基础形态），供 N03~N06 的识别结果卡片复用；本节点它以"手动新增"和"编辑已有账单"两种入口出现。
7. **记账页即时反馈**：顶部「今日已记 N 笔」、下方「最近记录」最近 4 笔（点进可编辑，「全部 ›」跳账单页）。
8. 所有读写经注入的 `ModelContext` / `LedgerStore`，**不自建 `ModelContainer`**（延续 N00 §11 迁移对冲硬约束，见 `Aubade/Persistence/PersistenceController.swift:6`）。

## 当前理解

### 数据底座已就绪（N00 交付，本节点直接消费）

- **`Transaction`**（`Aubade/Models/Transaction.swift:5`）：`amount: Decimal`（正值，方向由 `direction` 表达）、`direction: TransactionDirection`、`occurredAt: Date`、`category: LedgerCategory?`（可空，删分类后 nullify）、`merchant?`、`note?`、`cardTail?`、`source: TransactionSource`、`rawText?`、`imageRef?`、`createdAt`/`updatedAt`。手动记账用到 amount/direction/occurredAt/category/merchant/note/source；cardTail/rawText/imageRef 手动入口留空。
- **`TransactionDirection`**（`Aubade/Models/Enums.swift:4`）：`.expense` / `.income`，`CaseIterable`，可直接驱动方向选择器。
- **`TransactionSource`**（`Aubade/Models/Enums.swift:12`）：手动记账固定用 `.manual`。
- **`LedgerCategory`**（`Aubade/Models/LedgerCategory.swift:8`）：`name`、`direction`、`icon?`、`color?`、`isPreset`、`sortOrder`。分类选择器需**按 `direction` 过滤**（支出账单只选支出类，收入账单只选收入类）并按 `sortOrder` 排序。**注意：预置分类当前 `color`/`icon` 均为 nil**（N00 `PresetCategories` 只写了 name/direction/isPreset/sortOrder，见 `Aubade/Persistence/PresetCategories.swift:23`）——"分类彩色标签"需在 N01 端提供**从分类名/direction 派生的展示色与 emoji 映射**，不改数据层。
- **`LedgerStore`**（`Aubade/Store/LedgerStore.swift:8`）：已提供 `fetch`、`createTransaction`、`updateTransaction(_:apply:)`、`presetCategories`、`delete`。本节点主要复用这些；列表读取分类可用 `presetCategories()`（当前分类仅预置 8 条，N07 才有用户增删改，故 N01 读预置即可覆盖，但**分类选择器应查全部分类而非硬编码**以对 N07 前向兼容）。
- **`createTransaction` 语义**（`:53`）：内部填 `createdAt = updatedAt = Date()`（当前时刻，`Date()` 只在写入方内部调用，符合 N00 的 SwiftData 时机约定），`occurredAt` 由调用方传入——手动表单的"日期"即 `occurredAt`。

### 界面骨架现状

- 根视图 `ContentView`（`Aubade/ContentView.swift:5`）目前是占位页（图标 + "数据层已就绪"），DEBUG 下经 `DebugNavigationWrapper` 挂 `DebugMenuView`。本节点**替换**为 `TabView` 主框架。
- `DebugMenuView`（`Aubade/Debug/DebugMenuView.swift`）是 N00 的临时验证入口（仅 DEBUG），插样例账单/列分类/清库。本节点搭出真实界面后，DebugMenuView **保留**（仍是有用的 DEBUG 工具），可从「我的」占位页的 DEBUG 区进入，或维持现有挂载方式；不作为退出标准。
- SwiftData 查询在视图层用 `@Query`（`DebugMenuView.swift:10` 已有先例：`@Query(sort:) private var ...`），列表页据此实时刷新。

### 视图层数据获取方式（需 TRD 定，PRD 层面约定原则）

- 账单列表天然适合 `@Query` 驱动（增删改后自动刷新）；但**带动态筛选条件的 `@Query`**（分类/时间范围可变）在 iOS 17 需要用可变 `FetchDescriptor` 或在内存中过滤——具体策略留 TRD。PRD 只约束：筛选结果必须与条件一致、增删改后列表与"今日已记/最近记录"实时同步。
- 写操作（新增/编辑/删除）经 `LedgerStore`（注入 `ModelContext`）；读展示用 `@Query` 或 `LedgerStore.fetch`，二者共享同一注入 context。

## 涉及的现有链路

- **被替换**：`ContentView`（`Aubade/ContentView.swift:5`）占位内容 → 4-Tab 主框架。`AubadeApp`（`Aubade/AubadeApp.swift:10`）已注入 `container` 并 `.task` 装载预置分类，**本节点不改** App 入口的容器注入方式。
- **被复用（只读消费，不改）**：
  - `LedgerStore` 的 createTransaction / updateTransaction / delete / fetch / presetCategories。
  - `Transaction` / `LedgerCategory` / `TransactionDirection` / `TransactionSource` 模型与枚举。
  - `PersistenceController.makeInMemoryContainer()`（`:24`）供 SwiftUI 预览与本节点单测使用。
- **本节点新增（下游 N02~N07 将依赖）**：
  - 4-Tab 主框架容器视图（N02 填统计 Tab、N07 填我的 Tab 时挂到这里）。
  - **可复用的账单编辑组件**（N03~N06 的识别结果卡片直接复用其字段编辑与保存逻辑）——这是本节点对下游最重要的接口承诺，需保证其能以"新建草稿"和"编辑已有 Transaction"两种模式工作。
  - 分类展示映射（名称/direction → 颜色 + emoji），N02 统计的分类占比配色应与之一致（PRD 层记录该一致性期望，落地在 N02）。
- **无既有调用方冲突**：账单/记账界面是全新界面，除替换 ContentView 外不改动 N00 任何模型/Store/持久化代码；`LedgerStore` 现有方法签名不变。

## 需求范围

### 1. 底部 4-Tab 主框架
- `TabView` 四个 Tab：记账 / 账单 / 统计 / 我的，默认选中「记账」。
- 记账、账单 Tab → 本节点实现的真实视图；统计、我的 Tab → **占位视图**（简单说明"即将在后续节点提供"，不做功能）。
- Tab 图标与文案清晰区分（原型 §3）。

### 2. 记账 Tab
- 标题「记一笔」+ 右上「今日已记 N 笔」小卡片（N = **`createdAt`** 落在今天的账单数，即"今天这个记账动作发生了几笔"）。
- 四入口网格：📷截图识别 / 🎤语音记账 / 📋文本识别 / ✏️手动输入。**仅「手动输入」可用**；其余三个为占位按钮，点击提示"该入口将在后续版本提供"（对应 N03~N06），不做假流程。
- 「最近记录」：最近 4 笔（按 **`occurredAt` 倒序**，符合流水直觉），点某笔进编辑页，「全部 ›」切到账单 Tab。空账本显示占位提示。

### 3. 手动记账表单（复用编辑组件的"新建"模式）
- 字段：金额（数字键盘输入 → `Decimal` 正值，非法/空/零校验）、方向（支出/收入单选，`TransactionDirection`）、分类（下拉/选择器，**按当前方向过滤**分类并按 sortOrder 排序，可不选=category 置 nil）、日期（`occurredAt`，默认今天，**只允许当天及过去、禁未来**，与统计页禁未来口径一致）、备注（`note`，可空）。**手动新建表单不含商户输入**（原型 §4.4，保持 3 步内最短路径）；商户 `merchant` 字段在编辑页/结果卡片出现，可复用编辑组件内部仍支持该字段供 N03+ 识别填充。
- 保存 → `LedgerStore.createTransaction(amount:direction:occurredAt:category:note:source:.manual)`；成功后回到记账页，最近记录与今日计数刷新。

### 4. 账单 Tab（流水列表）
- **不含**顶部汇总卡（剩余总额/本月支出/本月收入 → N02）。
- 筛选栏：分类筛选（全部 + 各分类）、时间范围筛选（**全部 / 本周 / 本月 / 自定义起止**）。自定义提供起止日期选择器。
- 流水列表：按 `occurredAt` 所在**日期分组**（组头显示日期），组内倒序；每项 = 分类彩色标签（派生色+emoji）+ 商户或备注摘要 + 金额（**支出前缀 `-`、默认深色；收入前缀 `+`、绿色**）。
- 空状态：无账单时"还没有账单，去『记账』记第一笔吧"；筛选后无结果显示对应空态。

### 5. 账单详情 / 编辑页（复用编辑组件的"编辑"模式）
- 从列表或最近记录点入，展示并可改：金额 / 方向 / 分类 / 时间（`occurredAt`）/ 商户 / 备注。
- 保存 → `LedgerStore.updateTransaction(tx){ ... }`（apply 内改字段，Store 自动刷新 `updatedAt`）。
- 删除 → 二次确认弹窗（原型 §5「删除账单」）；确认后 `LedgerStore.delete(tx)`，返回列表。

### 6. 可复用账单编辑组件
- 抽象出一个编辑视图/表单组件，支持两种模式：**新建草稿**（无 Transaction，保存时 create）与**编辑已有**（绑定 Transaction，保存时 update）。
- 字段集与原型 §4.3 结果卡片一致（金额/方向/分类/时间/商户/备注），使 N03~N06 的识别结果卡片可直接复用；本节点先不实现"折叠原文/删除这笔=撤销入账"等 AI 专属交互（那些字段 rawText/imageRef 手动入口为空），但组件结构需为其预留（如可选的原文展示区）。

### 7. 分类展示映射
- 提供从 `LedgerCategory`（name + direction）到展示色与 emoji 图标的映射，用于列表标签、分类筛选、编辑页分类选择。数据层分类 color/icon 为空时用此映射兜底；不回写数据库。

## 不做什么

以下均属后续节点，本节点**不实现**：
- **账单页顶部汇总卡**（剩余总额 · 本月支出 · 本月收入）与任何统计聚合、剩余金额派生计算（→ N02）。本节点账单页无汇总区。
- **截图 / 语音 / 文本 三种识别记账**的真实流程、DeepSeek/OCR/Speech 调用、"识别中"态、结果卡片的识别数据填充（→ N03~N06）。本节点仅产出可复用编辑组件的**静态基础形态**，记账页三入口按钮为占位提示。
- **统计 Tab、我的 Tab 的实际功能**：统计聚合/趋势/占比/预算进度（→ N02）；剩余总额展示与调初始总额、预算设置、DeepSeek Key、分类管理界面、首次引导、权限申请（→ N07）。本节点这两 Tab 为占位视图。
- **分类的用户增删改界面**（→ N07）；本节点分类选择只读取已有（预置 8 条），选择器查全部分类以对 N07 前向兼容。
- **预算 / 初始总额 / Key / 通知**相关一切（→ N02 消费预算 / N07 设置）。
- 不改动 N00 的模型字段、`LedgerStore` 方法签名、`PersistenceController` 容器配置与 App Group 决策。

## 验收标准

（对齐 DAG 中 N01 的"退出标准（可观察）"与全局 PRD 验收点 5 / 10 / 12。可用模拟器或真机肉眼观察，或以单元测试/预览佐证组件逻辑。）

1. **手动新增入账（PRD 验收点 5）**：在记账页「手动输入」填一笔支出（如金额 35.55、分类「食」、今天、备注"午餐"）保存后，该笔立即出现在账单列表对应日期分组下，金额显示为 `-35.55`；再记一笔收入（如工资 8000、分类「工作」）显示为 `+8,000.00`（金额统一千分位展示，与原型 §4.1 一致）。金额以 `Decimal` 写入、读回无浮点误差。
2. **列表分组与展示**：账单列表按 `occurredAt` 日期倒序分组，每项含分类彩色标签、金额与方向符号；空账本显示"去记第一笔"引导。
3. **编辑（PRD 验收点 10 编辑部分）**：点一笔进编辑页，改金额或分类或时间并保存后，列表对应项同步更新；`updatedAt` 被刷新（可经 DEBUG/单测佐证）。
4. **删除 + 二次确认（PRD 验收点 10 删除部分）**：对一笔账单执行删除，弹出二次确认；确认后该笔从列表消失，取消则保留。
5. **分类筛选（PRD 验收点 12 分类部分）**：选某一分类（如「食」）后，列表仅显示该分类账单；切回"全部"恢复。
6. **时间范围筛选（PRD 验收点 12 时间部分）**：分别选「本周」「本月」「自定义起止区间」，列表仅显示 `occurredAt` 落在该区间的账单，边界正确（区间内/外各验一笔）；「全部」显示所有。分类 + 时间两个条件可叠加且结果一致。
7. **记账页即时反馈**：「今日已记 N 笔」随当天新增/删除实时变化；「最近记录」显示最近 4 笔、点入可编辑、「全部 ›」跳账单 Tab。
8. **4-Tab 框架**：App 启动默认落「记账」Tab；四 Tab 可切换；统计、我的为占位视图不崩溃；替换 ContentView 后 N00 的预置分类装载（`AubadeApp.task`）与数据读写仍正常。
9. **编辑组件可复用性**：同一编辑组件在**「新建草稿」**（手动记账，无绑定 Transaction，保存时 create）与**「绑定已有 Transaction」**（编辑，保存时 update）两种模式下均能正确保存；字段集与原型 §4.3 结果卡片一致，为 N03~N06 结果卡片预留复用点（以两模式各保存成功 + 代码结构审阅为证）。
10. **不越界**：账单页无汇总卡；统计/我的 Tab 无实际功能；记账页截图/语音/文本按钮为占位提示，不触发任何识别或假入账。

## 已确认约定

（以下 4 项在 PRD 评审前已由用户拍板，作为既定实现约束，非待确认项。）

1. **手动新建表单不含"商户"输入**：手动表单字段 = 金额/方向/分类/日期/备注（原型 §4.4），保持记账 3 步内最短路径；商户 `merchant` 字段仅在编辑页与结果卡片出现。可复用编辑组件内部仍支持商户字段，供 N03~N06 识别结果填充。
2. **日期只允许当天及过去、禁未来**：手动记账 `occurredAt` 默认今天，可选到过去，不允许选未来，与统计页"不能翻到未来"口径一致。
3. **时间口径**："今日已记 N 笔"按 **`createdAt`**（今天发生的记账动作数）；"最近记录"与账单列表按 **`occurredAt` 倒序**（流水发生时间直觉）。
4. **金额方向颜色**：收入用**绿色 + 正号**（如 `+8,000.00`），支出用**默认深色 + 减号**（如 `-35.55`）。纯展示，不影响数据。
