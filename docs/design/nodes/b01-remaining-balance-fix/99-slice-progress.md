# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/b01-remaining-balance-fix/01-balance-semantics-fix-trd.md`
- 下一个 TRD：`docs/design/nodes/b01-remaining-balance-fix/02-double-deduction-notice-trd.md`
- 更新时间：2026-07-16T19:53:49+08:00

## 上一次 TRD 开发

切片 01「剩余口径修复 + 单测同步」：推翻 N02 约定 2，`BalanceCalculator.remaining` 去掉 `occurredAt >= establishedAt` 日期过滤，改为对全部 transactions 按方向求和（initialAmount + Σ全部收入 − Σ全部支出）。同步单测断言与注释到新口径，补一条「早于基线仍计入」正向用例。覆盖 PRD 验收 1、2、3、6。

## 涉及文件和符号

- `Aubade/Features/Analytics/BalanceCalculator.swift`：`remaining(transactions:baseline:)` 删过滤行、两处 `sum(after)`→`sum(transactions)`、改写 :9-11 注释为全量口径。`sum`/`guard let baseline`/签名/返回类型未动。
- `AubadeTests/BalanceCalculatorTests.swift`：`testBaselineBoundaryInclusive` 断言 1130→1180 + MARK/行内注释更新；新增 `testTransactionsBeforeBaselineIncluded`（1000 − 早于基线10元支出 = 990）；类头 docstring :7 残留旧口径描述一并修正。其余现有用例未动。

## 验证情况

- 聚焦单测（xcodebuild test，iPhone 17 模拟器）：首轮 22 个全绿（BalanceCalculatorTests 9 + StatisticsAggregatorTests 13，0 失败）；注释修正后重跑 BalanceCalculatorTests 9 个仍全绿。关键：testBaselineBoundaryInclusive=1180、新增 testTransactionsBeforeBaselineIncluded=990 通过，统计链路零回归。
- jflow-review：第 1 轮 PASS，双子 agent 并行（正确性+红线 / TRD 契合度）均无阻断项。红线点（establishedAt 写入侧、挑最新基线、StatisticsAggregator）全部原样未动，单一职责纯净（仅改 2 个目标文件）。1 处非阻断注释残留已顺手修正。

## 遗留风险和注意事项

- `Aubade.xcodeproj/project.pbxproj` 有一处与本节点无关的改动（objectVersion 77→71 降级 + 新增 DEVELOPMENT_TEAM），疑似旧版 Xcode 打开工程副作用。用户已拍板本次提交排除，保留在工作区待用户后续单独决定。切片 01 提交时勿夹带。
- 验收 3（改历史日期仍计入）已由新增单测的底层机制覆盖，UI 层可观察验证留待整体收尾时目视。

## 下一次开发

1. 读取 `current.json.next_trd`，确认值仍为 `docs/design/nodes/b01-remaining-balance-fix/02-double-deduction-notice-trd.md`。
2. 读取该 TRD 同目录的 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `docs/design/nodes/b01-remaining-balance-fix/02-double-deduction-notice-trd.md`，只实现该 TRD 切片。

补充说明：
- 切片 01 已完成并通过评审，待 `complete-trd` 推进状态。
- 下一步：进入切片 02 `docs/design/nodes/b01-remaining-balance-fix/02-double-deduction-notice-trd.md`（D7 双重扣减提示，纯 UI 文案）。两处落点：`RootTabView.swift` 的 `InitialBalanceSheet` footer（约 :327）+ `OnboardingView.swift` balanceStep 说明文案（约 :78）。纯目视验证、无单测。
- 提交分支：用户已明确「直接提交 main」，切片 02 沿用不再询问。
