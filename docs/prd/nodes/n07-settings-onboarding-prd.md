# N07 设置/预算/Key/首次引导/权限收尾

> 本节点是 Aubade v1 开发 DAG 的**第八个、也是最后一个节点**（收尾节点），依赖 **N01 手动记账 + 账单列表/编辑**（已完成，设置/预算作用于账单与统计）。对应技术基线模块 **M8 设置 + M9 首次引导/权限收尾**。其余内容（Key 配置、通知开关、权限降级）与各 AI 节点（N03~N06）交叉，按 DAG 安排在最后统一补齐。
>
> 里程碑意义：**把散落在 N02~N06 各节点里的"配置项与异常提示"收进一个统一的「我的」页与一条首次引导流程**——N01~N06 已把四种记账入口和统计跑通，但很多配置至今**只有消费侧、没有正式设置入口**（预算只能靠 DEBUG 菜单硬编码写、超支阈值 80% 硬编码在聚合器里、通知无法关闭），且**首次启动直接落到空账本、没有任何引导**。本节点补齐这些"最后一公里"：**首次引导（录初始总额 → 提示配 Key 可跳过 → 落记账页）**、**我的页正式设置（预算周/月、Key 状态行、分类查看、通知开关、超支阈值）**、**权限被拒的统一降级提示**。做完后，App 从"能用"变成"配置完整、异常有交代"。
>
> 上游事实来源：全局 PRD `docs/prd/aubade-v1-prd.md`（辅助流程 E 统计与预算 `:61-64`、辅助流程 F 剩余金额 `:66-69`、应用设置数据 `:82`、业务规则 8 预算周期 `:102`、业务规则 9 超预算阈值 `:103`、业务规则 10 剩余金额 `:104`、业务规则 12 本地优先/Key 本机 `:106`、验收点 8 预算进度 `:117`、验收点 9 剩余金额 `:118`、验收点 11 未配 Key 提示手动可用 `:120`、后续澄清方向 2 超支阈值待确认 `:140`、后续澄清方向 3 分类可维护程度待确认 `:141`）、开发 DAG `docs/design/aubade-v1-dev-dag.md`（N07 小节 `:218-229`、验收点覆盖映射 8/11 `:244/:247`）。
> 代码事实来源：直接阅读 N00~N06 已落地源码（本仓库无 `.codegraph/` 索引，逐文件阅读，行号为本 PRD 写作时快照，可能有 ±1 漂移）。
>
> **本节点两项决策已由用户本轮拍板（非待确认项，TRD 直接据此落地）**：
> 1. **首次引导走两步（对齐 DAG，非原型的一步）**：`录初始总额（可跳过）→ 提示配置 DeepSeek Key（可跳过）→ 落到空账本记账页`。原型 demo `prototype/app/app.js:74-99 renderOnboard` 只画了"录初始总额"一步，DAG 节点范围 `:224/:226` 写的是含"提示配置 Key 可跳过"的两步——**用户拍板以 DAG 两步为准**，比原型多一个 Key 引导页（可跳过，跳过后仍落记账页、手动记账不受影响）。
> 2. **超支阈值做成用户可配置（默认 80%）**：全局 PRD 后续澄清方向 2 `:140` 与 DAG N07 详情 `:227` 都把"接近预算提示比例（默认 80%）是否可配"标为待确认——**用户拍板做成可配置**：我的页加"超支提示阈值"设置项（默认 80%），落配置存储，统计页 `StatisticsAggregator.budgetProgress`（现 `:121` 硬编码 `pct >= 80` 判 `.near`）改为读该配置。
>
> **N00~N06 复用锚点（本节点直接复用/扩展，不重造、不改既有签名）**：
> - **我的页骨架** `ProfilePlaceholderView`（`Aubade/Features/AppShell/RootTabView.swift:64-123`）：已是 `NavigationStack + List`，含 `balanceSection`（剩余总额展示 + 录入/调整初始总额按钮，`:105-122`）与 `#if DEBUG` 调试菜单入口（`:86-94`）。**N07 在这个 List 里追加预算/Key/分类/通知开关/阈值几个 Section，不新建页面。**
> - **初始总额设置 sheet 范式** `InitialBalanceSheet`（`RootTabView.swift:127-179`）：`Form + TextField(.decimalPad)` + posix locale 纯 `Decimal(string:)` 校验（`:136-142`，规避逗号小数分隔）+ toolbar 取消/保存 + `.disabled(parsedAmount == nil)`。**预算设置 sheet 照此范式做，金额一律走 Decimal、不经 Double。**
> - **初始总额/剩余读写（N02 交付）**：`LedgerStore.setBalanceBaseline(initialAmount:establishedAt:)`（`Store/LedgerStore.swift:104`，清空+插入唯一化）、`.currentBaseline()`（`:113`）；剩余计算 `BalanceCalculator.remaining(transactions:baseline:)`（`Features/Analytics/BalanceCalculator.swift:12`，无基线返回 nil）。**首次引导"录初始总额"直接调 `setBalanceBaseline`；我的页剩余展示已接，本节点不重做。**
> - **预算读写（N02 交付，仅消费+DEBUG 写）**：`LedgerStore.setBudget(...)`（`LedgerStore.swift:83`，按 `periodType` 唯一化）、`.createBudget(...)`（`:73`）；`Budget` 模型（`Models/Budget.swift:4`，`id/periodType:BudgetPeriodType/amount:Decimal`）；`BudgetPeriodType`（`Models/Enums.swift`，`weekly/monthly`）。N02 统计页 `AnalyticsTabView.currentBudget`（`Features/Analytics/AnalyticsTabView.swift:70`）消费、未设预算时按钮 `selection = .profile` 跳我的页（`:290-291`）。**正式"设置预算"入口至今只有 DEBUG 硬编码（`Debug/DebugMenuView.swift:70-75`）——N07 补正式设置入口，调既有 `setBudget`，零签名改动。**
> - **超支阈值消费点** `StatisticsAggregator.budgetProgress(spent:budget:)`（`StatisticsAggregator.swift:116`）：现 `:121` 硬编码 `pct >= 80 → .near`，`.near` 态橙色、`.over(>100%)` 红色已在 `AnalyticsTabView.budgetProgressView:312` 消费。**N07 把 80 改为读配置（默认 80），需给 `budgetProgress` 加阈值入参或读配置——此签名改动仅波及 N02 统计页调用点，需一并更新。**
> - **DeepSeek Key / Keychain（N03 交付最小实现）**：`KeychainStore.shared`（`Persistence/KeychainStore.swift`）—`deepSeekKey` 读（`:22`）、`setDeepSeekKey`（`:38`）、`clearDeepSeekKey`（`:48`）、`isConfigured`（`:54`，非空即已配置，不校验格式/联网）；填写 UI `KeySetupSheet`（`Features/Recognition/KeySetupSheet.swift`，SecureField+保存，**其头注释 `:4-5` 明写"完整『已配置✓/去填写』状态卡、我的页 Key 行、联网测活 → N07"**）。**N07 在我的页加 Key 状态行（已配置✓/去填写 ›），点击开既有 `KeySetupSheet`，不重造填写 UI。**
> - **未配 Key 拦截（N03 前台 / N06 后台，已收口，本节点不重做拦截逻辑）**：前台 `RecordTabView.swift:322/330`（截图·语音入口查 `isConfigured`）+ alert（`:271/:281`）+「去填写」开 `KeySetupSheet`；后台 `DeepSeekClient.swift:17` 抛 `.noKey`、`UNUserNotificationCenterNotifier.swift:58 missingKey` 通知 + `AppDelegate.swift:58 .configureKey` 深链落 `KeySetupSheet`。**验收点 11 的"未配 Key 提示"前后台均已实现——N07 的收口 = 我的页给出可视 Key 状态与统一入口，不改既有前后台拦截行为。**
> - **深链路由（N06 交付）** `DeepLinkRouter` + `DeepLinkIntent`（`App/AppDelegate.swift` / `RootTabView.swift:17-20/:41-56` 消费）：通知点击 → `AppDelegate` 写 `router.pending` → `RootTabView` 切 Tab 下传。`.configureKey` 深链已存在。**若首次引导/我的页需跳 Key 配置，复用既有深链/`KeySetupSheet`，不新造路由。**
> - **通知（N06 交付，有申请+delegate，无开关）** `UNUserNotificationCenterNotifier`（`Features/Recognition/Shortcut/UNUserNotificationCenterNotifier.swift`）：首次发通知时惰性 `requestAuthorization([.alert,.sound])`（`:27`），被拒静默不发不崩；delegate 挂载/点击路由/前台展示在 `AppDelegate.swift:27/:32/:41`。**无"通知开关"、无 `notificationsEnabled` 配置、无跳系统设置——N07 新增通知开关（关闭后后台入账不发通知，入账本身不受影响）。**
> - **权限现状（各写各的，N07 统一降级文案）**：麦克风+语音识别（N04）`SpeechVoiceTranscriber.swift:142/153` 首次 start() 内申请、被拒抛 `.speechDenied/.microphoneDenied`、降级文案 `VoiceCaptureView.swift:232 failedMessage`（纯文本无跳设置按钮）；相册（N05）走 `PhotosPicker` **免授权**（`ScreenshotIntakeSheet.swift:34`，无权限申请/降级、pbxproj 无相册 Usage 串）；通知（N06）被拒静默。权限串仅 pbxproj `Aubade.xcodeproj/project.pbxproj:332-333`（麦克风+语音，走 `GENERATE_INFOPLIST_FILE`，无独立 Info.plist）。
> - **预置分类（N00 交付，仅写侧+DEBUG 只读清单）** `PresetCategories`（`Persistence/PresetCategories.swift`，衣食住行玩其他+工作/其他收入，幂等装载）；`LedgerCategory` 模型（`Models/LedgerCategory.swift:7`，`isPreset/sortOrder`，反向关系 `transactions`）；`LedgerStore.createCategory`（`:27`，写侧已有）。**无分类管理/查看 UI（DEBUG 菜单 `:49` 有只读清单）——N07 补我的页只读查看（原型 `app.js:691-697` 也是只读标签展示）。**
> - **根路由 / 启动** `AubadeApp.swift:12 → ContentView.swift:8 → RootTabView()`；启动 `.task`（`AubadeApp.swift:15`）现做预置分类装载 + 清临时图。**默认落 `.record` 记账 Tab（`RootTabView.swift:16`）。首次引导标志读取挂 `ContentView`/`AubadeApp` 根分流。**
> - **配置存储现状**：**生产零 UserDefaults/AppStorage**（Key 走 Keychain、明确不进 UserDefaults）；仅 3 个 DEBUG mock key 集中在 `DebugMenuView.swift:7/13/19`。**N07 新增的生产配置（onboarding 完成标志、通知开关、超支阈值）需首次引入 UserDefaults/AppStorage，建议集中管理。**

## 给用户看的摘要

做完这个节点，你的记账 App 迎来**收尾的一公里**——把之前散在各处、还缺正式入口的配置和异常提示，收进一个清爽的「我的」页和一条首次引导：

1. **第一次打开有引导**：全新安装第一次进 App，会先请你**录一个初始总额**（现在所有账户加起来大约多少钱，作为剩余金额的起点，可以先跳过），再**提示你填一下 DeepSeek Key**（识别记账要用，也可以先跳过、之后在「我的」里补），然后落到空账本的记账页——不再是一进来就对着空白发愣。
2. **「我的」页能设的都能设了**：
   - **剩余总额**：看当前还剩多少、随时调整初始总额（这块 N02 已做好，本节点沿用）。
   - **周/月预算**：直接在这里设，设完统计页的进度条和超支提示立刻生效（以前只能靠开发者菜单硬塞）。
   - **超支提示的松紧**：默认花到预算的 **80%** 就提醒你"接近了"，你也可以调这个比例。
   - **DeepSeek Key**：一眼看到"已配置 ✓"还是"去填写 ›"，点进去填/改（填写界面 N03 已做好，本节点接上状态显示）。
   - **分类一览**：看一眼系统预置的分类（衣食住行玩其他 / 工作 / 其他收入）。
   - **通知开关**：不想要截图后台入账的通知了，一键关掉——关掉只是不弹通知，账照记。
3. **权限被拒不再各说各话**：麦克风、语音、通知这些权限如果你拒了，App 给的降级提示**统一成一致的说法**——告诉你哪个功能受影响、去哪开、以及**手动记账永远不受影响**，不会因为拒了权限就卡死。

**这一节点不做什么**（都在别处或 v1 不做）：四种记账入口本身（N01~N06 已做）、统计的计算与图表（N02 已做）、Key 的填写界面与前后台拦截逻辑（N03/N06 已做，本节点只接状态显示）、截图后台链路（N06 已做）；**不做分类的增删改**（本节点只做只读查看，增删改是 v1 后续澄清项，见"不做什么"）、不做 Key 的联网测活、不做云同步/账号。

## 目标

1. **首次引导两步流程（M9 净新增，用户拍板对齐 DAG）**：全新安装首次启动进引导——**① 录初始总额页**（可输入并调 `LedgerStore.setBalanceBaseline` 落库，也可"先跳过"）→ **② 提示配置 DeepSeek Key 页**（可开 `KeySetupSheet` 填写，也可"先跳过"）→ **落到空账本的记账 Tab（`.record`）**。引导只在**未完成引导**时出现，完成后写入"已引导"标志、之后启动直达主框架。跳过任一步都不阻塞、手动记账不受影响（对齐原型 `renderOnboard:89-98` 的"开始记账/先跳过"双按钮语义，但按 DAG 多一个 Key 提示步）。
2. **我的页预算设置入口（M8 净新增，接既有 `setBudget`）**：在 `ProfilePlaceholderView` 的 List 增"预算设置"Section——周预算、月预算两项，可填/改/清空，保存调既有 `LedgerStore.setBudget(periodType:amount:)`（按 periodType 唯一化）。设完统计页 `AnalyticsTabView` 的 `currentBudget` 消费即时生效（验收点 8 的设置侧；N02 已实现进度/超支展示）。金额走 `InitialBalanceSheet` 同款 Decimal 校验范式。
3. **超支阈值可配置（M8 净新增，用户拍板）**：我的页增"超支提示阈值"设置项（默认 **80%**，合理范围如 50%~100%，具体范围/步进留 TRD），落配置存储（UserDefaults/AppStorage）；`StatisticsAggregator.budgetProgress` 现 `:121` 硬编码 `pct >= 80` 改为读该配置判定 `.near`（阈值入参化或读配置，签名调整同步更新 N02 唯一调用点 `AnalyticsTabView.budgetProgressView`）。默认值与现状一致，保证不配置时行为不变。
4. **我的页 DeepSeek Key 状态行（M8 净新增，接既有 `KeySetupSheet`）**：在 List 增"智能识别"Section 的 Key 行——依 `KeychainStore.isConfigured` 显示**「已配置 ✓」/「去填写 ›」**（对齐原型 `renderMine:682-689`），点击开既有 `KeySetupSheet`（N03 已做填写/保存 UI，本节点不重造）。Key 保存/清空后状态行即时刷新。
5. **我的页分类只读查看（M8 净新增，仅查看）**：在 List 增"分类（预置）"Section，只读展示预置分类标签（衣食住行玩其他 + 工作/其他收入，对齐原型 `renderMine:691-697` 的 `cat-tags` 只读标签），数据源 `LedgerCategory`（`isPreset` + `sortOrder` 排序）。**只读，不做增删改**（见"不做什么"）。
6. **通知开关（M9 净新增，UserDefaults）**：我的页增"通知开关"（截图后台入账结果通知的总开关，默认开），落配置存储；关闭后 `UNUserNotificationCenterNotifier` 发通知前先查开关、关则不发（**入账本身不受影响，只是不弹通知**）；若系统级通知权限被拒，我的页开关旁给出"去系统设置开启"引导（是否加 `UIApplication.openSettingsURLString` 跳转留 TRD）。
7. **权限被拒统一降级提示（M9 净新增，统一文案/组件）**：把现在各写各的降级提示（语音 `VoiceCaptureView:232` 纯文本、通知静默、相册无）**统一成一致的降级提示范式**——被拒时明确告知"哪个功能受影响 + 去哪开（可跳系统设置）+ 手动记账不受影响"。统一的是**文案与呈现**（一个可复用的降级提示组件/文案源），不改各权限**已有的申请时机**（语音仍首次 start 内申请、通知仍首次发通知时申请）。相册走 PhotosPicker 免授权、**无权限降级需求**（现状事实，不为它硬造降级）。
8. **新增生产配置集中管理（可维护性）**：本节点首次引入生产 UserDefaults/AppStorage（onboarding 完成标志、通知开关、超支阈值）——集中定义（如一个配置 store/枚举 key），避免散落（对齐 DEBUG mock key 集中在 `DebugMenuView.swift:7/13/19` 的现状范式）。

## 当前理解

> N00~N06 已交付、本节点直接复用/扩展的能力（我的页 `ProfilePlaceholderView` 骨架、`InitialBalanceSheet` 校验范式、`setBalanceBaseline`/`setBudget`/`KeychainStore`/`KeySetupSheet`/`UNUserNotificationCenterNotifier`/`StatisticsAggregator.budgetProgress`/`PresetCategories`/根路由与默认 Tab 等）**已在开头"复用锚点"引文块逐条列出文件:行号与"已实现 vs 待做"判断，此处不重复**；本小节只补锚点未覆盖的两点：净新增能力确认为零、可测性。

### 净新增能力在项目中确认为零（本 PRD 写作时逐文件核实）

- **首次引导 / onboarding / `hasOnboarded` 标志**：全仓零命中（仅 `BalanceCalculator` 注释提过"引导用户先录初始总额"一词）——引导流程、完成标志均本节点首次引入。
- **正式预算设置入口 / 超支阈值配置 / 通知开关 / 我的页 Key 状态行 / 分类查看 UI / 生产 UserDefaults / 统一权限降级组件**：均未实现，本节点新增（复用的是各自的读写/申请能力与既有 sheet 范式，不是现成的设置 UI）。

### 可测性（对齐技术基线 §10、N02~N06 范式）

- 测试框架 **XCTest**（`AubadeTests/` 平铺），已有 `StatisticsAggregator`/预算进度、`RecognitionEntry*` 等测试。
- **超支阈值可配置**：`budgetProgress` 加阈值入参后，补单测——阈值=80 时 79%→normal/80%→near/101%→over；阈值=50 时 50%→near（验证阈值真的驱动 `.near` 判定），金额 Decimal 无浮点误差。
- **预算设置落库**：mock/in-memory 容器下设周/月预算调 `setBudget`，断言唯一化（同 periodType 覆盖不新增第二条）、金额 Decimal 无误差、统计页 `currentBudget` 读到新值。
- **通知开关 gating**：注入通知发送器 + 开关配置，断言"开关关时不发通知、开时发"（复用 N06 可注入通知发送器范式）。
- **onboarding 标志分流**：标志未置位 → 根视图进引导；置位 → 直达 `RootTabView`（可注入配置或 in-memory 断言分流选择）。

## 涉及的现有链路

- **被扩展/接线**：
  - `ProfilePlaceholderView`（`RootTabView.swift:64-123`）→ List 追加预算/Key 状态/分类查看/通知开关/超支阈值 Section（复用其 `@Query`、`store`、sheet 范式）。
  - `StatisticsAggregator.budgetProgress`（`:116-121`）→ 80% 硬编码改为读配置/入参；**其唯一消费点 `AnalyticsTabView.budgetProgressView`（`:309-312`）同步更新**。
  - `ContentView`（`ContentView.swift:6-10`）/ `AubadeApp`（`:12-19`）→ 按 onboarding 完成标志分流：未完成进引导、完成进 `RootTabView`（分流点归属留 TRD）。
  - `UNUserNotificationCenterNotifier`（`:27` 发通知路径）→ 发通知前查通知开关配置（关则不发，入账不受影响）。
  - `DebugMenuView`（DEBUG，`:70-75` 硬编码预算 / `:49` 分类只读清单）→ 正式设置入口落地后，DEBUG 硬编码可保留/精简（留 TRD，不删既有调试能力）。
  - `Info.plist` 生成配置（pbxproj `INFOPLIST_KEY_*`，现 `:332-333` 麦克风+语音）→ 若统一降级"去系统设置"或分类/通知需新增用途串，照 N04/N05 `GENERATE_INFOPLIST_FILE` 方式落地（相册免授权，除非改用需授权 API，否则不必加相册串；具体键留 TRD）。
- **被复用（只读消费/接线，不改签名）**：
  - `LedgerStore.setBalanceBaseline`（首次引导录初始总额）、`setBudget`（预算设置）、`currentBaseline`。
  - `BalanceCalculator.remaining`（我的页剩余展示，已接）。
  - `KeychainStore.isConfigured/deepSeekKey`（Key 状态行判定）、`KeySetupSheet`（点击填写）。
  - `LedgerCategory` + `PresetCategories`（分类只读查看数据源）。
  - `DeepLinkRouter`/`DeepLinkIntent`（若引导/我的页跳 Key 配置复用既有深链）。
  - `UNUserNotificationCenterNotifier`（通知开关 gating 挂在发送前）。
  - `Budget`/`BudgetPeriodType`/`InitialBalanceSheet` 校验范式。
- **本节点新增**：
  - **首次引导流程**（两步：初始总额 → Key 提示 → 落记账页）+ onboarding 完成标志。
  - **我的页设置 Section**（预算设置 sheet、Key 状态行、分类只读查看、通知开关、超支阈值设置）。
  - **超支阈值配置**（存储 + `budgetProgress` 读取 + 我的页设置项）。
  - **通知开关配置**（存储 + 发送前 gating + 我的页开关）。
  - **统一权限降级提示**（可复用文案/组件，覆盖语音/麦克风/通知；相册免授权不涉及）。
  - **生产配置集中管理**（onboarding 标志/通知开关/超支阈值的 UserDefaults key 集中定义）。
- **既有调用方冲突点（需一并更新，不可漏）**：
  - **`StatisticsAggregator.budgetProgress` 若改签名（加阈值入参）**：唯一调用点 `AnalyticsTabView.budgetProgressView:310` 必须同步传参，否则统计页编译失败——这是本节点唯一有签名波及的既有链路，TRD 需显式覆盖。
  - 其余（预算设置、Key 状态行、分类查看、通知开关、引导）均为新增 UI 消费既有读写能力，**不改 `LedgerStore`/`KeychainStore`/`Budget`/`LedgerCategory`/通知发送器的既有签名**；通知开关 gating 是在发送器内部加一次配置读取，不改其对外接口（具体留 TRD）。

## 需求范围

### 1. 首次引导两步流程（M9，用户拍板对齐 DAG）
- 全新安装、**onboarding 完成标志未置位**时，根视图进引导（分流挂 `ContentView`/`AubadeApp`，具体归属留 TRD）：
  1. **录初始总额页**：数字输入（`.decimalPad` + posix Decimal 校验，复用 `InitialBalanceSheet` 同款范式），「开始记账/下一步」→ 有值调 `LedgerStore.setBalanceBaseline` 落库；**「先跳过」**→ 不落基线（剩余总额此后显示"未设置"，可后续在我的页补，对齐 `BalanceCalculator` nil 语义与原型 `:97` skip 分支）。
  2. **提示配置 DeepSeek Key 页**：说明"识别记账要用 Key、手动不受影响"，「去填写」开既有 `KeySetupSheet`、**「先跳过」**→ 不填（此后识别类入口仍走 N03/N06 既有未配 Key 拦截，手动可用）。
  3. 两步走完（无论是否跳过）→ **置 onboarding 完成标志 → 落到记账 Tab（`.record`）**；之后启动直达 `RootTabView`、不再进引导。
- 引导页视觉基调对齐原型 `renderOnboard`（logo/标题/说明/输入/主按钮/ghost 跳过按钮），但 SwiftUI 原生实现、非照搬 HTML；确切文案/步进指示（1/2）/能否回退留 TRD。

### 2. 我的页预算设置（M8，接既有 `setBudget`）
- `ProfilePlaceholderView` List 增"预算设置"Section：**周预算、月预算**两项，展示当前值（`AnalyticsTabView.currentBudget` 同源 `@Query budgets`）、点击开设置 sheet（`InitialBalanceSheet` 同款 Decimal 校验范式）。
- 保存调既有 `LedgerStore.setBudget(periodType: .weekly/.monthly, amount:)`（按 periodType 唯一化，`:83`）；支持清空（金额 0 或删除该 Budget，语义留 TRD）。
- 设完统计页周/月档进度即时生效（验收点 8 设置侧；N02 已实现进度条与超支展示，本节点不重做展示）。

### 3. 超支提示阈值可配置（M8，用户拍板）
- 我的页增"超支提示阈值"设置项，**默认 80%**（合理范围/步进/呈现形态——slider/stepper/输入——留 TRD）；落配置存储（UserDefaults/AppStorage，集中管理）。
- `StatisticsAggregator.budgetProgress`（`:116`）把 `:121` 的 `pct >= 80` 改为 `pct >= 配置阈值` 判 `.near`（阈值入参化或函数内读配置，二选一留 TRD）；**同步更新唯一调用点 `AnalyticsTabView.budgetProgressView:310`**。
- 默认 80% 与现状完全一致——不配置时统计页超支/接近表现不变（回归安全）。

### 4. 我的页 DeepSeek Key 状态行（M8，接既有 `KeySetupSheet`）
- List "智能识别"Section 的 Key 行：读 `KeychainStore.isConfigured` → 显示**「已配置 ✓」/「去填写 ›」**（对齐原型 `:684-687`）；点击开既有 `KeySetupSheet`（N03 填写/保存 UI，不重造）。
- Key 保存/清空后（`KeySetupSheet` 内已调 `setDeepSeekKey/clearDeepSeekKey`）状态行即时刷新（`@State`/`@Query`/视图刷新机制留 TRD）。
- **不做联网测活**（`isConfigured` 只判非空，见"不做什么"，对齐 `KeychainStore:54` 现状）。

### 5. 我的页分类只读查看（M8，仅查看）
- List "分类（预置）"Section：只读展示预置分类（`LedgerCategory`，按 `direction` 分支出/收入、`sortOrder` 排序，对齐原型 `:691-697` 只读标签）。
- **仅查看，不提供增删改**（增删改是 v1 后续澄清方向 3 `:141`，本节点不做，见"不做什么"）。

### 6. 通知开关（M9，UserDefaults）
- 我的页增"通知开关"（截图后台入账结果通知总开关，**默认开**），落配置存储（集中管理）。
- `UNUserNotificationCenterNotifier` 发通知前查开关（`:27` 发送路径内加一次配置读取）：**关则不发通知、但后台入账链路照常完成落库**（关的是通知、不是记账）。
- 若系统级通知权限被拒（`requestAuthorization` 返回拒绝），我的页开关旁给"通知权限被拒，去系统设置开启"引导（是否 `openSettingsURLString` 跳转留 TRD）。

### 7. 权限被拒统一降级提示（M9，统一文案/组件）
- 提供**统一的权限降级提示范式**（可复用组件/文案源），覆盖：**麦克风+语音识别**（N04）、**通知**（N06）；统一要素 = "哪个功能受影响 + 去系统设置开启的入口 + 手动记账永远不受影响"。
- **不改各权限已有申请时机**（语音仍 `SpeechVoiceTranscriber` 首次 start 内申请、通知仍首次发通知时申请）——统一的是**被拒后的呈现**（把 `VoiceCaptureView:232` 的纯文本降级、通知的静默降级，收敛到一致文案/组件）。
- **相册（N05）走 PhotosPicker 免授权、无降级需求**——不为其硬造权限降级（现状事实）。
- 是否需要在我的页集中展示各权限状态（已授权/被拒）留 TRD；核心是"被拒时提示一致、不卡死、手动可用"。

### 8. 生产配置集中管理（可维护性）
- 本节点首次引入的生产配置——**onboarding 完成标志、通知开关、超支阈值**——集中定义 key（一个配置 store/枚举，对齐 `DebugMenuView` DEBUG key 集中范式），避免散落到各视图。
- Key（DeepSeek）**仍走 Keychain、不进 UserDefaults**（对齐全局 PRD 业务规则 12 与 `KeychainStore` 现状）。

### 9. 单元测试（对齐技术基线 §10、N02~N06 范式）
- **超支阈值驱动**：`budgetProgress` 阈值=80→79%normal/80%near/101%over；阈值=50→50%near；断言 `.near` 判定随配置变化、Decimal 无浮点误差。
- **预算设置落库**：设周/月预算调 `setBudget`，断言 periodType 唯一化（覆盖不新增）、金额 Decimal 无误差、`currentBudget` 读到新值。
- **通知开关 gating**：注入通知发送器 + 开关，断言开关关→不发、开→发（复用 N06 可注入通知发送器）。
- **onboarding 分流**：标志未置位→进引导、置位→直达主框架。
- **不回归**：N02 预算进度/超支展示（默认阈值 80 行为不变）、N03/N06 未配 Key 拦截、N01 手动记账、既有 `setBudget/setBalanceBaseline` 行为不受影响。

## 不做什么

以下均属其他节点、v1 不做、或已在别处，本节点**不实现**：
- **四种记账入口本身**（N01 手动 / N03 文本 / N04 语音 / N05 相册 / N06 快捷指令后台）：全部已完成，本节点不碰入口链路，只补它们共用的配置与降级提示。
- **Key 的填写界面与前后台拦截逻辑**（N03/N06 已做）：本节点只加"我的页 Key 状态行 + 点击开既有 `KeySetupSheet`"，不重造填写 UI、不改 `RecordTabView`/`DeepSeekClient`/通知的未配 Key 拦截行为。
- **Key 联网测活 / 格式校验**：`isConfigured` 只判非空（`KeychainStore:54` 现状），本节点不加"填的 Key 是否真能用"的联网验证。
- **分类增删改**：本节点只做**只读查看**；分类的增删改是全局 PRD 后续澄清方向 3 `:141` 的待确认项，v1 暂不做（`PresetCategories` 幂等装载已为"日后可删预置分类"留了语义空间，但本节点不建增删改 UI）。
- **统计的计算/图表/剩余金额计算**（N02 已做）：本节点只加"预算设置入口"与"超支阈值配置"，不重做统计聚合、趋势图、分类占比、剩余金额计算与展示。
- **改各权限的申请时机 / 新增权限**：统一的是被拒后降级文案的一致性，不改语音/通知既有申请时机；不为免授权的相册硬造权限申请与降级。
- **通知的构造/点击路由/后台链路**（N06 已做）：本节点只加"通知开关"（发送前 gating）与"权限被拒统一提示"，不改通知内容、深链路由、后台入账链路。
- **App Group / 独立扩展进程 / 数据迁移**（N06 已定 in-app 路线）：不碰存储架构。
- **云同步 / 账号体系 / 数据导出 / 预算跨周期结转**（v1 不包含，全局 PRD `:124-135`；结转是后续澄清方向 1 `:139`）。
- 不改 N00~N06 的模型字段、`LedgerStore`（除调用既有 `setBudget/setBalanceBaseline`）、`KeychainStore`、通知发送器对外签名与既有行为；**唯一的既有签名改动是 `StatisticsAggregator.budgetProgress` 加阈值入参**（连带更新其唯一调用点），此外不动既有链路。

## 验收标准

（对齐 DAG N07"退出标准（可观察）"`:228` 与全局 PRD 验收点 8/9/11。完成门禁 = 可编译 + 可观察行为达成 + 单测覆盖阈值/预算/开关/分流，延续 N03~N06 约定。）

1. **首次引导两步（DAG 退出标准 + 用户拍板）**：全新安装（onboarding 标志未置位）首次启动 → 进"录初始总额"页，输入一个数并「开始记账/下一步」→ 进"提示配置 Key"页 →（填或「先跳过」）→ 落到**空账本的记账 Tab**；重启 App 不再进引导，直达主框架。录了初始总额的，我的页/账单页剩余总额随即显示该值（对齐验收点 9）；两步都跳过的，剩余显示"未设置"、手动记账可用、识别类走既有未配 Key 拦截。
2. **我的页设周/月预算即时生效（验收点 8 设置侧）**：我的页"预算设置"填周预算/月预算并保存 → 统计页对应周/月档立即显示进度条与"已用/剩余"；再次设置同周期覆盖旧值（不产生第二条 Budget）。
3. **超支阈值可配置且驱动接近提示（用户拍板 + 验收点 8）**：我的页调"超支提示阈值"（如从 80% 调到 50%）→ 统计页当支出达到该比例即进入"接近"（橙色）态、超 100% 标红；阈值保持默认 80% 时表现与调整前一致（回归）。
4. **我的页 Key 状态正确、可填可改（验收点 11 收口）**：未配 Key 时 Key 行显示「去填写 ›」、点击开 `KeySetupSheet` 填写并保存后变「已配置 ✓」；清空后回到「去填写 ›」。全程手动记账不受影响；识别类入口的未配 Key 拦截（N03/N06）行为不变。
5. **分类只读查看**：我的页"分类（预置）"Section 展示衣食住行玩其他 + 工作/其他收入（按方向分组、sortOrder 排序），只读、无增删改入口。
6. **通知开关可关且不误伤入账**：我的页关闭通知开关 → 触发截图后台入账（N06「演示」或真机）时**不弹通知、但账单照常入账**（账单出现在列表/统计）；重新打开 → 恢复弹通知。系统级通知权限被拒时，开关旁有"去系统设置"引导。
7. **权限被拒降级一致、手动可用（验收点 11 精神）**：拒绝麦克风/语音/通知权限时，各自给出**一致范式**的降级提示（说明受影响功能 + 去系统设置入口 + 手动记账不受影响），App 不崩溃、不卡死；相册走免授权选图不受影响。
8. **配置持久**：初始总额、周/月预算、超支阈值、通知开关、onboarding 完成标志跨 App 重启保持（Key 在 Keychain、其余在 UserDefaults）。
9. **单测覆盖**：`budgetProgress` 阈值驱动（80/50 两组，normal/near/over 边界，Decimal 无误差）；`setBudget` 唯一化落库；通知开关 gating（开/关发不发）；onboarding 标志分流；N02 默认阈值不回归、N03/N06 未配 Key 拦截不回归。
10. **不越界**：不做记账入口本身、不重造 Key 填写/拦截、不做 Key 测活、不做分类增删改、不重做统计计算/图表、不改权限申请时机、不碰通知内容/路由/后台链路、不动存储架构；除 `budgetProgress` 加阈值入参（连带更新 `AnalyticsTabView` 唯一调用点）外不改既有签名。

## 已确认约定

（以下由上游 PRD/DAG 定死、由 N00~N06 既有实现约束、或由用户本轮拍板，作为既定实现约束，非待确认项。TRD 直接据此落地。）

1. **首次引导两步（用户本轮拍板，对齐 DAG）**：`录初始总额（可跳过）→ 提示配置 Key（可跳过）→ 落记账页`；比原型 `renderOnboard` 的一步多一个 Key 提示步（DAG `:224/:226`）。跳过不阻塞、手动记账不受影响。
2. **超支阈值可配置、默认 80%（用户本轮拍板）**：解掉全局 PRD 后续澄清方向 2 `:140` 与 DAG `:227` 的待确认；`StatisticsAggregator.budgetProgress:121` 硬编码 80 改为读配置，默认 80 与现状一致。
3. **分类只做只读查看、不做增删改**（DAG N07 前端范围 `:224`"分类管理查看"、全局 PRD 后续澄清方向 3 `:141` 增删改待确认）：本节点只读展示，增删改留后续。
4. **Key 只走 Keychain、判定只看非空**（全局 PRD 业务规则 12 `:106`、`KeychainStore:54` `isConfigured` 现状）：我的页状态行读 `isConfigured`，不联网测活、不进 UserDefaults；填写复用既有 `KeySetupSheet`。
5. **预算设置调既有 `setBudget`、按 periodType 唯一化**（`LedgerStore:83` 现状）：本节点只加设置入口 UI，不改预算读写与统计消费逻辑；周自然周、月自然月口径沿用 N02（全局 PRD 业务规则 8 `:102`）。
6. **通知开关关闭只停通知、不停入账**（全局 PRD 业务规则 5 `:96`"通知可在设置里关闭"）：gating 加在 `UNUserNotificationCenterNotifier` 发送前，后台入账链路（N06）照常落库。
7. **权限统一的是被拒降级文案、不改申请时机**（DAG N07 范围 `:227`"各权限被拒的统一降级提示"）：语音/通知既有申请时机不动；相册免授权无降级；统一"受影响功能 + 去设置 + 手动不受影响"文案范式。
8. **首次引导标志 / 通知开关 / 超支阈值 = 本节点首次引入的生产 UserDefaults，集中管理**（生产现零 UserDefaults 的事实）：集中定义 key，避免散落。
9. **我的页 = 扩展既有 `ProfilePlaceholderView` List、不新建页面**（`RootTabView.swift:64` 现状 + 注释 `:61`"完整设置 → N07"）：追加 Section，复用其 `@Query`/`store`/sheet 范式与 `InitialBalanceSheet` Decimal 校验。
10. **唯一既有签名改动 = `budgetProgress` 加阈值入参**，连带同步 `AnalyticsTabView.budgetProgressView:310` 唯一调用点；其余全为新增 UI 消费既有能力，不改 `LedgerStore`/`KeychainStore`/`Budget`/`LedgerCategory`/通知发送器对外签名。
11. **完成门禁延续 N03~N06 约定**（可编译 + 可观察行为达成 + 单测覆盖）：无独立真机专项（本节点无 N06 那类后台真机风险；截图后台入账的真机验证仍属 N06）。
12. **Info.plist 权限串照 `GENERATE_INFOPLIST_FILE` / `INFOPLIST_KEY_*` 方式**（pbxproj `:332-333` 现状）：若统一降级需跳系统设置或新增用途串，以 build setting 落地；相册免授权不必加相册串（除非改用需授权 API，本节点不改）。
