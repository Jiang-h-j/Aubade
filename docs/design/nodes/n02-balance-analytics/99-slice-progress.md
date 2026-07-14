# N02 剩余金额 + 统计 — 切片进度

> 个人恢复入口。每完成一个切片，更新本表 + `.claude/jflow/current.json`（经 `complete-trd`）。

## 切片状态

| 切片 | 文件 | 状态 | 说明 |
|---|---|---|---|
| 01 | `01-balance-summary-trd.md` | todo | 剩余金额纯函数 + 基线唯一写入 + 账单页汇总卡 + 我的页初始总额 |
| 02 | `02-stats-aggregator-shell-trd.md` | todo | 统计聚合纯函数（区间/合计/趋势/占比/预算）+ 统计 Tab 骨架（粒度/导航禁未来/日档） |
| 03 | `03-charts-breakdown-budget-trd.md` | todo | 周月年档：Swift Charts 趋势折线 + 条形占比 + 下钻明细 + 预算进度 + DEBUG 写预算入口 |

## 恢复提示

- 下一切片：01（剩余金额 + 汇总卡 + 初始总额）。
- 每次 `jflow-dev` 最多实现一个切片，实现后经 `jflow-review` 自评审 PASS，再 `complete-trd`。
- 全节点共用约束见 `00-index.md`（不自建 container / Decimal 纯运算 / 半开区间 / 周首日=周一 / 聚合走纯函数 / 复用 CategoryStyle+AmountFormat / 不越界 N07/N03-06）。

## 关键决策速查

- 剩余口径：技术基线精确版 `initialAmount + Σ基线后收入 − Σ基线后支出`，`occurredAt >= establishedAt`（非 demo 全量简化）。
- 多条 Budget/Baseline：写侧唯一化（清同类再插）；Budget 无时间戳，靠 `setBudget` 唯一化后读 `first{periodType==x}`，Baseline 另有 `establishedAt` 可排序（双保险）。
- 趋势图：Swift Charts（iOS 16+ 原生，非自绘 SVG）。
- 预算阈值：near=80~100%、over=>100%（demo 只有 over，本节点补 near）。
- 预算/初始总额设置界面在 N07；本节点预算靠 DEBUG 入口写库验收。
