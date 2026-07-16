# B01 剩余总额口径修复 — TRD 索引

> 节点 PRD：`docs/prd/nodes/b01-remaining-balance-fix-prd.md`（已评审通过）。
> 上游事实来源：批次 PRD `docs/prd/batch01-feedback-fixes-prd.md`（R1 段）、批次技术基线 `docs/design/batch01-feedback-fixes-technical-baseline.md`、批次 DAG `docs/design/batch01-feedback-fixes-dev-dag.md`（B01 详情）。
> 模式 `existing_batch`：在 Aubade v1（N00~N07 已合并 main）既有链路上做修复，不从 0 到 1。
> 本仓库无 `.codegraph/` 索引，代码事实来自本次逐文件阅读核实，行号为写作时快照（可能 ±1 漂移）。

## 里程碑意义

B01 是 `batch01-feedback-fixes` 批次的**首个开发节点（对应批次需求 R1）**，也是这批反馈里最急的一条：**修好「记了账、剩余总额却不动」的 bug**。

现算法有个隐藏条件——`BalanceCalculator.remaining` 只累加「设初始总额那一刻**之后**」（`occurredAt >= establishedAt`）的账，早于那一刻的账（最典型：先记几笔、后录初始总额）被整个漏掉，于是记了账剩余纹丝不动。这是 N02「约定 2：仅计基线后账单」的既有实现，本节点**推翻它**。

按用户拍板的新口径修：**初始总额 = 录入那一刻手上所有钱的净值；之后每一笔收支都在它上面加减，不再按日期卡。** 改动核心极小——`BalanceCalculator` 去掉那行日期过滤。同时新口径有一个用户已确认接受的边界（D7 双重扣减），在两个初始总额录入入口各加一句防呆提示。

做完后「记账 → 剩余变动」这条最基础的反馈闭环恢复正确。

## 关键设计前提（用户本轮拍板 + 核对后确认，TRD 直接据此落地）

1. **推翻 v1 约定 2，剩余改全量求和**：剩余 = `initialAmount` + Σ**全部**收入 − Σ**全部**支出，不再按 `occurredAt` 与 `establishedAt` 先后过滤。早于基线的账也参与加减。
2. **`baseline == nil` 分支不变**：未录初始总额仍返回 nil、视图显示「未设置/—」，这是正常设计分支，不动。
3. **D7 双重扣减边界用文案规避、不改算法**：若用户填的净值本已扣过某笔早期消费、而该消费又作为账单存在，会被双扣。这是新口径的固有边界、用户已确认接受；仅在两个录入处加「填当前净值、勿补录历史账」提示，**不做去重/对账逻辑**。
4. **范围严格锁 R1**：不碰 B02~B04（最近记录删除/自定义分类/识别链/UI 视觉还原），不改数据模型、不动统计链路、不改初始总额录入的解析/校验/写库逻辑。

## 核对后确认的关键代码事实（决定 TRD 落地方式）

| 事实 | 核对结论 | 对 TRD 的影响 |
|---|---|---|
| 唯一 bug 点 | `BalanceCalculator.remaining` 第 `:14` 行 `transactions.filter { $0.occurredAt >= baseline.establishedAt }`（`BalanceCalculator.swift:12-18`），注释口径在 `:9-10` | 切片 01 删 `:14` 过滤、`after` 改用全量 `transactions`；同步改 `:9-10` 注释删「基线后/约定 2」 |
| 过滤点唯一性（防误伤） | 全项目「基线后过滤」**仅 `BalanceCalculator.swift:14` 一处** | 切片 01 只改这一处；下方「不可误改点」清单是红线 |
| 剩余读侧调用点 | `RootTabView.swift:102-103`（我的页）、`LedgerTabView.swift:83`（账单页 hero） | 读侧不改逻辑，自动受益于口径修正；无需改动 |
| `establishedAt` 其余读取点 | 均为**写入侧**（`LedgerStore.createBalanceBaseline/setBalanceBaseline`、`OnboardingView:95`、`RootTabView:128`、`DebugMenuView:159`）或**挑最新基线**（`LedgerStore:115`、`LedgerTabView:73`、`RootTabView:99`） | **不可误改**：它们不是过滤点，误改会引入新 bug |
| 统计链路 | `StatisticsAggregator` 用统计周期区间过滤（`occurredAt` 在 period 内），**不依赖 `establishedAt`** | 不受本节点影响，完全不改 |
| 我的页录入处 D7 落点 | `InitialBalanceSheet`（`private struct`，`RootTabView.swift:301-353`），footer 现为 `:327`「之后每记一笔收支，剩余总额会自动加减。」 | 切片 02 在此 footer 追加/改写 D7 提示；不动 `parsedAmount:310`、`onSave`、写库 |
| 首次引导 D7 落点 | `OnboardingView.balanceStep`（`OnboardingView.swift:73-112`），说明文案现为 `:78`「所有账户加起来的合计，作为剩余金额的起点。之后每记一笔收支会自动加减。可以先跳过，稍后在「我的」里设置。」 | 切片 02 在此文案强化 D7 提示；不动 `parsedAmount:94`、`setBalanceBaseline` |
| 待改单测 | `testBaselineBoundaryInclusive`（`BalanceCalculatorTests.swift:91-102`）**显式锁旧「仅计基线后」口径**（早 1 秒的 50 被排除） | 切片 01 **必改**为新口径（早于基线也计入）+ 补正向断言；其余用例（nil/公式/Decimal 精度/写侧唯一/本月 sum）不动 |

## 切片划分与顺序

B01 拆成 **2 个单一职责切片**，按「先修算法口径（单测可验、影响所有读侧）→ 再补 UI 防呆文案（目视可验、独立于算法）」排序，每片可独立编译、独立验证：

| 切片 | 名称 | 单一职责 | 验证手段 | 覆盖 PRD 验收 |
|---|---|---|---|---|
| 01 | 剩余口径修复 + 单测同步 | **唯一业务逻辑改动**：`BalanceCalculator.remaining` 去掉 `occurredAt >= establishedAt` 过滤，改对全部 transactions 按方向求和；同步 `:9-10` 注释删旧口径；`testBaselineBoundaryInclusive` 改为新口径 + 补「早于基线仍计入」正向断言 | 单测（`BalanceCalculatorTests` 全绿）+ 可观察 970/990 | 1（早于基线计入）、2（持续加减）、3（改历史日期仍计入）、6（单测全绿） |
| 02 | D7 双重扣减提示（两处录入入口） | **纯 UI 文案新增**：`InitialBalanceSheet` footer（`RootTabView.swift:327`）与 `OnboardingView` 步①说明（`:78`）各加/强化「填当前净值、勿补录初始总额之前的历史账，否则会双重扣减」；措辞简短、不阻塞录入流程 | 目视 UI（两处可见提示） | 4（提示可见）、5（未录基线分支不回归——不涉改，回归确认） |

### 为什么这样拆

- **切片 01 先修算法口径**：这是**唯一有业务逻辑波及**的改动，且是所有剩余读侧（我的页、账单页 hero）的共同数据源。先做它并用单测钉死新口径（含删掉旧口径断言、补正向断言），把「口径正确」这件最关键的事一次性验证通过。此片纯逻辑 + 单测，不碰任何 UI。
- **切片 02 补 UI 防呆文案**：D7 提示是**呈现层文案**，与算法正交、无逻辑风险，验证靠目视而非单测。放在算法修好之后，两处文案表述保持一致，一次收尾。拆开是因为验证手段不同（单测 vs 目视 UI）且改动文件不重叠，各自可独立验证、互不阻塞。
- **顺序无强依赖但推荐 01→02**：01 决定「剩余算得对」，02 决定「用户别把净值填错导致双扣」；先保证算法正确再补防呆，符合「核心闭环优先」。

## 切片文件

- `01-balance-semantics-fix-trd.md`
- `02-double-deduction-notice-trd.md`

## 全节点共用的关键约束（两片都遵守）

1. **唯一业务逻辑改动 = 删 `BalanceCalculator.swift:14` 日期过滤**：除此之外不改任何算法；`remaining` 签名（`transactions:baseline:`）、`sum` 函数、返回类型 `Decimal?` 全不动。
2. **金额一律纯 `Decimal`、不经 `Double`**（对齐 `DecimalPrecisionTests` 与既有 `sum` reduce 范式）：切片 01 求和仍走 `sum(_:direction:)`，不引入浮点。
3. **不可误改的红线点**：`establishedAt` 的写入侧（`createBalanceBaseline/setBalanceBaseline`、`OnboardingView:95`、`RootTabView:128`、`DebugMenuView:159`）与「挑最新基线」读取点（`LedgerStore:115`、`LedgerTabView:73`、`RootTabView:99`）**均不是过滤点，不得改动**；`StatisticsAggregator` 统计周期过滤不动；`baseline == nil` 显示「未设置/—」分支不动。
4. **D7 仅新增/改写文案、不动录入逻辑**（PRD 已确认边界）：不碰 `parsedAmount`、`setBalanceBaseline`、`onSave`、按钮 disable 条件；提示为纯展示文案，不阻塞录入流程。
5. **不越界**（PRD「不做什么」）：不碰 B02~B04 范围；不改数据模型（`Transaction`/`BalanceBaseline` 字段，无 SwiftData 迁移）；不动统计链路。
6. **可测性延续 N02 范式**（XCTest 平铺 `AubadeTests/`）：切片 01 改/补的断言复用现有 `date()`/`makeTx()`/`makeBaseline()` helper 与 in-memory 容器（`PersistenceController.makeInMemoryContainer()`）；切片 02 无单测（纯 UI 文案，目视验证）。
