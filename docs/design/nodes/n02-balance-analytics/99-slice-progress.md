# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n02-balance-analytics/01-balance-summary-trd.md`
- 下一个 TRD：`docs/design/nodes/n02-balance-analytics/02-stats-aggregator-shell-trd.md`
- 更新时间：2026-07-14T11:23:46+08:00

## 上一次 TRD 开发

实现 M6 剩余金额完整闭环（切片01）：
- 新增剩余派生纯函数 `BalanceCalculator`（无状态、纯 Decimal）：`remaining(transactions:baseline:)` = 初始总额 + Σ基线后收入 − Σ基线后支出（`occurredAt >= establishedAt` 为基线后，无基线返回 nil）；`sum(_:direction:)` 按方向求和。
- `LedgerStore` 新增基线唯一写入：`setBalanceBaseline`（清空既有再插，写侧唯一化）+ `currentBaseline`（取 establishedAt 最新），不改任何现有方法签名。
- 账单页 `LedgerTabView` 顶部插汇总卡：剩余总额 · 本月支出 · 本月收入（本月复用 `LedgerFilter.thisMonth` + Calendar 周一）。
- 我的页 `ProfilePlaceholderView` 重写：顶部剩余总额区块 + 录入/调整初始总额 sheet（decimalPad + POSIX locale Decimal 解析 + >=0 校验），DEBUG 调试 Section 保留。
- 金额展示三处（账单页剩余/本月两列、我的页剩余）按 demo 补 `¥` 前缀。

## 涉及文件和符号

- `Aubade/Features/Analytics/BalanceCalculator.swift`（新增）：`BalanceCalculator.remaining` / `.sum`
- `Aubade/Store/LedgerStore.swift`（:93 `setBalanceBaseline`、:102 `currentBaseline`）
- `Aubade/Features/Ledger/LedgerTabView.swift`（`summaryCard` / `summaryColumn` / `monthTransactions` / `@Query baselines`）
- `Aubade/Features/AppShell/RootTabView.swift`（`ProfilePlaceholderView` 重写 + `InitialBalanceSheet`）
- `AubadeTests/BalanceCalculatorTests.swift`（新增 8 单测）

## 验证情况

- 单测：`BalanceCalculatorTests` 8 例全通过（nil/公式/Decimal精度/边界>=/唯一化/取最新/本月合计/空集）。
- 全量回归：AubadeTests 58 例全通过，0 失败，N01 无回归。
- 补 `¥` 后重新编译 BUILD SUCCEEDED（纯展示层字符串，未动计算/测试逻辑）。
- Jflow Review：2 轮=否，1 轮 2 只读子 agent（正确性+TRD符合度 / 范围守纪+复用+UI对齐demo+无回归）均 PASS，无阻断。补 `¥` 前缀为唯一采纳项（对齐 demo UI 事实来源）。次要建议（`try?` 吞错、`max{}` 三处重复、nil 态字号）与 N01 既有风格一致，不阻断，未在本片处理。

## 遗留风险和注意事项

- `setBalanceBaseline` 用 `try?` 吞保存错误（与 N01 `EditorActions.makeDelete` 一致），保存失败无提示；SwiftData 小记录失败概率极低，后续可统一加错误 toast。
- `currentBaseline` 的取最新逻辑在 LedgerTabView / RootTabView / LedgerStore 三处重复（口径一致），可后续抽共享 helper。
- 切片01 未引入 RootTabView 的 selection 绑定（TRD 定为切片02 前移），`ProfilePlaceholderView()` 仍无参实例化，未堵死切片02 重构空间。

## 下一次开发

1. 读取 `current.json.next_trd`，确认值仍为 `docs/design/nodes/n02-balance-analytics/02-stats-aggregator-shell-trd.md`。
2. 读取该 TRD 同目录的 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `docs/design/nodes/n02-balance-analytics/02-stats-aggregator-shell-trd.md`，只实现该 TRD 切片。

补充说明：
- 下一切片：**切片02** `docs/design/nodes/n02-balance-analytics/02-stats-aggregator-shell-trd.md`（统计聚合纯函数 `StatisticsAggregator` + 统计 Tab 骨架：粒度切换/时间导航禁未来/日档流水；含 RootTabView selection 绑定前移）。
- 恢复动作：说「按照 TRD 开发」→ jflow-dev 读 next_trd 实现切片02。
- 分支：`feat/n02`（本节点已确定，后续切片沿用，不再询问）。
- 切片02 依赖 N01 + 同 Analytics/ 目录，不调用切片01，与切片01 无回改。
