# N00 工程地基 + 数据层

> 本节点是 Aubade v1 开发 DAG 的第一个节点（无依赖），对应技术基线模块 **M1 数据层（Persistence Core）**。它不产出任何用户可见界面，只搭建 Xcode 工程骨架与 SwiftData 数据底座，供后续 N01~N07 所有节点复用。
>
> 上游事实来源：全局 PRD `docs/prd/aubade-v1-prd.md`、技术基线 `docs/design/aubade-v1-technical-baseline.md`（重点 §3 决策 / §4-M1 / §7.4 隐私 / §8 数据与状态设计 / §11 待展开问题）、开发 DAG `docs/design/aubade-v1-dev-dag.md`（N00 小节）。

## 给用户看的摘要

这一节点是整个 App 的"地基"，做完之后**你还看不到任何记账界面**——它交付的是三样看不见但后面全靠它的东西：

1. **一个能在你 iPhone（iOS 17+）上编译运行的空 Xcode 工程**（SwiftUI，纯本地，无任何三方依赖）。
2. **四张本地数据表**：账单（Transaction）、分类（Category）、预算（Budget）、余额基线（BalanceBaseline）——就是 PRD 里"需要维护的数据"。金额一律用精确的 `Decimal`，不会有小数误差。
3. **首次打开自动写入 8 个预置分类**：支出 衣/食/住/行/玩/其他，收入 工作/其他收入；并且这四张表都能增、删、改、查（先用一个临时调试入口或单元测试验证，不做正式界面）。

**需要你在评审时拍一个板**：截图记账的后台入账走哪条技术路线，会影响这一步"建库要不要开 App Group 共享容器"。我的推荐是走 **in-app App Intents（App 进程内后台执行）**，这样本节点**不需要** App Group、代码最简；但我会把数据库读写封装成"日后若要改成独立扩展进程也只改一处"的形态，降低返工。**要说清一点**：这层封装消除的是"代码要改很多处"的扩散风险；如果到 N06 真机验证时被迫改走 App Group，而那时你已经记了不少真实账单，仍需要**一次把已有数据文件从旧目录搬到共享目录**的迁移动作（这步封装省不掉）。若你想彻底免掉这次搬迁，也可以现在就选备选方案（一开始就把库建在 App Group 目录），代价是提前引入配置负担。详见"需要你确认的关键决策"。做完这节点，下一步就是 N01 手动记账，那时你就有第一个能日常用的版本了。

## 目标

1. 建立 Aubade 的 Xcode 工程骨架：iOS 17+ 部署目标、SwiftUI App 生命周期、纯本地、零三方依赖（技术基线 §3）。
2. 落地技术基线 §8 定义的四个 SwiftData `@Model`：`Transaction`、`Category`、`Budget`、`BalanceBaseline`，金额字段一律 `Decimal`。
3. 初始化并共享一个 `ModelContainer`，为后续所有 ViewModel/Store 提供统一的持久化入口。
4. 首次启动幂等装载 8 个预置分类（衣/食/住/行/玩/其他 + 工作/其他收入），重复启动不重复写入。
5. 提供一层薄的基础读写封装（查询/增删改），供 N01+ 的 ViewModel 调用；本节点用临时调试入口或单元测试证明四模型 CRUD 与预置装载可用。
6. 在本节点**尽量前移**确定"截图后台入账是否需要 App Group 共享容器"的建库路线（技术基线 §11 第 1 条），避免后期存储迁移返工。

## 当前理解

- **这是一个从 0 到 1 的全新工程**：当前仓库除 `docs/`、`prototype/`、`.claude/` 外**没有任何 Swift / Xcode 代码**（已 `find` 确认无 `*.swift` / `*.xcodeproj` / `Package.swift`）。因此本 PRD 的"代码事实"锚定到技术基线的设计定义，而非现有代码行号；后续 TRD 落地后才产生真实文件路径。
- **数据模型的权威定义在技术基线 §8**，逐字段如下（本节点须实现，可空性/关系/类型细节留待 TRD）：
  - `Transaction`：`id`、`amount: Decimal`（正值，方向单独表达）、`direction: expense|income`、`occurredAt`（识别不到时取当前时间）、`category`（关系→Category）、`merchant?`、`note?`、`cardTail?`（仅记录）、`source: screenshotShortcut|screenshotAlbum|voice|sms/text|manual`、`rawText?`、`imageRef?`（截图临时引用）、`createdAt`/`updatedAt`。
  - `Category`：`id`、`name`、`direction`、`icon?`/`color?`、`isPreset`、`sortOrder`。
  - `Budget`：`id`、`periodType: weekly|monthly`、`amount: Decimal`（周/月各一条，可同时存在）。
  - `BalanceBaseline`：`id`、`initialAmount: Decimal`、`establishedAt`。剩余金额是**派生值、不存储**（= initialAmount + Σ基线后收入 − Σ基线后支出）。
- **金额精度**：技术基线 §3、§8 明确金额一律 `Decimal`，避免浮点误差——这是本节点最硬的实现约束。
- **预置分类**（技术基线 §8 Category / 全局 PRD 业务规则 7）：支出 衣、食、住、行、玩、其他；收入 工作、其他收入，共 8 条，`isPreset=true`。归类兜底约定（医疗/话费/数码→其他；红包/退款/转账→其他收入）属于 N03 解析层的匹配逻辑，**本节点只负责把 8 条预置分类写进库**。
- **非实体状态不进 SwiftData**（技术基线 §8 非实体状态、§7.4）：DeepSeek Key → Keychain；通知开关/预算周期规则/超支阈值(默认80%) → UserDefaults。本节点**不实现** Keychain / UserDefaults 封装，只在建模时确保这些状态**不被误放进数据库**。
- **App Group 与建库时机的耦合**（技术基线 §11 第 1 条，本节点关键决策）：截图主入口已确认走"App Intents 后台全流程入账"（§3）。若采用 **in-app App Intents**（Intent 在主 App 进程内后台执行 `perform()`），主 App 与后台 Intent 天然共享同一 `ModelContainer`，**无需 App Group**；若未来改走**独立扩展进程**（单独 App Extension target），则需要 App Group + 共享容器，且**建库时就得按共享容器建**否则后期迁移返工。此判定基线要求尽量前移到本节点，见下。

## 涉及的现有链路

- **无既有代码链路可复用或改动**：本节点是工程的第一行代码，不存在调用方/被调方。CodeGraph 无 `.codegraph/` 索引（全新项目，符合预期），代码事实来自对技术基线的手动阅读，非索引检索。
- **下游依赖本节点的节点**（本节点是它们的前置地基，需保证接口稳定）：
  - **N01 手动记账 + 账单列表/编辑**：直接依赖 `Transaction`/`Category` 模型与读写封装。
  - **N02 剩余金额 + 统计**：依赖 `Budget`/`BalanceBaseline` 与账单查询。
  - **N03 DeepSeek 解析**：依赖 `Transaction` 写入与 `Category` 清单。
  - **N06 截图后台入账**：依赖本节点确定的 `ModelContainer` 共享方式（是否 App Group）。
- **本节点对下游的契约承诺**：四模型字段与技术基线 §8 一致、金额为 `Decimal`、存在一个可被主 App（及后续后台链路）访问的共享 `ModelContainer`、首次启动后预置分类可查询到。

## 需要你确认的关键决策

> 这是 §11 第 1 条要求"前移"的判定，直接决定本节点建库形态，需在 PRD 评审时确认。

**决策点：截图后台入账的进程路线 → 本节点是否引入 App Group 共享容器？**

- **推荐方案（默认采纳）：in-app App Intents 路线 → 本节点不引入 App Group。**
  - 理由：App Intents 支持在主 App 进程内后台执行，主 App 与后台 Intent 天然共享同一 `ModelContainer`；契合"零三方依赖、私人自用、代码最简"的基调（§3）；避免为一个私人自用 App 过早引入 App Group 配置负担。
  - 风险对冲（及其边界）：将 `ModelContainer` 的创建收敛到**单一工厂/封装点**，容器 URL 与配置集中一处；即便 N06 真机验证后被迫改走独立扩展进程 + App Group，**代码改动**也只在这一处封装，不扩散到各 ViewModel（ViewModel 只持有注入的 `ModelContext`）。**但对冲不消除数据搬迁**：若切换时已积累真实账单，仍需一次"把已有 store 文件从默认目录搬到 App Group 共享目录"的迁移逻辑并验证——这步不在封装的消除范围内，需在 N06 一并评估。
- **备选方案：独立扩展进程路线 → 本节点即按 App Group 共享容器建库。**
  - 仅当你已确定后台链路要用独立扩展进程时选它；本节点会预先配置 App Group、容器指向共享目录。
  - 代价：需要 App Group entitlement 配置；对私人自用 App 偏重。

若你不确定，**默认按推荐方案（in-app，不建 App Group）推进**，并以"单一容器封装点"保留迁移余地。N06 节点做真机 spike 时若确证必须独立进程，再在 N06 评估迁移成本。

## 需求范围

1. **Xcode 工程骨架**：创建 iOS App 工程，部署目标 iOS 17+，SwiftUI `App` 生命周期，纯 Swift、无 SPM/CocoaPods 三方依赖；工程能编译并在 iOS 17+ 模拟器/真机启动到一个占位根视图（占位内容不做要求，可为空白或临时调试入口）。
2. **四个 SwiftData 模型**：按技术基线 §8 实现 `Transaction`、`Category`、`Budget`、`BalanceBaseline`，含各自字段与 `Transaction`↔`Category` 关系；金额字段（`amount`、`initialAmount`）用 `Decimal`；枚举 `direction`、`source`、`periodType` 落地为可持久化形态。
3. **ModelContainer 初始化与共享**：建立单一的 `ModelContainer` 创建封装点并注入 SwiftUI 环境，供后续视图/ViewModel 通过 `ModelContext` 访问；容器配置（存储位置/是否共享）集中于此一处，按"需要你确认的关键决策"结论落地（默认 in-app、非 App Group）。
4. **预置分类首次装载**：App 首次启动（库为空）时幂等写入 8 条预置分类（支出 衣/食/住/行/玩/其他；收入 工作/其他收入），`isPreset=true` 并设 `sortOrder`；重复启动**不**重复写入。
5. **基础读写封装**：提供一层薄封装（查询/新增/更新/删除）覆盖四模型的基本 CRUD，供 N01+ ViewModel 调用；封装形态从简，不过度分层。
6. **可观察性验证手段**：提供一个临时调试入口（如仅 DEBUG 可见的按钮/菜单）或单元测试，用来演示"四模型可增删改查""首次启动预置分类已写入且可查询"，作为退出标准的可观察证据。

## 不做什么

以下均属后续节点，本节点**不实现**：

- 任何**用户可见的记账/账单/统计界面**：手动记账表单、账单列表/筛选/编辑/删除（→ N01）、剩余金额与统计展示（→ N02）。
- **业务计算逻辑**：剩余金额派生计算、统计聚合、预算进度——本节点只建 `Budget`/`BalanceBaseline` 表结构，不算数（→ N02）。
- **AI / 识别 / 后台链路**：DeepSeek Client、OCR、语音、截图相册、快捷指令后台入账与通知（→ N03~N06）。
- **Keychain / UserDefaults 封装**：DeepSeek Key 读写、通知开关、预算周期规则、超支阈值的持久化封装（→ N03 最小 Key 读写 / N07 收口）；本节点只确保这些非实体状态**不进 SwiftData**。
- **完整设置界面、预算设置入口、首次引导 UI、权限申请**（→ N07）。
- **分类的用户增删改界面**与解析层的分类兜底匹配规则（界面→N07；匹配→N03）；本节点仅写入预置分类并保证表支持增删改。
- **App Group 的实际启用**（除非评审选定备选方案）：默认推荐方案下不配置 App Group。

## 验收标准

（对齐 DAG 中 N00 的"退出标准（可观察）"；本节点无 PRD 编号验收点直接落点，属所有验收点的底座。）

1. **工程可编译运行**：工程在 iOS 17+ 目标上编译通过，并能在模拟器或真机启动到占位根视图，无崩溃。
2. **四模型可 CRUD**：通过临时调试入口或单元测试，对 `Transaction`、`Category`、`Budget`、`BalanceBaseline` 各完成一次"新增→查询到→修改→删除"，结果符合预期。
3. **金额为 Decimal**：`Transaction.amount`、`Budget.amount`、`BalanceBaseline.initialAmount` 的类型为 `Decimal`，写入含小数（如 `35.55`）后读回无浮点误差。
4. **预置分类首次装载**：全新安装首次启动后，库中存在且仅存在 8 条预置分类（衣/食/住/行/玩/其他 + 工作/其他收入），`isPreset=true`，可被查询到；**再次启动不产生重复分类**（数量仍为 8）。
5. **Transaction↔Category 关系可用**：能创建一笔关联到某预置分类的 `Transaction` 并通过该分类反查到它（或经关系读到其分类名）。
6. **ModelContainer 单点共享**：容器创建集中在单一封装点，被 SwiftUI 环境注入；后续节点可经 `ModelContext` 读写同一存储（以调试入口/单测能读到同一数据为证）。
7. **非实体状态未入库**：确认 DeepSeek Key、通知开关、预算周期规则、超支阈值等未被建成 SwiftData 模型字段（以模型定义审阅为证）。
8. **App Group 决策已落定并记录**：按"需要你确认的关键决策"的结论落地建库。若走默认推荐方案（in-app），则以**未配置 App Group entitlement + `ModelContainer` 使用默认（非共享）配置**为可审阅证据，并在节点 TRD/进度中记录该选择、迁移对冲点及"数据搬迁不被对冲消除"的边界。
