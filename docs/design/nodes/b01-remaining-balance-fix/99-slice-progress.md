# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/b01-remaining-balance-fix/02-double-deduction-notice-trd.md`
- 下一个 TRD：`全部完成`
- 更新时间：2026-07-16T20:57:46+08:00

## 上一次 TRD 开发

切片 02「D7 双重扣减提示」：在两个"录初始总额"入口各加同一句 D7 提示——「填当前净值就好，别补录初始总额之前的旧账，否则会被重复扣减。」告知用户切片 01 全量口径下的双扣边界。纯文案规避，不做去重对账。覆盖 PRD 验收 4（提示可见），确认验收 5（未录基线分支）不受影响。

## 涉及文件和符号

- `Aubade/Features/AppShell/RootTabView.swift`：`InitialBalanceSheet` 的 Form footer `Text`（:327）字符串追加 D7 提示句。parsedAmount/onSave/保存按钮 disable/onAppear 预填、private 可见性均未动。
- `Aubade/Features/Onboarding/OnboardingView.swift`：`balanceStep` 说明副标题 `Text`（:78）字符串在"自动加减"后、"可以先跳过"前插入同一 D7 句。parsedAmount/setBalanceBaseline/下一步/先跳过按钮均未动。

## 验证情况

- 编译：`xcodebuild -scheme Aubade -destination 'iPhone 17 Simulator' build` → **BUILD SUCCEEDED**。folder-based 项目仅改字符串，不涉新增文件/pbxproj。
- 无单测（TRD 明确纯 UI 文案，验证方式为目视）。
- jflow-review：第 1 轮 PASS，只读 code-reviewer 子 agent 逐条核实——单一职责（仅 2 处 Text 字面量、零逻辑越界）、两处 D7 核心句一致、落点与语序符合 TRD、无过度设计、private 可见性未变、纯展示不阻塞录入。无阻断项。2 条非阻断建议（既有前置句式微差、"重复扣减"措辞偏机制）不影响推进。

## 遗留风险和注意事项

- 目视验证（我的页「调整初始总额」sheet footer、首次引导步①副标题）留待整体收尾时执行；代码层已确保为纯 Text 展示。
- `Aubade.xcodeproj/project.pbxproj` 仍有一处与本节点无关的改动（objectVersion 降级 + DEVELOPMENT_TEAM），用户已拍板本次提交排除，勿夹带。
- 提交分支：用户已明确「直接提交 main」，本切片沿用。

## 下一次开发

全部 TRD 已完成。下一次若继续，请从 PRD 验收标准和最终验证情况开始检查。

补充说明：
切片 02 是 b01-remaining-balance-fix 节点的最后一个 TRD（共 2 片，01+02 均已完成）。complete-trd 后 next_trd 应为空。
下一步：提交推送（仅 RootTabView.swift + OnboardingView.swift 两个文件到 main，排除 pbxproj），然后更新 DAG 节点 B01 状态为完成，并按 `docs/design/batch01-feedback-fixes-dev-dag.md` 找下一个可开发节点，把 next_action 指向生成该节点 PRD。
