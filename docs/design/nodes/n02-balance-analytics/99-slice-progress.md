# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n02-balance-analytics/02-stats-aggregator-shell-trd.md`
- 下一个 TRD：`docs/design/nodes/n02-balance-analytics/03-charts-breakdown-budget-trd.md`
- 更新时间：2026-07-14T12:57:15+08:00

## 上一次 TRD 开发

实现 M5 统计底座 + 骨架（切片02）：
- 新增区间口径纯函数 `StatPeriod`：`make(grain:offset:now:calendar:)` 用 `Calendar.dateInterval(of:)` 算日/周/月/年四档半开区间 `[start,end)` + 导航标题/副标题（day"M月D日"+周X、week"M月D日 - M月D日"+本周/N周前、month/year 当前档带本月/今年）；`isAtOrAfterNow(offset)=offset>=0` 禁未来（TRD 权威口径，比 demo isFuture>0 更严，当前区间也禁 ›）。
- 新增聚合纯函数 `StatisticsAggregator`（无状态、纯 Decimal）：`total`（复用 BalanceCalculator.sum + 半开过滤）、`expenseBreakdown`（降序/pct 四舍五入/总额0空数组/nil分类哨兵id成组/等额按id串稳定定序）、`expenseTrend`（year=12桶/month=当月天数/week&day=所在周7天，仅支出）、`budgetProgress`（over>100/near80~100/normal<80，防除零）+ `BudgetState` + `BreakdownRow(Identifiable)`。
- 新增统计 Tab 骨架 `AnalyticsTabView`：`@Binding selection`（照抄 RecordTabView 范式，切片02 即定死供切片03 消费）+ 粒度分段切换（切换 offset 归零）+ 时间导航（› 到当前置灰禁未来）+ 合计卡（日档"当天支出/收入"文案）+ 日档流水（复用 LedgerRowView，点行 .sheet(item:) 进 TransactionDetailView）+ 周月年档占位区（切片03 填充）。
- RootTabView：`AnalyticsPlaceholderView()` → `AnalyticsTabView(selection: $selectedTab)`，干净移除占位结构体，更新主框架注释。
- 回填 02 TRD：`expenseBreakdown` 签名去掉 TRD 草案的 calendar 参数（实现不需要，仅按 period 日期过滤 + 按 id 分组），注明供切片03 按 2 参签名消费。

## 涉及文件和符号

- `Aubade/Features/Analytics/StatPeriod.swift`（新增）：`StatGrain` 枚举 + `StatPeriod.make` / `.isAtOrAfterNow`
- `Aubade/Features/Analytics/StatisticsAggregator.swift`（新增）：`total`/`expenseBreakdown`/`expenseTrend`/`budgetProgress` + `BudgetState` + `BreakdownRow`
- `Aubade/Features/Analytics/AnalyticsTabView.swift`（新增）：`@Binding selection` + grainPicker/timeNav/totalsCards/dayList/chartsPlaceholder
- `Aubade/Features/AppShell/RootTabView.swift`（改）：接线 AnalyticsTabView + 移除 AnalyticsPlaceholderView
- `AubadeTests/StatPeriodTests.swift`（新增 9 单测）、`AubadeTests/StatisticsAggregatorTests.swift`（新增 11 单测）
- `docs/design/nodes/n02-balance-analytics/02-stats-aggregator-shell-trd.md`（回填 expenseBreakdown 签名）

## 验证情况

- 单测：新增 20 例（StatPeriod 9 + StatisticsAggregator 11）全通过——四档半开边界/周一起/禁未来/合计按方向半开/占比降序pct空数组nil哨兵/趋势桶数跟随粒度仅支出/预算阈值79-80-100-101-137。
- 全量回归：AubadeTests 78 例全通过（58 旧 + 20 新），0 失败，N00/N01 无回归。
- 编译：build-for-testing BUILD SUCCEEDED（iOS 17 target，零参 onChange 可编译，无 import Charts）。
- 模拟器：App 启动无崩溃（PID 存活），默认记账 Tab 正常渲染。**UI 局限**：环境无 idb/tap 工具，无法程序化点击切到统计 Tab 或经 DebugMenu 造数，统计 Tab 的交互（粒度切换/导航翻页/日档点击）未做肉眼验证；核心风险（区间/聚合纯函数）已由 20 单测全覆盖。
- Jflow Review：1 轮 PASS，2 只读子 agent（正确性+TRD符合度 / 范围守纪+复用+无回归+前向兼容切片03）均无阻断。采纳 1 项（回填 TRD expenseBreakdown 签名去 calendar，避免切片03 照草案误传）。非阻断建议（inRange 可提公开供视图复用、趋势 label 铺满需切片03 绘图时稀疏化、补跨月周标题断言）留待切片03，未处理。

## 遗留风险和注意事项

- **统计 Tab UI 未肉眼验证**：环境缺 tap 工具，粒度/导航/日档交互仅靠单测覆盖数据正确性，视觉与手势需后续在真机/可交互模拟器补验。
- `AnalyticsTabView.periodTransactions`（视图内半开过滤）与 `StatisticsAggregator.inRange`（private）是同一口径两处实现；口径一致无回归，可后续将 inRange 提为公开方法供视图复用消重。
- `expenseTrend` 每桶产完整 "M/D" label；切片03 绘图需自行稀疏化 x 轴标签（对齐 demo trendSeries 非里程碑日给空串）。
- `@Binding selection` 本片 body 内未读写（仅定死签名供切片03 跳我的 Tab），有意为之，非未用告警。

## 下一次开发

1. 读取 `current.json.next_trd`，确认值仍为 `docs/design/nodes/n02-balance-analytics/03-charts-breakdown-budget-trd.md`。
2. 读取该 TRD 同目录的 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `docs/design/nodes/n02-balance-analytics/03-charts-breakdown-budget-trd.md`，只实现该 TRD 切片。

补充说明：
1. 读 `current.json.next_trd`，应为 `docs/design/nodes/n02-balance-analytics/03-charts-breakdown-budget-trd.md`（切片03，N02 最后一片）。
2. 读该 TRD 同目录 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 切片03 内容：周月年档可视化——Swift Charts 趋势折线（import Charts，iOS17 原生）+ 条形分类占比 + 下钻明细 sheet（复用 LedgerRowView/TransactionDetailView）+ 预算进度（新增 LedgerStore.setBudget 写侧唯一化 + @Query budgets.first）+ DebugMenu 写预算/初始总额入口。消费切片02 已就绪的 expenseTrend/expenseBreakdown(2参)/budgetProgress/BreakdownRow(Identifiable)/@Binding selection，不回改切片02 签名。
4. 分支：`feat/n02`（本节点已定，沿用，不再询问）。
5. 切片03 是 N02 最后一片；完成后更新 DAG N02 节点状态，next_action 指向下一可开发节点的 PRD。
