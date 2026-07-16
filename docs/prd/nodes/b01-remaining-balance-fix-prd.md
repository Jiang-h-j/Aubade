# B01 剩余总额口径修复

> 批次 `batch01-feedback-fixes` 首个开发节点（对应批次需求 **R1**）。模式 `existing_batch`：在 Aubade v1（N00~N07 已合并 main）既有链路上做修复，不从 0 到 1。
> 上游事实来源：批次 PRD `docs/prd/batch01-feedback-fixes-prd.md`（R1 段）、批次技术基线 `docs/design/batch01-feedback-fixes-technical-baseline.md`、批次 DAG `docs/design/batch01-feedback-fixes-dev-dag.md`（B01 节点详情）。
> 代码事实来源：本仓库无 `.codegraph/`，以下行号来自本次手动阅读源码核实，可能 ±1 漂移。

## 给用户看的摘要

这个节点只干一件事，也是这批反馈里最急的一条：**修好"记了账、剩余总额却不动"这个 bug**。

现在的算法有个隐藏条件——只把"你设初始总额那一刻**之后**"的账算进剩余，早于那一刻的账（最典型的就是"先记了几笔、后才去录初始总额"）被整个漏掉，于是你记了账，剩余数字纹丝不动。

按你拍板的口径修：**初始总额 = 你录入那一刻手上所有钱的净值；之后每一笔收支都在它上面加减，不再按日期卡。** 改动极小——就是 `BalanceCalculator` 里去掉那行日期过滤。

同时，这个口径有一个你已经确认接受的边界：如果你录初始总额时填的净值**本来就已经扣过**某笔早期消费，而那笔消费又还作为账单存在，它会被扣两次。所以我会在**两个录入初始总额的地方**（首次引导、我的页"调整初始总额"）各加一句短提示：**填当前净值就好，别再补录初始总额之前的历史账**。

范围严格锁在 R1，不碰 B02~B04 的任何东西。做完的可观察标准：先记 3 笔各 10 元支出、再录初始总额 1000 → 剩余显示 **970**（而不是 1000）。

## 目标

1. 修复剩余总额 bug：剩余 = 初始总额 + **全部**收入 − **全部**支出，不再按 `occurredAt` 与 `establishedAt` 的先后做过滤。
2. 在两个初始总额录入入口加一句"填当前净值、勿补录历史账"的提示，让用户能规避已确认的双重扣减边界（决策 D7）。
3. 同步更新锁定旧口径的单测，保持测试全绿。

## 当前理解

- **唯一 bug 点**：`BalanceCalculator.remaining(transactions:baseline:)`（`Aubade/Features/Analytics/BalanceCalculator.swift:12-18`）第 `:14` 行 `transactions.filter { $0.occurredAt >= baseline.establishedAt }`，只累加基线建立时刻之后的账。这是 N02「约定 2：仅计基线后账单」的既有实现。
- **用户拍板口径**：初始总额 = 录入那一刻所有账户的当前净值；剩余对全部账单求和，早于录入时刻的账也参与加减。本节点**推翻 v1 约定 2**。
- **口径边界（用户已确认接受）**：若填写的净值本已扣除过某笔早期消费、而该消费又作为账单存在，会被双重扣减。使用建议"填当前净值、勿补录初始总额之前的历史账"需在录入处体现（D7）。
- **过滤点唯一性（已核实，防误伤）**：全项目"基线后过滤"仅 `BalanceCalculator.swift:14` 一处。`establishedAt` 其余读取点均为**写入侧**（`LedgerStore.createBalanceBaseline/setBalanceBaseline`、`OnboardingView:95`、`RootTabView:128`、`DebugMenuView:159`）或**挑最新基线**（`LedgerStore:115`、`LedgerTabView:73`、`RootTabView:99`），均不可误改。`StatisticsAggregator` 用统计周期区间过滤（`occurredAt` 在 period 区间内），不依赖 `establishedAt`，不受本节点影响。
- **`baseline == nil` 分支不变**：未录初始总额仍返回 nil、视图显示"未设置/—"，这是正常设计分支。

## 涉及的现有链路

- `Aubade/Features/Analytics/BalanceCalculator.swift:12-18` — `remaining(...)`，**唯一改动的业务代码**（去掉 `:14` 日期过滤 + 更新 `:9-10` 注释口径）。
- `Aubade/Features/AppShell/RootTabView.swift:102-103` — 我的页剩余总额调用点（读侧，不改逻辑，自动受益于口径修正）。
- `Aubade/Features/Ledger/LedgerTabView.swift:83` — 账单页 hero 剩余总额调用点（读侧，不改逻辑，自动受益）。
- `Aubade/Features/AppShell/RootTabView.swift:301-353` — `InitialBalanceSheet`（我的页"调整初始总额" sheet），在 `footer`（现 `:327`）加 D7 提示。
- `Aubade/Features/Onboarding/OnboardingView.swift:73-112` — 首次引导步①录初始总额，在说明文案（现 `:78`）加/强化 D7 提示。
- `AubadeTests/BalanceCalculatorTests.swift:91-102` — `testBaselineBoundaryInclusive`，显式锁旧"仅计基线后"口径，**必改**为新口径并补正向断言。

## 需求范围

1. **口径修复**：`BalanceCalculator.remaining` 去掉 `occurredAt >= establishedAt` 过滤，改为对全部 `transactions` 按方向求和（初始总额 + Σ全部收入 − Σ全部支出）。同步更新函数内注释，删除"约定 2/基线后"的旧口径描述。
2. **D7 双重扣减提示**：
   - 我的页 `InitialBalanceSheet` 录入处：加一句简短提示"填当前净值、勿补录初始总额之前的历史账，否则会双重扣减"（落在 sheet footer 或说明文案）。
   - 首次引导 `OnboardingView` 步①：在现有说明文案基础上强化同一提示。
   - 两处提示为 UI 文案，措辞简短、不阻塞录入流程。
3. **测试同步**：更新 `testBaselineBoundaryInclusive` 为新口径（不再排除早于基线的账）；补一条"消费日期早于 `establishedAt` 的账仍计入剩余"的正向断言，对齐验收标准 1、3。

## 不做什么

- **不碰 B02~B04 的任何范围**：不做最近记录删除、不做自定义分类、不动识别链、不做 UI 视觉还原。
- **不改数据模型**：`Transaction`、`BalanceBaseline` 字段不动，无 SwiftData 迁移。
- **不动统计链路**：`StatisticsAggregator`/`AnalyticsTabView` 及其统计周期过滤逻辑完全不改（与本 bug 无关）。
- **不改 `establishedAt` 的写入侧与"挑最新基线"读取点**：它们不是过滤点，误改会引入新 bug。
- **不改 `baseline == nil` 显示"未设置/—"分支**。
- **不改初始总额录入的解析/校验/写库逻辑**：D7 仅新增提示文案，不动 `parsedAmount`、`setBalanceBaseline` 等。

## 验收标准

1. **早于基线的账计入**：全新库，先记 3 笔各 10 元支出，**再**录初始总额 1000 → 剩余显示 **970**（旧行为为 1000）。
2. **持续加减正确**：接上一步再记 1 笔 20 元收入 → 剩余显示 **990**。
3. **改历史日期仍计入**：把某笔消费的日期改到初始总额录入时刻之前 → 该笔仍计入剩余（数字随之变化）。
4. **提示可见**：我的页"调整初始总额" sheet 与首次引导步①录入处，都能看到"填当前净值、勿补录历史账"的双重扣减提示。
5. **未录初始总额分支不回归**：未设初始总额时剩余仍显示"未设置/—"。
6. **单测全绿**：`testBaselineBoundaryInclusive` 更新为新口径且通过；新增的"早于基线仍计入"正向断言通过；`BalanceCalculatorTests` 其余用例（无基线 nil、公式、Decimal 精度、写侧唯一化、本月 sum）与 `StatisticsAggregatorTests` 全部保持通过。
