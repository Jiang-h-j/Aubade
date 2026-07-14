# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n01-manual-ledger/03-ledger-list-filter-trd.md`
- 下一个 TRD：`全部完成`
- 更新时间：2026-07-13T23:40:59+08:00

## 上一次 TRD 开发

N01 切片 03：闭合账单 Tab「看流水 → 筛 → 改 → 删」全闭环，N01 手动记账可自用版完成。账单 Tab 真实视图 `LedgerTabView` 替换切片 01 的 `LedgerTabPlaceholder`：`@Query` 全量 + 内存过滤/分组（TRD §1 决策）；顶部筛选栏（分类 × 时间范围，可叠加）；按自然日分组倒序、组内 occurredAt 倒序的流水列表，每行分类彩标 + 商户/备注摘要 + 方向金额；点行经 `.sheet` 进编辑页（复用切片 02 `TransactionEditor(.edit)` + `EditorActions.makeUpdate` 落库）；列表侧滑删除 + 编辑页「删除这笔」双入口均二次确认（`confirmationDialog`）；空账本引导去记账、筛选无结果两态分离。筛选核心（半开区间边界、分类过滤、双条件叠加、分组倒序）抽为无状态纯函数 `LedgerFilter`，边界可单测。不含汇总卡（验收 10，→ N02）。

**呈现方式修正**：TRD §66 原写「push」，实现时改为 `.sheet`——切片 02 的 `TransactionEditor` 自带 `NavigationStack`（为 sheet 设计），push 会嵌套导航栈致双导航栏；已同步更新 TRD 记录此决策（用户确认）。

## 涉及文件和符号

新增：
- `Aubade/Features/Ledger/LedgerFilter.swift`：`CategoryFilter`（.all/.some，Equatable+Hashable **基于 LedgerCategory.id** 而非引用，防 @Query 刷新后 Picker selection 丢失）、`DateRangeFilter`（.all/.thisWeek/.thisMonth/.custom，`contains(_:now:calendar:)` 注入 now/calendar 以便单测钉死边界，统一半开区间 `[start,end)` 不用 `DateInterval.contains`）、`LedgerFilter.apply`（分类×时间叠加）/`groupByDay`（日期倒序+组内倒序）、`DayGroup`（Identifiable，day 作 id）。
- `Aubade/Features/Ledger/LedgerRowView.swift`：单行；取色走**主 API** `CategoryStyle.color(name:direction:)`（nil 分类走方向兜底，遵循切片 02 handoff 规范）、`AmountFormat.signedString` 方向金额。
- `Aubade/Features/Ledger/TransactionDetailView.swift`：编辑页容器，包 `TransactionEditor(.edit)` + `makeUpdate` onSave + onDelete 触发 `confirmationDialog` 二次确认。删除顺序**先 dismiss 再 delete**（局部常量捕获闭包），消除 save 触发 @Query 刷新时 sheet 以已删 tx 重建 editor 的时序窗口（SwiftData 已删对象敏感）。
- `Aubade/Features/Ledger/LedgerTabView.swift`：账单主视图，自带 `NavigationStack`；筛选栏（分类/时间 Menu + 自定义 DatePicker `in: ...Date()` 禁未来、止不早于起）；分组 `List`/`Section`（组头 `M月d日`）；侧滑删除 `pendingDelete` + `confirmationDialog`；编辑/自定义双 `.sheet`；空账本/筛选无结果两态。
- `AubadeTests/LedgerFilterTests.swift`（12 例）：固定 UTC+firstWeekday=2+固定 now，钉死本周/本月上下边界内外各一、自定义含止日整天+次日排他、全部时间、分类过滤（all/some/未分类不误命中）、CategoryFilter 按 id 相等、双条件叠加、分组日期倒序+组内倒序+同日合并。

改：
- `Aubade/Features/AppShell/RootTabView.swift`：账单 Tab `LedgerTabPlaceholder` → `LedgerTabView()`；删除已不用的 `LedgerTabPlaceholder` 私有 struct 及临时占位注释；更新 `AppTab`/`RootTabView` 文档注释（记账/账单已是真实视图）。

不改（确认无回归）：`TransactionEditor`/`EditorActions`/`CategoryStyle`/`AmountFormat`（复用，对外形态不动）、`LedgerStore`、所有 `Models/*`、`RecordTabView`（编辑已走共享 EditorActions，无需改）、`AubadeApp`、`PersistenceController`、`project.pbxproj`（file-system-synchronized groups 自动纳编）。

## 验证情况

- 编译：`xcodebuild -scheme Aubade -destination 'platform=iOS Simulator,name=iPhone 17' build` → **BUILD SUCCEEDED**（验证点 1）。
- 单测：`xcodebuild test` → **50 例全绿**（切片 02 的 38 例无回归 + 本片新增 `LedgerFilterTests` 12 例）。半开区间上下边界内外、自定义、全部、分类过滤、双条件叠加、分组倒序全覆盖（验证点 1）。防御性加固后重跑仍 50 全绿。
- **jflow-review 自评审：1/3 轮 PASS，阻断项 0**。两只读子 agent（正确性+TRD符合度 / 上游一致性+SwiftUI/SwiftData陷阱）均 PASS：半开区间无 off-by-one 且单测测的是边界瞬时而非中点、过滤/分组/Hashable 自洽、验收全落点、无越界；取色走主 API、无嵌套 NavigationStack、dismiss 关 sheet 正确、删除基于 TransactionDraft 值快照安全、无悬垂 context、CategoryFilter selection 按 id 稳定。采纳两 agent 共同点名的非阻断项做零成本加固：编辑页删除改「先 dismiss 再 delete」。
- 未做：验证点 2/3/4/5/6/7/8 的模拟器肉眼 UI 交互（分组展示/编辑即时刷新/侧滑与编辑页删除二次确认/分类筛选/时间筛选叠加+自定义禁未来/无汇总卡/闭环回归）——无头环境无法肉眼验收，编译+单测+Preview 就绪，留待有界面环境确认。

## 遗留风险和注意事项

- **编辑页删除时序**：已加固为「先 dismiss 再 delete」，理论上消除已删对象重读窗口；两子 agent 推演当前安全，但项目 memory 记录 SwiftData 对已删对象敏感，**建议有界面环境时对「编辑页打开某笔 → 删除这笔 → 确认」冒烟一次**确认无 SIGTRAP，列表侧滑删除路径无此风险。
- **删除静默失败**：`EditorActions.makeDelete` 内 `try? store.delete` 吞异常（切片 02 定义，本片复用）。本地 SwiftData 删除失败概率极低；若后续要删除失败反馈，需让 delete 返回结果并在 UI 提示。
- **dismiss 语义链依赖约定**：正确性依赖「`TransactionEditor` 自带 NavigationStack、外层容器不再套栈」；`TransactionDetailView`/`TransactionEditor` 顶部注释已作契约护栏，后续勿在 `TransactionDetailView` 补 NavigationStack。
- **@Query 全量过滤**：账单列表取全表内存过滤/分组，TRD 已认可；数据量大后（N02 汇总或膨胀时）再评估带 predicate/fetchLimit 的 FetchDescriptor。
- **金额 i18n / edit 回填尾零**：延续切片 02 已知项（`Decimal(string:)` 恒 `.` 小数点；`88.80` 回填显示 `88.8`），纯展示、不影响落库正确性。

## 下一次开发

全部 TRD 已完成。下一次若继续，请从 PRD 验收标准和最终验证情况开始检查。

补充说明：
本片是 N01 节点最后一个 TRD 切片，`completed_trds` 将含全部 3 片。恢复步骤：
1. 读取 `.claude/jflow/current.json`，确认 N01 三片全部完成、`next_trd` 应为空（本节点无后续切片）。
2. 按 DAG（`docs/design/aubade-v1-dev-dag.md`）确认 N01 节点状态可标完成、下一个可开发节点（预期 N02 统计/汇总卡）；`next_action` 指向为下一节点生成 PRD。
3. `config.json.main_branch` 为 null——合并主线前需先与用户确认主分支（当前分支 `main`，但 config 未固化）。
4. 复用资产已就绪：`LedgerFilter`（过滤/分组纯函数）、`LedgerTabView`/`LedgerRowView`、`TransactionDetailView`、切片 02 的 `TransactionEditor`/`EditorActions`/`CategoryStyle`/`AmountFormat`。N02 汇总卡将挂在 `LedgerTabView` 顶部（本片刻意留空未做）。
