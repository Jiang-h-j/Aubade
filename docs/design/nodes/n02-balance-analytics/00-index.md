# N02 剩余金额 + 统计 — TRD 索引

> 节点 PRD：`docs/prd/nodes/n02-balance-analytics-prd.md`（已评审通过）。
> 上游代码事实：N00 数据层 + N01 手动记账/账单列表（提交 38d98ee）。
> UI 与聚合口径事实来源：已实现原型 demo `prototype/app/`（`app.js` / `data.js` / `styles.css`）。
> 本节点无 `.codegraph/` 索引，代码事实来自逐文件阅读，行号为写作时快照（可能 ±1 漂移）。

## 切片划分与顺序

N02 拆成 **3 个单一职责切片**，按"先独立闭环、再骨架、后可视化"排序，每片可独立编译运行与验收：

| 切片 | 名称 | 单一职责 | 依赖 | 覆盖 PRD 验收 |
|---|---|---|---|---|
| 01 | 剩余金额 + 汇总卡 + 初始总额 | M6 完整闭环：剩余派生纯函数 + `BalanceBaseline` 唯一写入 + 账单页汇总卡 + 我的页初始总额录入/调整 | N01 | 验收 1、2、3（汇总卡半）、9（同步半） |
| 02 | 统计聚合纯函数 + 统计 Tab 骨架 | M5 底座：`StatisticsAggregator` 无状态聚合纯函数（区间/合计/趋势/占比/预算）+ 统计 Tab 骨架（粒度切换 / 时间导航禁未来 / 日档流水） | N01（不调用切片01；同 Analytics/ 目录与 Tab 体系） | 验收 4（合计半）、8（粒度导航/日档） |
| 03 | 周月年档可视化 + 预算进度 | 在骨架上填：支出趋势折线 + 条形分类占比 + 下钻明细 + 周月档预算进度与阈值 | 切片 02 | 验收 4（占比）、5、6、7、9（统计同步半）、10 |

### 为什么这样拆
- **切片 01 独立最小闭环**：剩余金额(M6)只依赖账单收支与基线，不依赖任何统计聚合，先交付"能看结余"的价值，风险最低。
- **切片 02 建骨架 + 聚合底座**：统计的时间维度骨架（粒度/导航/日档）与可单测的聚合纯函数一次建好；日档只列流水不含趋势图（原型 §4.6 契约），复杂度低，先验证时间维度正确性。
- **切片 03 填可视化**：趋势折线、条形占比、下钻、预算进度都建立在切片 02 的聚合纯函数与骨架之上，是纯"消费聚合结果 + 渲染"，与前两片无回改。

## 切片文件

- `01-balance-summary-trd.md`
- `02-stats-aggregator-shell-trd.md`
- `03-charts-breakdown-budget-trd.md`

## 全节点共用的关键约束（三片都遵守）

1. **不自建 `ModelContainer`**：一律注入 `ModelContext` / `LedgerStore(context)`，禁链式 `container().mainContext`（N00 SIGTRAP 陷阱，见 memory 与 `PersistenceController.swift:7`、测试注释）。
2. **金额纯 `Decimal` 运算**：聚合求和、剩余计算不经 `Double`，对齐 `DecimalPrecisionTests` 约定。
3. **半开区间 `[start, end)`**：所有区间判定复用 `LedgerFilter` 口径，禁用 `DateInterval.contains`（`LedgerFilter.swift:48-50`）。
4. **周首日 = 周一**：聚合/预算用的 `Calendar` 必须 `firstWeekday = 2`（技术基线 §2/§8）。
5. **聚合走新增无状态纯函数**：注入 `transactions`/`now`/`calendar`，视图层 `@Query` 全量取 + 内存聚合（与 N01 `LedgerTabView` 同策略），天然实时同步。
6. **配色/格式化复用**：分类色/emoji 走 `CategoryStyle.color(name:direction:)`/`emoji`（传方向），金额走 `AmountFormat`。
7. **不越界**：预算/初始总额的**完整设置界面**、Key、分类管理、首次引导、通知 → N07；AI 识别 → N03~06。本节点预算靠 DEBUG 入口/单测写入验证；我的页只做初始总额一项。
