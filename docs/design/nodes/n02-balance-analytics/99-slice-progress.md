# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n02-balance-analytics/03-charts-breakdown-budget-trd.md`
- 下一个 TRD：`全部完成`
- 更新时间：2026-07-14T13:27:05+08:00

## 上一次 TRD 开发

实现 N02 切片 03（周月年档可视化，N02 最后一片）：
- **支出趋势折线图** `ExpenseTrendChart`：Swift Charts（iOS16+ 原生，零第三方依赖）折线 + catmullRom 面积渐变 + 峰值 PointMark 高亮标注 + 峰值/均值副标题（均值除数含 0 桶，对齐 demo）；x 轴标签稀疏化（≤12 桶全显示，当月每日 28-31 桶抽首/中/尾）；本期无支出显示"本期还没有支出"占位。
- **分类占比条形** `CategoryBreakdownView`：Capsule 宽度=pct%、色=CategoryStyle.color(name:direction:.expense)；点某行回调父视图弹下钻。
- **下钻明细** `CategoryDetailSheet`：标题=分类名·区间标题；"共N笔·合计"合计由实时 transactions 求和（与列表同源，sheet 内改删后同步）；List 复用 LedgerRowView，点行进 TransactionDetailView 编辑。
- **预算进度**（仅周/月档）：@Query budgets.first{periodType==目标} 读唯一预算；进度条 min(pct,100)%、over 标红"已超支！"、near 橙态、剩余 max(budget-spent,0)；未设预算跳 selection=.profile；年档不显示。
- **setBudget 写侧唯一化** `LedgerStore.setBudget`：删同 periodType 再插（对称 setBalanceBaseline），全量 fetch+内存 filter 规避 #Predicate 对 String enum 限制。
- **DebugMenu N02 调试 Section**：写月/周预算、清空预算、写初始总额（复用 setBalanceBaseline），支撑预算 UI 肉眼验收（正式设置界面在 N07）。

## 涉及文件和符号

- `Aubade/Store/LedgerStore.swift`（改）：新增 `setBudget(periodType:amount:)`
- `Aubade/Features/Analytics/ExpenseTrendChart.swift`（新增）：Swift Charts 趋势图 + peak/average/axisLabel 稀疏化
- `Aubade/Features/Analytics/CategoryBreakdownView.swift`（新增）：`CategoryBreakdownView`（占比条形）+ `CategoryDetailSheet`（下钻明细，合计实时求和）
- `Aubade/Features/Analytics/AnalyticsTabView.swift`（改）：chartsPlaceholder → periodCharts（trendSection/breakdownSection/budgetSection）；加 @Query budgets、detailCategory sheet、trendSeries/breakdown/currentBudget/detailTransactions 计算属性
- `Aubade/Debug/DebugMenuView.swift`（改）：N02 调试 Section + setBudget/setBaseline/clearBudgets 方法
- `AubadeTests/ModelCRUDTests.swift`（改）：新增 `testSetBudgetUniquePerPeriod`（连写同周期 count==1、取最后值、周月并存）

## 验证情况

- 编译：build-for-testing BUILD SUCCEEDED（iPhone 17 / iOS 26.5，含 import Charts）。
- 单测：新增 1 例（setBudget 唯一化）；全量 79 例全通过（78 旧 + 1 新），0 失败，N00/N01/N02切片01-02 无回归。
- Jflow Review：1 轮 PASS，2 只读子 agent（正确性+TRD符合度 / 范围守纪+复用+无回归+SwiftUI正确性）均无阻断。采纳 2 项两 agent 共同点名的非阻断修复：① 下钻合计由 row.amount 快照改为实时求和（触及验收 6 改删同步）；② 趋势 x 轴标签阈值 7→12（年档 12 月全显示对齐 demo）。修复后重新编译+全量测试再次全绿。
- **UI 局限**：环境无 idb/tap 工具，无法程序化点击切统计 Tab / 经 DebugMenu 造数，趋势/占比/下钻/预算的视觉与手势未做肉眼验证；数值正确性由切片 02 的 20 聚合单测 + 本片 setBudget 单测覆盖。

## 遗留风险和注意事项

- **统计可视化 UI 未肉眼验证**：趋势折线、占比条形、下钻 sheet、预算进度条的视觉呈现与点击手势需后续在真机/可交互模拟器补验（DEBUG 入口已备好造数按钮：写月预算1500/周预算800/初始总额12000/清空预算）。
- 趋势峰值 `.annotation(position:.top)` 在峰值贴图顶时可能被 Chart 边界裁剪（纯视觉小问题，子 agent 观察点，未处理）。
- `AnalyticsTabView.periodTransactions`（视图内半开过滤）与 `StatisticsAggregator.inRange`（private）仍是同口径两处实现；口径一致无回归，聚合不暴露"过滤后 tx 列表"故视图层自行过滤属可接受，长期须保持口径一致。
- 同一 view 挂两个 .sheet(item:)（editingTransaction 日档 / detailCategory 周月年）；二者按 grain 互斥永不同时非 nil，iOS 17 安全。

## 下一次开发

全部 TRD 已完成。下一次若继续，请从 PRD 验收标准和最终验证情况开始检查。

补充说明：
- **N02 节点已全部完成**（切片 01/02/03 三片闭环）。本片是 N02 最后一片。
- 下一步：更新 DAG `docs/design/aubade-v1-dev-dag.md` 中 N02 节点状态为完成；找到下一个可开发节点，next_action 指向生成该节点 PRD（jflow-start）。
- 分支：`feat/n02`（本节点已用，提交沿用）。提交后按 DAG 推进下一节点。
- 提交信息：`feat(n02): 实现切片03 周月年档可视化（趋势/占比/下钻/预算）+ setBudget 写侧唯一化`。
