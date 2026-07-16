# 反馈批次 01 技术基线 — 剩余总额 / 日期填充 / 最近记录删除 / 自定义分类 / 截图多笔 / UI 还原

> 模式 `existing_batch`：Aubade v1（N00~N07 已合并 main）真机验收后的一批反馈修复/增强。**架构地基已定死**（见 `docs/design/aubade-v1-technical-baseline.md`：SwiftUI + SwiftData + @Observable、四 Tab、DeepSeek/Vision/Speech 分工、Keychain、URLSession），本基线**不重述架构**，只定清每条需求的**改造边界、动了什么契约/约定、迁移与兼容风险、测试增删**。
>
> 事实来源：逐文件阅读核实（本仓库无 `.codegraph/`），行号为写作时快照，可能 ±1 漂移。所有关键事实已交叉验证。

## 给用户看的摘要

这批 6 条我按代码事实核完了，性质和改动面差别很大，技术上分三档：

- **改几行就好（R1）**：剩余总额 bug 的根子就在**一处** —— `BalanceCalculator.swift:14` 那行按日期过滤。去掉它、改成"全部账都算"即可。全项目只有这一处这么过滤，统计页用的是另一套（按统计周期），不受影响。代价是**要改 1 个单测**（那个测试现在正锁着"只算基线后"的旧口径）。这条**推翻了 v1 定的"约定2"**，属于你已拍板的口径变更。
- **中等，主要是补 UI 和 Store（R3/R4）**：
  - R3 最近记录删除：删除逻辑（`EditorActions.makeDelete`）和二次确认弹窗**都是现成的**，账单页已经在用。唯一麻烦是记账页最近记录是用 `VStack` 堆的、不是 `List`，SwiftUI 的"侧滑删除"必须要 `List` 才有——所以要么把最近记录改成 `List`，要么用长按触发删除。这是个**要你选的技术取舍**（见下）。
  - R4 自定义分类：数据模型**完全不用动**（字段早就够）。要补的是 Store 层三个方法（改分类、删除时保护预置、查一个分类被多少账单用了）+ 我的页那块只读标签改成能增删改。这里有个**已存在的坑**：现在删分类时账单会自动"变成未分类"（数据库层面的 `.nullify`），而原型里说的是"转到『其他』"——两者不一致，得定一个。
- **较大，动识别解析链（R2/R5）**：这两条改的是同一批文件，PRD 也建议合成一个节点，我确认代码事实支持合并。
  - R5 截图多笔是**本批最大改动**：现在从解析契约（`ParsedTransaction` 是单个结构体）、DeepSeek 的 prompt（明写"提取一笔"）、到入账（一次落一笔）、到结果卡片（单笔）全链路都是"一笔"，要改成"多笔"。**账单数据模型不用动**（多笔 = 多条记录），但契约、prompt、解码、入账循环、结果卡 UI、后台通知全要改，连带一批测试。
  - R2 日期未识别：好消息是——DeepSeek 的 prompt **早就要求**"取不到日期就返回空"，契约里 `occurredAt` 也**本就是可空**的。问题只出在归一层（`RecognitionNormalizer`）把这个"空"**默默填成了今天**，把"这是猜的"这个信息丢了。所以 R2 的解析/契约层不用动，改动集中在**如何表达并展示"这是猜的"**。这里有个**没法回避的取舍要你定**：原型要求"日期未识别"标记不仅出现在识别结果卡，还要出现在**账单列表/最近记录行、直到你确认才消失**——而列表行是从数据库读的，要让标记在列表里持久显示，就**必须**让"这是猜的"这个事实能被持久化或可派生。这与"不动数据模型"直接相关，有三条路（弃列表持久标记 / 给 Transaction 加字段 / 用派生启发式），各有代价，列入待确认由你拍板（见 §5 D6、§9）。
- **纯视觉，面最广（R6）**：项目现在**没有**统一的设计 token 层（`Features/Shared/` 只有分类色和金额格式两个小工具，用的还是系统色 `.green`/`.orange`）。要按原型的"晨曦暖白"重做，得先建一套 token（颜色/圆角/字重/间距），再逐页改样式。**不动数据和业务逻辑**。这条也**推翻了 v1 的"约定4"**（支出用主文本色/收入用系统绿 → 改成珊瑚/青绿）。

技术基线定"改哪、动了什么、风险在哪、测试怎么动"；**具体代码怎么写留到各节点 TRD**。下面有 **7 个待确认项**需要你拍板，其中 3 个会影响节点怎么拆。

## 1. 文档目的与范围

- 把已通过评审的 PRD（`docs/prd/batch01-feedback-fixes-prd.md`）与原型（`docs/design/batch01-feedback-fixes-prototype.md`）收敛为**改造事实来源**：每条需求的触点、契约/约定变更、迁移与兼容风险、测试策略、开发顺序建议。
- 作为本批**开发 DAG** 拆节点的依据，以及各**节点 TRD** 的上游约束。
- **不做**：不写 Swift 源码、不给文件级实现计划（留节点 TRD）；不重述 v1 已定架构。

## 2. 现有系统事实（本批触点，均逐文件核实）

### R1 剩余总额 — 唯一过滤点确凿

- `BalanceCalculator.remaining(transactions:baseline:)`（`Aubade/Features/Analytics/BalanceCalculator.swift:12-18`）：
  ```swift
  guard let baseline else { return nil }
  let after = transactions.filter { $0.occurredAt >= baseline.establishedAt }   // ← 唯一过滤点（:14）
  return baseline.initialAmount + sum(after, .income) - sum(after, .expense)
  ```
  注释（:9-11）写明"基线后 = occurredAt >= establishedAt（**PRD 已确认约定 2，同刻计入**）"。
- **全项目唯一**用 `establishedAt` 过滤交易的点就是 `:14`。其余 `establishedAt` 读取点均为"在多条 baseline 里挑最新一条"或写入侧，**不可误改**：
  - `LedgerTabView.swift:73`、`RootTabView.swift:99`：`baselines.max { $0.establishedAt < $1.establishedAt }`（挑最新）
  - `LedgerStore.swift:115`：`SortDescriptor(\.establishedAt, .reverse).first`（取最新）
  - `RootTabView.swift:128` / `OnboardingView.swift:95` / `DebugMenuView.swift:159`：写入 `establishedAt: Date()`
- `StatisticsAggregator`（同目录）**完全不依赖** `establishedAt/baseline`，只用统计周期半开区间 `inRange`（`:134-136`，`occurredAt >= p.start && < p.end`）。**改 R1 不影响统计。**
- `BalanceBaseline` 模型（`Aubade/Models/BalanceBaseline.swift`）：`id/initialAmount/establishedAt`，剩余为派生值不建字段。
- 剩余展示点：`LedgerTabView.swift:83-90`（账单页 hero，nil→"—"）、`RootTabView.swift:102-161`（我的页，nil→"未设置"+按钮文案）。二者只消费返回值，对内部过滤口径透明。

### R2 消费日期填充 — 契约已能表达 nil，被归一层抹掉

- 契约 `ParsedTransaction`（`Aubade/Features/Recognition/Parsing/TransactionParsing.swift:5-12`）：`occurredAt: Date?` **本就可空**，`amountText: String`（金额是串）。
- `DeepSeekClient`（`.../DeepSeekClient.swift`）：prompt **已要求** `occurredAt` 按 `"yyyy-MM-dd HH:mm"` 返回、"取不到留空"；`parseDate`（:88-94）空串/解析失败 → `nil`。**日期抽取链路已经能表达"识别不到"。**
- **断点**：`RecognitionNormalizer.occurredAt(_:now:)`（`.../RecognitionNormalizer.swift:18-21`）：
  ```swift
  guard let date else { return now }          // nil → now（此处丢失"未识别"信息）
  return date > now ? now : date              // 禁未来：晚于 now clamp 到 now
  ```
  nil 被兜成 now，"这是猜的"信息在此丢失，未传入 `Transaction`、未传入结果卡。
- `Transaction.occurredAt`（`Aubade/Models/Transaction.swift:9`）：**非可选 `Date`**，落库恒有值，**当前无"日期是否为兜底值"的标记字段**。
- 结果卡 `RecognitionResultCard`（`TextRecognitionView.swift:268-298`）：以单个 `tx` 输入，内嵌 `TransactionEditor` + `onDelete` 二次确认 + `rawText` 折叠原文——已有扩展点范式，"日期未识别"高亮可循此加扩展点。
- **持久列表标记的三条技术路径**（原型要求标记出现在账单列表/最近记录行、直到确认才消失；标号与 §5 D6 对齐）：
  - **(a) 弃列表持久标记**：只在识别结果卡当次高亮，不进列表；零迁移、零误判，但**不满足原型"列表行持久标记"**。
  - **(b) 加字段**：给 `Transaction` 加 `var dateInferred: Bool`（或 `occurredAtIsInferred`）→ 需 SwiftData 轻量迁移，与"不动模型"约束冲突，但语义最干净、列表可直接读。
  - **(c) 派生启发式**：不加字段，用现有字段推断——如"`occurredAt` 与 `createdAt` 同刻（兜底时二者都被设为 now）"近似判定；零迁移，但对"用户手动把日期改成记账当天"会误判，且后台/前台 createdAt 语义需核。
  三者取舍见 §5 D6，属用户拍板项。

### R2 兜底值语义（非被推翻约定，勿误判）

- `occurredAt` "识别不到取 now" 是 v1 既有兜底（`RecognitionNormalizer.occurredAt` 注释"约定 6"），**本批不推翻此兜底值本身**——兜底后仍是 now（除非 D6 选"留空强制填"）。R2 改的是"**让这次兜底被用户看见/可辨识**"，不是改兜底数值。账单**排序逻辑本身正确、无需改**（`LedgerTabView` `@Query(sort:\.occurredAt,.reverse)`），下游勿误改排序（PRD R2 核查结论）。

### R3 最近记录删除 — 逻辑现成，结构差异是唯一难点

- 记账页最近记录（`RecordTabView.swift:343-377`）：**`VStack(spacing:0)` + `Button`**（非 `List`），点进 `editSheet`（:394-402）**未注入 onDelete**（注释直言"删除在切片 03"）。数据源 `@Query(sort:\.occurredAt,.reverse)`（:52），删除后自动刷新。
- 账单页删除（`LedgerTabView.swift`）：**`List` + `ForEach` + `.swipeActions`**（:212-226）置 `pendingDelete` → `.confirmationDialog`（:52-58，"删除这笔账单？/删除后无法恢复"）→ `delete(_:)`（:271-274）调 `EditorActions.makeDelete`。
- `EditorActions.makeDelete(store:tx:)`（`Editor/EditorActions.swift:26-30`）：返回删除闭包（`store.delete(tx)`），**二次确认由调用方套**。已被账单页和 `DeepLinkResultSheet` 复用。
- **关键结构差异**：`.swipeActions` 依赖 `List`/`ForEach` 上下文；记账页最近记录是 `VStack`，直接套不了 → 见 §5 决策 D1。

### R4 自定义分类 — 模型零改动，Store 缺三样，UI 只读

- `LedgerCategory` 模型（`Aubade/Models/LedgerCategory.swift:9-21`）：`id/name/direction/icon:String?/color:String?/isPreset:Bool/sortOrder:Int` + 关系 `@Relationship(deleteRule:.nullify, inverse:\Transaction.category) transactions`。**做自定义分类不需要改模型。**
- `LedgerStore`（`Aubade/Store/LedgerStore.swift`，struct）：
  - `createCategory(name:direction:icon:color:isPreset:sortOrder:)`（:26-35）**已支持建 isPreset=false**。
  - **缺 `updateCategory`**（现状改分类靠裸改属性 + `context.save()`，见 `ModelCRUDTests.testCategoryCRUD`）。
  - `delete<T>(_:)`（:120-123）泛型删除，**无预置保护**（isPreset=true 照删）。
  - **无引用计数方法**，但模型反向关系 `category.transactions.count` 可直接得。
- 我的页分类区 `categorySection`/`categoryTags`（`RootTabView.swift:270-296`）：**只读 capsule 标签流**，`@Query` 只取 `isPreset==true`（自定义分类当前根本不显示），header 写死"分类（预置）"。
- 预置 seed（`Aubade/Persistence/PresetCategories.swift:14-31`）：启动时 `seedIfNeeded`，幂等判据是"已存在任一预置分类则整体跳过"——**注释明说此设计是为了"用户删掉预置后重启不补回"**，与"预置不可删"保护有语义张力 → 见 §5 决策 D3。
- **删分类归属差异**：模型 `deleteRule:.nullify` 使删分类后账单 `category` **置 nil（未分类）**，而原型/PRD 说的是**转到"其他"**。二者不一致 → 见 §5 决策 D2。

### R5 截图多笔 — 全链路单笔，本批最大改动面

- 契约单笔：`ParsedTransaction` 是单结构体，`parse(text:categories:) -> ParsedTransaction`（`TransactionParsing.swift:15-18`）；全项目无 `[ParsedTransaction]` 变体。
- `DeepSeekClient`：prompt 明写"提取**一笔**账单"，`response_format: json_object`；decode 只取 `choices.first`、按**单个** `ExtractedFields` 对象解码（:68-85）。
- 编排 `RecognitionEntry.recognizeAndSave(...)`（`TextRecognitionView.swift:12-40`）：parse 单笔 → 归一 → `store.createTransaction` **落一笔**，返回单个 `Transaction`；失败（parse 抛错/无金额）都在落库前，不产脏账。
- 后台 `BackgroundIntakeService.intake(imageData:)`（`Shortcut/BackgroundIntakeService.swift:21-61`）：一张图 OCR → `recognizeAndSave` **落一笔** → 成功通知携**单笔** payload（`IntakeNotification.success(transactionID:amountText:categoryName:merchant:)`）；失败 `context.rollback()` + 留原图。
- 结果卡 `RecognitionResultCard` / `DeepLinkResultSheet`：均以**单个 tx** 输入，多笔需新 UI。
- `Transaction` 模型：**不需改**（多笔 = 多条独立记录）。

### R6 UI 还原 — 无 token 层，系统观感，推翻约定 4

- **无统一设计 token/Theme/Palette 文件**（grep 确认）。`Features/Shared/` 仅 `CategoryStyle.swift`（分类色用系统 `.purple/.orange/.blue/.teal/.pink/.gray/.green`）、`AmountFormat.swift`。
- `AmountFormat.color(for:)`（`Shared/AmountFormat.swift:37-42`）：**支出 `.primary`（系统主文本色）、收入 `.green`（系统绿）**，注释"已确认约定4"。原型要求珊瑚 `#e8785c` / 青绿 `#4fa87a` → **推翻约定 4**。
- 记账页（`RecordTabView.swift:200-217`）：`NavigationStack + ScrollView + .navigationTitle`、`EntryButton` 裸 emoji+标题、`.background(.background.secondary, in: RoundedRectangle(cornerRadius:12))`——**系统默认观感，无晨曦渐变 hero、无暖米白底、无 token**。
- 原型 token 事实来源：`prototype/app/styles.css:4-26`（`--bg:#f6f3ee`、`--dawn` 晨曦渐变、`--expense:#e8785c`、`--income:#4fa87a`、`--r-lg:22px`、字重 800）。

## 3. 模块与入口（本批改动清单，按需求组织）

| 需求 | 改动文件（核实路径） | 改动性质 |
|---|---|---|
| R1 | `Analytics/BalanceCalculator.swift:14`（去日期过滤）；`Onboarding/OnboardingView.swift`、`AppShell/RootTabView.swift` 初始总额录入处（补双重扣减提示文案，见 §5 D7） | 去过滤改全量求和 + 录入处加提示 |
| R2 | `Parsing/RecognitionNormalizer.swift`、`RecognitionEntry`(TextRecognitionView.swift)、`RecognitionResultCard`；**若 D6 选列表持久标记**再加 `Models/Transaction.swift`（加字段+迁移）或派生逻辑 | 归一层保留"日期未识别"标志 + 结果卡高亮；列表标记范围取决于 D6 |
| R3 | `Record/RecordTabView.swift`（最近记录区 + editSheet 注入 onDelete） | 复用 `EditorActions.makeDelete` + 二次确认；结构选型见 D1 |
| R4 | `Store/LedgerStore.swift`（补 updateCategory/预置保护/引用计数）、`RootTabView.swift`（分类区改可管理 + 放开 @Query）、分类编辑器新 UI | Store 补方法 + UI 增删改 |
| R5 | `Parsing/TransactionParsing.swift`（契约→多笔）、`DeepSeekClient.swift`（prompt+decode）、`RecognitionEntry`（循环落多笔）、`BackgroundIntakeService`+`IntakeNotification`（后台多笔+通知）、多笔结果卡新 UI、`MockTransactionParser` | 全链路单笔→多笔 |
| R6 | 新建设计 token 层（`Features/Shared/` 或新 `DesignSystem/`）、`AmountFormat.color`、`CategoryStyle`、逐页 View 样式 | 抽 token + 逐页改样式，不动逻辑 |

## 4. 设计约束

1. **默认不动数据模型存储结构**：`Transaction`/`Budget`/`BalanceBaseline`/`LedgerCategory` 的持久字段默认不改。R4 靠 `LedgerCategory` 既有字段；R5 多笔靠解析/编排层。**唯一例外**：R2 若经 D6 选"给 Transaction 加 `dateInferred` 字段"实现列表持久标记，则触发一次 SwiftData 轻量迁移——此为用户拍板项，不是本基线单方决定。基线不预设 R2 一定不落库。
2. **失败不产脏账（沿用 v1 不变量）**：R5 多笔要显式定义"部分笔失败"语义（见 D5）；无论如何，无金额/解析失败的笔不得落库。
3. **口径变更需在测试焊死**：R1 推翻约定 2、R6 推翻约定 4，对应单测必须同步更新为新口径（见 §7），不能只改实现留旧测试。
4. **复用既有范式**：R3 删除复用 `EditorActions.makeDelete` + 两套二次确认范式（`pendingDelete`+dialog / 先 dismiss 再删）；R2 结果卡复用 `TransactionEditor` 扩展点（如 `RecognitionResultCard` 的 `onDelete`/`rawText` 注入方式）。
5. **R2 归一层禁未来 clamp 必须保留**：`occurredAt` 现有 `date > now → now` 的 clamp（对齐编辑器 DatePicker 禁未来）不能因改兜底逻辑而丢失。
6. **R6 只动视觉层**：token 化不改任何 `@Query`/Store/聚合/编排；语义色改动集中在 `AmountFormat.color` + `CategoryStyle` + 各 View 背景，逐页可回归。

## 5. 关键决策点（需用户/节点拍板）

> 以下决策影响实现方式或节点拆分，**技术基线阶段先列明取舍与建议，最终以你评审拍板为准**。

- **D1（R3 结构选型）**：记账页最近记录是 `VStack+Button`，`.swipeActions` 需 `List`。两条路：**(a) 把最近记录改成 `List`** —— 得侧滑删除、与账单页体验一致，但要调样式（List 默认样式与当前圆角卡不同，且 R6 又要重做视觉）；**(b) 保持 VStack，用长按/按钮触发 `pendingDelete` 走同一 `confirmationDialog`** —— 改动小但交互与账单页侧滑不完全一致。**建议 (a)**，且与 R6 视觉重做协同（R6 本就要重做列表卡片）。
- **D2（R4 删分类归属）**：模型 `deleteRule:.nullify` 现状 = 删分类后账单变**未分类(nil)**；原型说**转"其他"**。两路：**(a) 删除前把该分类账单批量改到"其他"再删**（对齐原型，需 Store 逻辑）；**(b) 顺从 `.nullify` 让账单变未分类**（改动小，但与原型不符，且"未分类"在统计/列表如何显示要另定）。**建议 (a)**，与原型一致、语义清楚。
- **D3（R4 预置保护 vs seed 幂等）**：seed 幂等判据是"删了预置不补回"，与"预置不可删"保护冲突。**建议：预置分类禁删禁改名**（保护），则 seed 幂等的"不补回"分支实际不会触发，无害；预置是否允许改图标/色为次要待确认（见 §9）。
- **D4（R2/R5 是否合并节点）**：两者改动集中在同一批识别文件（`ParsedTransaction`/`DeepSeekClient`/`RecognitionNormalizer`/`RecognitionEntry`/结果卡），代码事实支持合并。**建议合并为一个"识别改造"节点**，减少对解析层的重复改动与测试返工。
- **D5（R5 多笔覆盖范围与失败语义）**：①多笔只覆盖截图，还是文本识别也多笔？②后台快捷指令（N06）是否多笔、通知如何呈现"已记 N 笔"？③一张图部分笔失败时：成功的入账 + 失败的提示、整体不产脏账的具体策略。**这些是 §9 待确认，直接影响 R5 节点范围**。
- **★ D6（R2"日期未识别"标记范围与落地）**：原型要求标记出现在**账单列表/最近记录行且直到确认才消失**（持久），不止识别结果卡。三条路：**(a) 弃列表持久标记**——只在识别结果卡当次高亮，零迁移零误判，但不满足原型持久要求；**(b) 给 `Transaction` 加 `dateInferred` 字段**——满足原型、语义干净，但要一次 SwiftData 轻量迁移（破"不动模型"默认）；**(c) 派生启发式**（如 occurredAt==createdAt 近似）——零迁移，但用户把日期改成记账当天时会误判。**基线不替你选**；连带"识别不到日期时按今天填+高亮 vs 留空强制填"（原型 §6#1、PRD R2）也一并请你定。倾向 (b)（最贴原型、迁移成本低），但取舍归你。
- **★ D7（R1 双重扣减提示落点）**：PRD R1 口径边界（你已拍板）要求初始总额录入处提示"填当前净值、勿再补录初始总额之前的历史账，否则双重扣减"。落点在 `OnboardingView`（首次引导录入）+ `RootTabView` 我的页"调整初始总额"入口。这是 R1 节点的交付项之一，不只是改 `BalanceCalculator` 一行。确认文案口径即可（建议简短一句 + 可选"了解更多"）。

## 6. 数据与状态影响

- **R1**：`remaining` 派生口径变更（去日期过滤），无存储变化；账单页"—"/我的页"未设置"的 nil 分支不变。**副作用**：早于基线时刻的账也计入，用户若"填的净值已扣过某早期消费、该消费又作为账单存在"会双重扣减——**须在初始总额录入处提示**（D7，落 OnboardingView + RootTabView，不只改算法）。
- **R2**："日期未识别"标志的传递/存储范围取决于 D6：选 (a) 仅当次内存、结果卡关闭即消、不落库；选 (b) 落 `Transaction.dateInferred`、列表持久、用户确认后置 false；选 (c) 派生、不落库但列表可显示。三者都不改 `occurredAt` 兜底数值本身。
- **R3**：删除经 `store.delete` → `@Query` 自动刷新，剩余总额/统计随 SwiftData 变更同步。
- **R4**：自定义分类增删改经 Store 落库；删除按 D2 决定账单归属；`@Query` 需从"仅预置"放开到"全部分类"（或另开自定义区）。
- **R5**：多笔 = 多条独立 `Transaction`，各自 `occurredAt/amount/merchant`；无新增关联。
- **R6**：纯展示层，无数据/状态变化。

## 7. 兼容与迁移风险

- **SwiftData schema 迁移**：本批**默认无迁移**（R3/R4/R5 都不加改持久字段）。**唯一可能的迁移**：R2 若经 D6 选方案 (b)（`Transaction.dateInferred` 字段），则需一次轻量迁移（加一个带默认值 false 的可选/布尔字段，SwiftData 轻量迁移可自动处理）。D6 选 (a)/(c) 则仍无迁移。此迁移是否发生由用户 D6 决定。
- **推翻 v1 约定的测试更新**（必须同步，否则测试与实现打架）：
  - **R1 → 约定 2**：`BalanceCalculatorTests.testBaselineBoundaryInclusive`（:91-102）显式锁"只计基线后 + >= 同刻"，**必改**（如期望 1130 → 1180）；`testRemainingFormula`/`testRemainingDecimalPrecision`（账单都在基线后）语义前提需复核，数值大概率不变；`StatisticsAggregatorTests` 全不受影响。
  - **R6 → 约定 4**：`AmountFormat.color` 若有对应断言（支出.primary/收入.green）需随珊瑚/青绿更新。
- **R5 契约变更的测试连锁**（单→多笔的硬冲突）：
  - `count == 1` 断言：`RecognitionEntryTests`（:45）、`BackgroundIntakeServiceTests`（:96）、`RecognitionEntryScreenshotTests`（:47）。
  - `ParsedTransaction(...)` 构造 + 断言：`MockTransactionParser`（4 处定值）、`MockParserTests`。
  - 后台成功通知单笔 payload 断言：`BackgroundIntakeServiceTests:111-117`。
  - `DeepSeekClient` decode 无现成单测（靠编译 + 端到端自测），改对象→数组不破坏既有单测，但需新增多笔 decode 覆盖。
- **R2 兜底语义测试**：`RecognitionNormalizerTests.testOccurredAtFallbackAndClamp`（:50-57）锁 `nil→now` + clamp，若改兜底策略需同步更新（保留 clamp 断言）。
- **R3/R4 测试空白**：`updateCategory`、预置保护、引用计数、最近记录删除均无现成测试，属新增覆盖区（见 §8）。现有 `RelationshipTests.testDeleteCategoryNullifiesTransaction` 已兜底"删分类账单归属"行为，D2 若改为"转其他"需更新此测试。

## 8. 测试策略

- **R1**：更新 `testBaselineBoundaryInclusive` 为新口径；补一条"账单早于 establishedAt 也计入剩余"的正向断言（对齐 PRD 验收 1）。**D7 提示为 UI 文案，无单测**，靠录入页面人工核对提示存在。
- **R2**：新增"解析 occurredAt=nil → outcome/draft 带 dateInferred 标志 + 结果卡显示提示"的单测/UI 断言；保留 `occurredAt` clamp 断言。**若 D6 选 (b)**：补"入账落 dateInferred=true / 用户改日期后置 false / 列表行据此显示标记"的用例；选 (c) 补派生判定用例。
- **R3**：新增"记账页最近记录删除 → 二次确认 → 删除后 @Query 刷新 + 剩余/统计同步"用例；与账单页删除行为一致性断言。
- **R4**：新增 `updateCategory`（改名/图标/色）、`deleteCategory` 预置保护（isPreset=true 拒删/拒改名）、引用计数（`category.transactions.count`）、删除已引用分类按 D2 的归属行为、**同方向重名拒绝**（原型 §5 校验）；`PresetCategoryTests` 幂等保持。**自动归类到自定义分类**（PRD 验收 4）：`RecognitionNormalizer.category` 已按 name+direction 匹配全部库分类（含自定义），补一条"DeepSeek 返回自定义分类名 → 命中自定义分类"的用例即可，无需改归一逻辑；DeepSeek prompt 的"可选分类"清单（`categoryNames`）已由 `@Query` 全量分类喂入，加自定义分类后天然带上（见待确认 6）。
- **R5**：`MockTransactionParser` 扩展多笔返回；更新所有 `count==1` 为多笔断言；新增多笔 decode（对象数组）、多笔编排（循环落 N 笔 + 部分失败语义按 D5）、后台多笔通知 payload 用例。
- **R6**：纯视觉，无单测；靠真机/模拟器截图对照原型 §4 的 8 条硬锚点（A1 背景 #f6f3ee、A2 晨曦渐变、A3 珊瑚支出、A4 青绿收入、A5 圆角 22px、A6 彩色入口卡、A7 圆角卡列表、A8 字重 800）。
- 复用 v1 的 mock 注入范式（`TransactionParsing` 协议 + Mock），识别类改造保持可脱设备单测。

## 9. 不做什么

- 默认不改 `Transaction`/`Budget`/`BalanceBaseline`/`LedgerCategory` 持久字段；默认无 SwiftData 迁移。**唯一例外**：R2 若 D6 选方案 (b) 加 `Transaction.dateInferred`（用户拍板）。
- 不做多账户/多币种（剩余仍单一净值口径）；不做分类层级/子分类（R4 平级）。
- 不重写四 Tab 导航；不动 v1 已定的 DeepSeek/Vision/Speech 分工与后台链路形态（R5 只在其上扩多笔）。
- R6 不逐像素克隆、暗色模式默认不做（见待确认）。

## 待确认（评审时请拍板；标 ★ 者影响节点拆分/是否迁移）

1. **★ D4 R2/R5 是否合并为一个"识别改造"节点**（建议合并）。
2. **★ D5 R5 多笔覆盖范围**：仅截图 or 含文本识别？后台快捷指令是否多笔、通知怎么呈现"已记 N 笔"？部分笔失败的处理。
3. **★ D6 R2 日期标记范围与落地**：(a) 只结果卡当次高亮（不满足原型列表持久） / (b) 加 `Transaction.dateInferred` 字段（满足原型，需轻量迁移，建议） / (c) 派生启发式（零迁移、可能误判）；并连带定"识别不到日期：按今天填+高亮 vs 留空强制填"。**直接决定是否有迁移、R2 节点范围。**
4. **★ D7 R1 双重扣减提示文案**：初始总额录入处（Onboarding + 我的页）的提示口径，是 R1 节点交付项。
5. **D1 R3 最近记录结构选型**：改 `List`（建议，配合 R6）还是保持 `VStack` 长按触发。
6. **D2 R4 删除已引用分类归属**：转"其他"（建议，对齐原型）还是顺从 `.nullify` 变未分类。
7. **D3 R4 预置分类保护范围**：禁删禁改名（建议）；是否允许改预置的图标/颜色？
8. **R4 自动分类 prompt**：DeepSeek prompt 的"可选分类"清单现已由全量分类 `@Query` 喂入，加自定义分类后天然带上——确认即可（无需额外改识别逻辑）。
9. **R6 还原范围与暗色**：核心三页（记账/账单/我的）先行还是全部一次到位？暗色模式做不做？
