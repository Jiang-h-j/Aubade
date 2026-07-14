# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n03-deepseek-text/03-result-card-fallback-debug-trd.md`
- 下一个 TRD：`全部完成`
- 更新时间：2026-07-14T17:48:29+08:00

## 上一次 TRD 开发

N03 切片 03「结果卡片 + 失败转手动带原文 + DEBUG 运行时 mock 开关」——把文本识别最后一公里补齐（识别完能当场看/改/撤）：
- **识别成功**：从切片 02 的 dismiss 回记账页，改为**先入账 → 弹结果卡片**（复用 `TransactionEditor(.edit)`，走 edit 语义因账单已存在）。可当场改金额/分类/时间/商户/备注，「保存」走 `EditorActions.makeUpdate` 回写；展开「查看识别到的原始文本」看折叠原文。
- **删除撤销**：结果卡片「删除这笔」→ 二次确认（`confirmationDialog`）→ `EditorActions.makeDelete` 撤销入账。与 N01 `TransactionDetailView` 严格同构（先 dismiss 再 delete，规避 SwiftData 悬垂 SIGTRAP）。
- **失败转手动带原文**：失败 alert 按 `RecognitionError.isRetryable` 分支——network/timeout/invalidResponse 给「重试」（`retryToken` + `onChange` 重跑 recognize）；所有失败给「转手动填写」→ `ManualEntryView(prefillNote: 识别页原文)` 预填备注。noAmount 转手动补金额即可记，不产生脏账。
- **DEBUG 调试**：`DebugMenuView` 加 N03 Section（Key 状态/写占位 Key/清 Key + 5 档 mock 行为 Picker）；`RecordTabView` DEBUG 下 `textParser` 改读 `@AppStorage(DebugMockSettings.behaviorKey)` 运行时切换 mock 行为。

## 涉及文件和符号

新增：
- `AubadeTests/ResultCardActionsTests.swift`（4 条单测）
- `TextRecognitionView.swift` 内新增 `RecognitionResultCard` 子视图（结果卡片，同构 N01 删除二次确认范式）

改动：
- `TransactionEditor.swift`：init 加 `initialNote: String? = nil`（向后兼容）；初始草稿构造抽为 `static makeInitialDraft`（可测核心）；body 加折叠原文 `rawTextSection`（消费已声明的 `rawText`）。
- `TextRecognitionView.swift`：成功分支 `resultTx = tx` 弹结果卡片（`.sheet(item:$resultTx, onDismiss:{dismiss()})` 关闭链）；失败 alert 加转手动/重试；新增 `@State resultTx/showingManualEntry/retryToken`。
- `RecognitionError.swift`：加 `isRetryable` 计算属性。
- `MockTransactionParser.swift`：`Behavior` 加 `: String, CaseIterable`（供 @AppStorage rawValue）。
- `ManualEntryView.swift`：加 `init(prefillNote: String? = nil)` 透传 `initialNote`。
- `RecordTabView.swift`：DEBUG `textParser` 读 `@AppStorage` mock 行为。
- `DebugMenuView.swift`：加 `DebugMockSettings.behaviorKey` + N03 调试 Section。

未改：`EditorActions.makeUpdate` 回写字段集（cardTail/source/rawText 不进 update）、`TransactionDraft` 结构、`EditorMode`（未加 .result）、`LedgerStore` 签名、N01/N02 既有行为。

## 验证情况

- 编译：`xcodebuild test`（scheme Aubade / iPhone 17 Pro 模拟器）全量编译通过。
- 测试：**98 条全绿 0 失败**，含本片新增 `ResultCardActionsTests` 4 条——完成回写（makeUpdate 更新 amount/category，source==.text/rawText/cardTail 保持不变）、删除撤销（fetch isEmpty）、转手动预填（makeInitialDraft 的 note 命中原文；不传为空）、edit 忽略 initialNote（从 tx 回填）。
- Jflow Review：**1/3 轮 PASS，零阻断**。两个只读子 agent 独立评审——①正确性+行为（关闭链自洽、删除同构 N01 规避悬垂 SIGTRAP、重试无争用、@AppStorage 跨文件 DEBUG 依赖健壮、makeInitialDraft 行为等价）；②TRD 契约+范围守纪（5 项职责全落地、"不做什么"全守纪、签名放宽仅限向后兼容可选参数、无越界 N04/N05/N07、验收 2/3/6/7 全覆盖）。
- 吸收 1 条非阻断修订：补齐 TRD 修改点表格漏列的 `RecognitionError.swift` / `MockTransactionParser.swift`（文档修订，不改代码行为）。

## 遗留风险和注意事项

- **肉眼验收未由本会话跑模拟器**：单测焊死了回写/删除/预填的落库正确性，但结果卡片全交互（成功→弹卡片→改分类→完成→各页同步）、删除二次确认、无金额转手动、网络失败重试这 4 个肉眼场景（TRD 验证点 5-8）建议用户在模拟器（DEBUG mock 切换）跑一遍确认 UI。
- **重试肉眼演示不便**：mock 行为固定于 parser 实例，切换 mock 需退出被 `.fullScreenCover` 遮挡的识别页到调试菜单改，故"网络失败→重试→切成功"一次性演示不便；对真实 DeepSeekClient 的瞬时网络失败重试正常。
- **结果卡片下滑关闭 = 接受这笔**：`onDismiss` 下用户下滑手势关闭结果卡片也会 dismiss 识别页回记账页（因已先入账，"下滑=接受"语义合理，注释已说明）。
- **结果卡片头部沿用"编辑账单"标题**：TRD §2 拍板不做「✓已记一笔」视觉（不值得为纯视觉再开可选参数），若后续需定制编辑器标题归 N07。
- 真实 DeepSeek 联网端到端未验收（约定 1：编译交付，DEBUG 全量 mock，联网由用户真机自测）。

## 下一次开发

全部 TRD 已完成。下一次若继续，请从 PRD 验收标准和最终验证情况开始检查。

补充说明：
N03 节点**三个切片（01 解析底座 / 02 文本识别入口 / 03 结果卡片+转手动+DEBUG）已全部完成**，节点闭环。下一步：
1. 本片提交到 `feat/n03` 分支（`type[scope]:` 规范）。
2. 更新 DAG（`docs/design/aubade-v1-dev-dag.md`）N03 节点状态为完成。
3. 确认 DAG 下一个可开发节点（依赖 N03 是否满足），把 `next_action` 指向生成该节点 PRD（走普通 Jflow 节点 PRD → TRD → dev）；若 N03 是当前依赖链末端且无下一可开发节点，按 config 合并主线（`main_branch` 为 null，需先询问用户主线策略）。
