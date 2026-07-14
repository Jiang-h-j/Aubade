# N02 剩余金额 + 统计

> 本节点是 Aubade v1 开发 DAG 的第三个节点，依赖 **N01 手动记账 + 账单列表/编辑**（已完成，提交 38d98ee）与其底座 **N00 工程地基 + 数据层**。对应技术基线模块 **M6 剩余金额** + **M5 统计与聚合层**。
>
> 里程碑意义：**「能看花销与结余」的可自用版本**——在 N01 已跑通的账单数据上，算出"还剩多少钱"和"这周/这月花了多少、花在哪、有没有超预算"，让手动记账真正产出决策价值。
>
> 上游事实来源：全局 PRD `docs/prd/aubade-v1-prd.md`（验收点 7 统计、8 预算、9 剩余、10 同步）、原型 markdown `docs/design/aubade-v1-prototype.md`（§3 页面地图 / §4.1 账单页汇总卡 / §4.6 统计页 / §4.7 我的页 / §5 状态与异常）、**已实现的原型 demo `prototype/app/`（`app.js` 渲染 / `data.js` 聚合口径 / `styles.css` 样式——UI 形态与聚合口径以此 demo 为准）**、技术基线 `docs/design/aubade-v1-technical-baseline.md`（M5、M6、§7.5 聚合策略、§8 模型语义）、开发 DAG `docs/design/aubade-v1-dev-dag.md`（N02 小节）。
> 代码事实来源：直接阅读 N00/N01 已落地源码（本仓库无 `.codegraph/` 索引，代码量小，逐文件阅读，行号为本 PRD 写作时快照，可能有 ±1 漂移）。
>
> **原型 demo 关键实现事实（本节点 UI 与聚合直接对齐）**：分类占比 = **条形图**（`app.js:530-539`，`bar-fill` 宽度=百分比、色=`catColor`、按金额降序、点击下钻）；支出趋势 = **SVG 折线图**（`app.js:627` `lineChart`，含峰值/均值标注、面积渐变）；趋势横轴桶（`data.js:185` `trendSeries`）：周档=本周每日、月档=当月每日、年档=当年每月；分类占比口径 `data.js:173` `rangeCatBreakdown`（`pct = round(val/total*100)`，降序）；预算 `app.js:542-561`（`pct>100` 标红"已超支！"，进度条 `min(pct,100)`）；剩余金额 `data.js:96` `remaining()`；账单页汇总卡 `app.js:104-113`（剩余总额 · 本月支出 · 本月收入）；我的页剩余区 `app.js:662-668`（录入/调整初始总额）。

## 给用户看的摘要

做完这个节点，你的记账 App 就从"能记账"进化到"能看账"——记完一笔，立刻知道**还剩多少钱**、**这段时间花了多少、花在哪、有没有超预算**：

1. **账单页顶部立起汇总卡**：打开「账单」Tab，最上面出现一张卡：**剩余总额 · 本月支出 · 本月收入**。剩余总额需要你先录一个"初始总额"（比如现在卡里有一万二），之后每记一笔收入就加、支出就减，滚动显示；还没录初始总额时先显示"—"。
2. **「我的」页能录/改初始总额**：进「我的」Tab，顶部有剩余总额和「调整初始总额」按钮，第一次用点进去填一个数，剩余总额就有了。（我的页其余设置——预算填写、Key、分类管理、首次引导——是下一批节点 N07 的活，这节点先只做初始总额这一项。）
3. **统计 Tab 全部做出来**：进「统计」Tab，顶部一套「日 / 周 / 月 / 年」粒度切换 + 「‹ 时间 ›」前后翻页（**不能翻到未来**）：
   - **日档**：选某天，看当天每一笔流水和当天收支合计。
   - **周 / 月 / 年档**：看这段时间的**总支出 / 总收入**、**支出趋势折线**（横轴跟着粒度走：周档本周每天、月档当月每天、年档当年每月）、**支出分类占比**（哪类花得最多，点某一类能弹出这段时间里这一类的每一笔明细）。
   - **周 / 月档还有预算进度条**：设了预算就显示进度，接近 80% 提醒、超 100% 标红说"已超支"（年档没有预算概念）。
4. **改一笔账，剩余和统计立刻跟着变**：在账单页改/删任意一笔，剩余总额、统计合计、分类占比、预算进度全部实时刷新，不用手动刷。

**这一节点不做什么**（都在后面节点）：预算的**填写界面**在 N07（这节点只把已存在的预算值拿来显示进度，验证时用 DEBUG/单测直接写一条预算）；Key 配置、分类管理、首次引导、通知开关都在 N07；任何截图/语音/文本 AI 识别在 N03~N06。

## 目标

1. **剩余金额（M6）**：实现剩余总额的**派生计算**（模型层不存该值，见 `Aubade/Models/BalanceBaseline.swift:10`）——按技术基线 §8 精确口径 `剩余 = BalanceBaseline.initialAmount + Σ(基线后收入) − Σ(基线后支出)`，"基线后"= `occurredAt >= establishedAt`（用户已定，含基线当天及之后）；**无基线时显示"—"**。（注：原型 demo `data.js:96-98` 用的是**全量收支**简化版 `initialBalance + totalIncome − totalExpense`，本节点采用技术基线的精确"基线后"口径，是有意的精化而非偏离 demo。）在**账单页顶部汇总卡**和**我的页顶部**展示，并提供**「调整初始总额」入口**（录入/调整 `BalanceBaseline`）。
2. **账单页汇总卡**：在 `LedgerTabView`（`Aubade/Features/Ledger/LedgerTabView.swift:8` 已标注"汇总区 → N02"）顶部新增汇总卡：**剩余总额 · 本月支出 · 本月收入**（本月合计用 `LedgerFilter` 的本月半开区间口径）。
3. **统计聚合（M5）**：实现四档区间聚合——支出/收入合计、分类占比与明细下钻、支出趋势序列、周/月档预算进度与阈值状态。聚合逻辑抽为**无状态纯函数**（仿 `LedgerFilter` 风格，注入 `now`/`calendar`），复用 `LedgerFilter` 的**半开区间 `[start, end)`** 口径，采用技术基线 §7.5 的**按需实时查询聚合**（不建缓存表）。
4. **统计 Tab 界面**：替换现有占位 `AnalyticsPlaceholderView`（`Aubade/Features/AppShell/RootTabView.swift:41`），实现原型 §4.6 的日/周/月/年粒度切换 + 时间导航（**禁未来**）+ 日档流水 / 周月年档趋势+占比 / 周月档预算进度 + 分类占比下钻明细弹窗 + 本期无数据占位。
5. **预算消费（不含设置界面）**：读取已有 `Budget`（`Aubade/Models/Budget.swift:6`，`periodType` 周/月、`amount`）计算进度与超支状态（≥80% 接近、>100% 超支标红）；**设置界面留 N07**，本节点验证经 DEBUG/单测直接写入 Budget。
6. **调整初始总额入口**：在我的页提供最小的初始总额录入/调整，写 `BalanceBaseline`，并保证**基线唯一性**（调整即更新该唯一基线）。我的页其余设置项仍为占位/DEBUG，由 N07 补齐。
7. **实时同步**：剩余金额与所有统计在任意账单增删改后自动刷新（依赖 SwiftData `@Query` 变更驱动，与 N01 列表同机制）。
8. 所有读写经注入的 `ModelContext` / `LedgerStore`，**不自建 `ModelContainer`**（延续 N00/N01 硬约束，见 `Aubade/Persistence/PersistenceController.swift:6`、`Aubade/Store/LedgerStore.swift:9`）。

## 当前理解

### 数据底座已就绪（N00 交付，本节点消费；N02 无需改 Schema）

- **`Transaction`**（`Aubade/Models/Transaction.swift:5`）：统计以 `amount: Decimal`（第 7 行，**正值**，注释明确"方向由 direction 单独表达"——聚合需按 direction 自行定正负）、`direction: TransactionDirection`（第 8）、`occurredAt: Date`（第 9，**统计区间一律以此为准**）、`category: LedgerCategory?`（第 10，分类占比按此分组）为核心。`createdAt` 不参与统计（仅 N01 的"今日已记笔数"用它）。
- **`TransactionDirection`**（`Aubade/Models/Enums.swift:4`）：`.expense` / `.income`。趋势图与分类占比只统计**支出**（原型"支出趋势""支出分类占比"）；总支出/总收入分别按方向汇总。
- **`LedgerCategory`**（`Aubade/Models/LedgerCategory.swift:9`）：分类占比按 `category?.id` 分组、`name`/`direction` 决定展示；`icon`/`color` 预置为 nil，配色**一律走 `CategoryStyle`**（不读字段，见下）。
- **`Budget`**（`Aubade/Models/Budget.swift:6`）：`periodType: BudgetPeriodType`（`.weekly`/`.monthly`，`Aubade/Models/Enums.swift:21`）+ `amount: Decimal`，**无关联分类**（全局周/月预算）。模型注释（`:10`）明确"周/月各一条可同时存在，未加唯一约束，'每种周期仅一条'的保证指派给 N02/N07"——本节点**消费**预算，写入唯一化随设置界面落 N07；本节点消费时按"每周期取一条"处理（多条兜底策略留 TRD）。
- **`BalanceBaseline`**（`Aubade/Models/BalanceBaseline.swift:6`）：`initialAmount: Decimal`（第 7）+ `establishedAt: Date`（第 8）。注释（`:10`）钉死语义："**剩余金额是派生值，不建字段……派生计算在 N02**"。**本节点负责写入该基线（调整初始总额）并保证唯一性**。

### 现有可复用能力（N01 交付，直接复用，不改）

- **半开区间与时间口径**——`LedgerFilter`（`Aubade/Features/Ledger/LedgerFilter.swift`）：
  - `DateRangeFilter`（`:42`）与 `contains(_:now:calendar:)`（`:53`）已实现 `[start, end)` 半开区间；本周/本月用 `calendar.dateInterval(of: .weekOfYear/.month, for: now)`（`:58`/`:60`）。注释（`:48`）明确"**不用 `DateInterval.contains`**（含右端点误纳下周期首刻），改手写 `start <= date < end`"。
  - **N02 的四档区间（日/周/月/年）与时间导航必须对齐同一半开口径**；周/月可直接复用 `dateInterval(of:)`，日档用 `dateInterval(of: .day)`，年档用 `dateInterval(of: .year)`。`now`/`calendar` 注入方式照搬（便于单测钉边界）。
  - 分组范式 `groupByDay` + `DayGroup`（`:92`/`:101`）：日档流水列表与趋势的"按日分桶"可仿此写 `groupByDay`/按分类分组的纯函数。
- **金额格式化**——`AmountFormat`（`Aubade/Features/Shared/AmountFormat.swift`）：`plainString(_:)`（`:31`，无符号千分位，用于剩余总额/合计展示）、`signedString(_:direction:)`（`:23`，明细带符号）、`color(for:)`（`:37`）。保 `Decimal` 精度不经 Double（`:10`）。
- **分类配色/emoji**——`CategoryStyle`（`Aubade/Features/Shared/CategoryStyle.swift`）：`color(name:direction:)`（`:42`）+ `emoji(name:direction:)`（`:33`）。**分类占比条形/明细的配色与 emoji 必须走此主 API**（传 `tx.direction`），与账单列表标签配色一致（现有约定见 `LedgerRowView.swift:28`）。
- **数据获取范式**——`LedgerTabView`（`:13`）用 `@Query(sort: \Transaction.occurredAt, order: .reverse)` 取全量后内存过滤/分组（数据量小，增删改自动刷新）。**N02 统计页与汇总卡沿用同一策略**：`@Query` 全量 + 内存聚合，天然获得实时同步。
- **写操作**——`LedgerStore`（`Aubade/Store/LedgerStore.swift:8`，`struct` + 注入 `context`）：已有 `fetch`（`:17`，泛型谓词查询）、`createBudget`（`:73`）、`createBalanceBaseline`（`:83`）、`delete`（`:92`）。**注意：无任何聚合方法**（`:6` 注释"不预设 N02+ 的聚合查询"）、**无 Budget/BalanceBaseline 的 update 或唯一化方法**——N02 的聚合走新增纯函数；"调整初始总额"的唯一化需新增 Store 方法或覆盖策略（留 TRD）。

### 界面骨架现状

- **统计 Tab 占位**：`RootTabView` 的 `AnalyticsPlaceholderView`（`Aubade/Features/AppShell/RootTabView.swift:41`，当前 `ContentUnavailableView("统计"…)`），挂载于 `.tag(AppTab.analytics)`（`:27`）。**N02 替换其 body 即可，无需改 `TabView` 结构与 `AppTab` 枚举**（`:5`）。
- **我的页占位**：`ProfilePlaceholderView`（`:51`，DEBUG 下含调试菜单入口）。**N02 在其顶部新增"剩余总额 + 调整初始总额"区块**，其余保持占位/DEBUG，N07 补齐。
- **账单页汇总位**：`LedgerTabView`（`:8` 已注明"不含顶部汇总卡；汇总区 → N02"）。**N02 在列表顶部插入汇总卡**，不改其筛选/分组逻辑。
- **趋势图/占比图实现方式**（`import Charts` 的 Swift Charts vs 自绘）与聚合纯函数的落点，留 TRD；PRD 只约束可观察行为与半开口径一致性。

## 涉及的现有链路

- **被替换/扩展**：
  - `RootTabView.AnalyticsPlaceholderView`（`:41`）→ 真实统计视图（替换 body）。
  - `RootTabView.ProfilePlaceholderView`（`:51`）→ 顶部新增剩余总额 + 调整初始总额区块（其余占位不动）。
  - `LedgerTabView`（`:8` 顶部）→ 新增汇总卡（剩余·本月支出·本月收入）；筛选/分组代码不动。
- **被复用（只读消费，不改签名）**：
  - `LedgerFilter` 的半开区间/`DateRangeFilter`/`dateInterval(of:)` 口径与 `groupByDay` 分组范式。
  - `AmountFormat`（plainString/signedString/color）、`CategoryStyle`（color/emoji 主 API）。
  - `Transaction`/`LedgerCategory`/`Budget`/`BalanceBaseline` 模型与 `TransactionDirection`/`BudgetPeriodType` 枚举。
  - `LedgerStore.fetch`/`createBudget`/`createBalanceBaseline`/`delete`；`PersistenceController.makeInMemoryContainer()`（`:24`）供预览/单测。
- **本节点新增（下游依赖）**：
  - **剩余金额派生计算**纯函数（如 `BalanceCalculator`）：`initialAmount + Σ基线后收入 − Σ基线后支出`，无基线返回 nil→"—"。N03/N07 会间接依赖（识别入账/设置后剩余同步）。
  - **统计聚合**纯函数（如 `StatisticsAggregator`）：四档区间合计、按分类占比、支出趋势序列、预算进度+阈值状态。
  - **调整初始总额**的 `BalanceBaseline` 写入 + 唯一化（新增 Store 方法或覆盖策略，留 TRD）。
  - 统计 Tab 视图 + 我的页剩余区块 + 账单页汇总卡。
- **无既有调用方冲突**：统计/汇总为全新界面与纯函数；除替换两个占位 body、在两处插入区块外，不改 N00/N01 的模型字段、`LedgerStore` 现有方法签名、`PersistenceController` 与筛选/分组逻辑。

## 需求范围

### 1. 剩余金额（M6）与账单页汇总卡
- **派生计算**：`剩余 = initialAmount + Σ(基线后收入) − Σ(基线后支出)`；**"基线后" = `occurredAt >= establishedAt`**（含基线时刻当天及之后的账单计入增减，用户已定）。**无 `BalanceBaseline` 时剩余显示"—"**（不显示 0），并引导去录入。采用技术基线 §8 精确口径（区别于 demo `data.js:96` 的全量简化版）。
- **账单页顶部汇总卡**（`LedgerTabView` 顶部，对齐 demo `app.js:104-113`）：三项——**剩余总额**（无基线"—"）、**本月支出**、**本月收入**（本月用 `LedgerFilter` 本月半开区间对当前 `occurredAt` 汇总，对齐 demo `data.js:102-103` `monthExpense/monthIncome`）。金额走 `AmountFormat.plainString`。样式参考原型"晨曦渐变汇总卡"（视觉细节 TRD/实现）。
- **同步**：增删改账单后汇总卡实时刷新（`@Query` 驱动）。

### 2. 我的页：剩余总额 + 调整初始总额（最小设置）
- 我的页顶部展示**剩余总额（大数字，无基线"—"）** + **「调整初始总额」入口**。
- 点入可**录入/调整初始总额**（`Decimal` 校验，写 `BalanceBaseline`）；调整后保证**只有一条有效基线**（唯一化），剩余总额随之重算。
- 我的页其余（预算填写、Key、分类管理、首次引导、通知）**不做**（N07）；保持占位/DEBUG。

### 3. 统计 Tab：粒度与时间导航（原型 §4.6）
- 顶部**唯一时间入口**：「日 / 周 / 月 / 年」粒度切换 + 一条「‹ 具体时间 ›」导航条。
- **粒度切换时导航归位到"当前"**（本日/本周/本月/今年）。
- 导航条 `‹ ›` 前后翻页；**不允许翻到未来**——到"今天所在区间"时 `›` 禁用置灰（与 N01 手动记账"禁未来日期"口径一致）。
- 各档区间用 `calendar.dateInterval(of: .day/.weekOfYear/.month/.year, for:)` 的**半开 `[start,end)`** 口径，`now`/`calendar` 注入。**周档必须钉死 `Calendar.firstWeekday = 2`（周一起）**（技术基线 §2/§8"周按自然周、周一起"，`LedgerFilter.swift:51` 注释已提示需固定 firstWeekday，避免系统区域默认周日导致周界与预算错位）。

### 4. 统计 Tab：日档
- 顶部显示**当天支出合计 / 当天收入合计**。
- 列出当天每一笔流水（复用 N01 行样式/`CategoryStyle`），**点某笔进详情编辑**（复用 N01 详情/编辑页）。
- **不显示趋势图**（原型 §4.6 日档契约）。
- 当天无账单：显示"这一天还没有账单"占位。

### 5. 统计 Tab：周 / 月 / 年档
- **总支出 / 总收入**：区间内按方向汇总（`Decimal`，对齐 demo `data.js:171` `rangeSum`）。
- **支出趋势折线图**（对齐 demo `app.js:627` `lineChart` + `data.js:185` `trendSeries`）：**SVG 折线图**（含峰值/均值标注、面积渐变），横轴跟随粒度——**周档=本周每日、月档=当月每日、年档=当年每月**（仅支出）。**本期无支出时显示"本期还没有支出"占位而非空图**（demo `app.js:521`）。
- **支出分类占比**（对齐 demo `app.js:530-539` + `data.js:173` `rangeCatBreakdown`）：**条形图**——区间内按分类汇总支出、按金额降序、`占比 = round(金额/总支出×100)`，条形宽度=占比、**配色走 `CategoryStyle.color(name:direction:)`**（与账单标签一致，传支出方向），行尾显示 `占比% · ¥金额 ›`。**本期无支出时占比区显示空态**（原型 §5 要求，与趋势占位并列）。
- **分类占比下钻**（demo `app.js:537` `openCatDetail`）：点某一类 → 弹出**该分类在当前时间区间**的记录明细（标题=分类+区间、共 N 笔、合计），明细合计与占比数字一致；**点某笔进详情可改/删**（复用 N01 详情编辑，改删后占比同步刷新）。
- **年档不显示预算**（原型 §4.6 + demo `app.js:542`，年档无预算概念）。

### 6. 统计 Tab：预算进度（仅周 / 月档，消费已有预算）
- 读取对应 `periodType` 的 `Budget`（`Budget` 无时间戳，靠**写侧唯一化**保证每周期至多一条，读侧 `filter{periodType==x}.first`，见已确认约定 3），计算进度（对齐 demo `app.js:542-561`）：**已设**→进度条（当前区间支出 / 预算额）+ 百分比，进度条宽度 `min(pct,100)%`；**超 100%**（如 2,055/1,500=137%）进度条标红 + "已超支！"（仅提示不阻止）。**接近阈值（默认 80%）**给接近提示样式——这是技术基线 §8 明确要求、demo 尚未实现的部分，本节点按基线补齐 80%~100% 的"接近"态。**未设预算**→显示"还没设置{周/月}预算，去『我的』设置 ›"（demo `app.js:547`，引导指向 N07 的我的页，本节点不实现设置界面）。
- 预算**设置界面不在本节点**；验收经 DEBUG 入口/单测直接写入 `Budget` 后观察进度与标红（TRD 需在 `DebugMenuView` 补一个写 Budget 的入口以支撑肉眼视觉验收）。

### 7. 统计聚合纯函数（新增，无状态、可单测）
- 抽出无状态聚合函数（注入 `transactions`/`now`/`calendar`），产出：区间收支合计、按分类占比列表、支出趋势序列（按粒度分桶）、预算进度与阈值状态。
- 复用 `LedgerFilter` 半开区间口径；保持 `Decimal` 纯运算不经 Double（对齐 `DecimalPrecisionTests` 约定）。
- 配套单测：区间边界（本期最后一刻入/下期第一刻出）、分类占比合计=总支出、剩余金额公式、预算阈值（79%/80%/100%/101%）等。

## 不做什么

以下均属其他节点，本节点**不实现**：
- **预算的设置/填写界面**（周/月预算输入 UI）→ N07。本节点仅**消费**已有 `Budget` 显示进度；写入唯一化随设置界面落 N07。
- **我的页完整设置**：DeepSeek Key 填写与状态、分类管理界面、首次启动引导、通知开关、权限申请 → N07。本节点我的页只做"剩余总额 + 调整初始总额"最小项。
- **任何 AI 识别入口**：截图/语音/文本识别、DeepSeek/OCR/Speech 调用、结果卡片识别数据填充 → N03~N06。
- **统计缓存表/预计算**：技术基线 §7.5 明确 v1 按需实时查询聚合，不建缓存（若真机某档卡顿，后续节点再评估，不在本节点范围）。
- 不改动 N00/N01 的模型字段、`LedgerStore` 现有方法签名、`PersistenceController` 容器配置、`LedgerFilter` 筛选/分组逻辑、N01 记账/账单界面既有行为。

## 验收标准

（对齐 DAG 中 N02 的"退出标准（可观察）"与全局 PRD 验收点 7 / 8 / 9 / 10。可用模拟器或真机肉眼观察，聚合逻辑另以单元测试佐证。）

1. **剩余金额（PRD 验收点 9）**：未录初始总额时，账单页汇总卡与我的页剩余总额显示**"—"**；在我的页录入初始总额（如 12,000）后，剩余 = 12,000；再记一笔支出 200、一笔收入 500，剩余变为 12,300（`初始 + 收入 − 支出`），金额 `Decimal` 无浮点误差。
2. **调整初始总额唯一性**：多次"调整初始总额"后，系统只有一条有效基线，剩余总额按最新基线重算（可经 DEBUG/单测佐证只有一条 `BalanceBaseline`）。
3. **账单页汇总卡**：账单页顶部显示剩余总额 · 本月支出 · 本月收入；本月支出/收入等于当月（半开区间）内对应方向账单合计；增删改账单后三项实时刷新。
4. **统计合计与分类占比（PRD 验收点 7）**：在周/月档，总支出/总收入等于该区间账单按方向的合计；支出分类占比各类金额之和 = 总支出、占比之和 = 100%（边界内/外账单各验，区间边界正确）。
5. **趋势与横轴跟随粒度**：周档趋势横轴为本周每日、月档为当月每日、年档为当年每月，仅统计支出；本期无支出时显示"本期还没有支出"占位而非空图。
6. **分类占比下钻**：点分类占比某一类，弹出该分类在**当前时间区间**的明细（共 N 笔 + 合计），合计与占比数字一致；点明细中某笔进详情可改/删，改删后占比同步刷新。
7. **预算进度与超支标红（PRD 验收点 8）**：经 DEBUG/单测写入月预算（如 1,500）后，统计月档显示进度；当月支出达 ≥80% 显示接近、>100%（如 2,055/1,500=137%）进度条标红并提示"已超支"；未设预算显示"未设置预算，去设置"；年档不显示预算区。
8. **粒度切换与禁未来导航**：日/周/月/年可切换，切换后时间导航归位到当前区间；`‹ ›` 前后翻页正常，翻到"今天所在区间"时 `›` 禁用置灰，无法翻到未来；日档某天无账单显示"这一天还没有账单"。
9. **实时同步（PRD 验收点 10 同步部分）**：在账单页/日档明细对任意账单执行增/删/改后，剩余总额、统计合计、分类占比、趋势、预算进度全部自动刷新（无需手动重进页面）。
10. **不越界**：预算无设置界面（仅显示进度与"去设置"引导）；我的页除剩余总额+调整初始总额外仍为占位；无任何 AI 识别入口；统计不建缓存表。

## 已确认约定

（以下在 PRD 评审前已由用户拍板或由已实现原型 demo 定死，作为既定实现约束，非待确认项。TRD 直接据此落地。）

1. **分类占比 = 条形图**：由原型 demo `app.js:530-539` 定死（`bar-row`/`bar-fill`，宽度=占比、色=`catColor`、按金额降序、点击下钻），非环形。原型 markdown 待确认清单中"条形/环形"以 demo 实现为准。
2. **剩余金额"基线后"边界 = `occurredAt >= establishedAt`**（用户已定）：含基线时刻当天及之后的账单计入增减。TRD 钉死并加边界单测（同日边界、基线前账单不计）。
3. **多条同周期预算：写侧唯一化 + 读侧取唯一**（用户已定"取最新一条"，落地为唯一化）：`Budget` 模型只有 `id/periodType/amount`、**无时间戳字段**（`Budget.swift:5-9`），无法按时间"取最新"。因此本节点采用**写侧唯一化**——写预算前先删同 `periodType` 旧记录再插（对称于 `BalanceBaseline` 的清空+插入），保证每周期至多一条，读侧 `filter{periodType==x}.first` 即唯一值。真正的写入唯一化入口在 N07 设置界面；本节点 DEBUG 写入即遵循此清插规则。`BalanceBaseline` 有 `establishedAt` 可排序，读侧取最新一条 + 写侧同样清插唯一化（双保险）。
4. **剩余金额采用技术基线精确口径**：`initialAmount + Σ(基线后收入) − Σ(基线后支出)`，而非 demo `data.js:96` 的全量简化版——这是有意精化（demo 为原型示意，未区分基线时点）。
5. **预算阈值补齐 80% 接近态**：demo 仅实现 `>100%` 标红，本节点按技术基线 §8 补齐 `≥80%` 接近提示样式。
6. **周首日 = 周一**：`Calendar.firstWeekday = 2`，周档区间与周预算据此对齐（技术基线 §2/§8）。
