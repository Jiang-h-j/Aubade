# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n03-deepseek-text/02-text-entry-key-trd.md`
- 下一个 TRD：`docs/design/nodes/n03-deepseek-text/03-result-card-fallback-debug-trd.md`
- 更新时间：2026-07-14T17:08:45+08:00

## 上一次 TRD 开发

N03 切片 02「文本识别入口 + 无 Key 拦截 + 最小 Key sheet + 识别状态机 + 识别成功入账」——把文本识别 UI 主链路接通:
- 记账页「📋 文本识别」入口从"敬请期待"占位改为进入识别页(`.fullScreenCover`)。
- 识别页:大输入框 + 「读取剪贴板」(UIPasteboard)+ 「识别并记账」CTA。
- 识别状态机 `RecognitionPhase`(idle/recognizing/failed):识别中全屏 spinner + 双重禁重复提交。
- 无 Key 拦截:`isConfigured==false` 先于识别弹 alert(文案裁去 N07"我的→Key"指向,避免死链)→「去填写」直开 `KeySetupSheet`(SecureField 写 Keychain)。
- 识别成功:`RecognitionEntry.recognizeAndSave`(可测核心,@MainActor)→ 归一 → `createTransaction(source:.text, rawText:输入原文)` → dismiss 回记账页(最近记录 +1)。
- 识别失败:按 `RecognitionError` 五分支给文案,只提示、不产生脏账、不丢原文。

## 涉及文件和符号

新增:
- `Aubade/Features/Recognition/RecognitionState.swift`(`RecognitionPhase`)
- `Aubade/Features/Recognition/TextRecognitionView.swift`(`RecognitionEntry.recognizeAndSave` 可测核心 + `TextRecognitionView` + `recognize()`)
- `Aubade/Features/Recognition/KeySetupSheet.swift`(最小 Key 填写 sheet)
- `AubadeTests/RecognitionEntryTests.swift`(4 条入账落库单测)

改动:
- `Aubade/Features/Record/RecordTabView.swift`:「文本识别」EntryButton action 接线 + `@State showingTextRecognition` + `.fullScreenCover` + `#if DEBUG` 注入 parser(生产 DeepSeekClient / DEBUG MockTransactionParser)。

未改:LedgerStore/TransactionEditor 签名、N01/N02 既有行为(git status + 子 agent 确认)。

## 验证情况

- 编译:`xcodebuild test`(scheme Aubade / iPhone 17 Pro 模拟器)全量编译通过。
- 测试:15 条聚焦测试全绿(本片 RecognitionEntryTests 4 + 01 遗留 RecognitionNormalizerTests 8 + MockParserTests 3);覆盖 TRD 验证点 1-4——成功入账全字段(amount==Decimal("256.00")/direction/merchant/cardTail/source==.text/rawText==输入原文/category 命中)、无金额不入账(0 笔)、network/timeout/invalidResponse 不入账(0 笔)、时间 clamp 不越未来。
- Jflow Review:1/3 轮 PASS,零阻断。两个只读子 agent 独立评审——正确性+安全(失败不产生脏账不变量成立、@MainActor 并发正确、Key 只进 Keychain、失败文案无遗漏、单测真绿)、TRD 契约+范围守纪(6/6+5/5+4/4 覆盖、"不做什么"全守纪、硬红线未破、约定8文案达标)。
- 采纳 1 条非阻断建议:catch-all(落库意外)加 `modelContext.rollback()` 焊死"失败不产生脏账";修复后重编译+重跑测试仍全绿。另 `RecognitionEntry` 钉 @MainActor 消除 "Unbinding from the main queue" 运行时告警。

## 遗留风险和注意事项

- 真实 DeepSeek 联网入账未端到端验收(约定 1:编译交付,DEBUG 全量走 mock;联网真解析由用户后续在 release/真机自测)。
- 肉眼验收(模拟器 DEBUG mock)未由本会话跑模拟器执行——单测已焊死落库正确性,但入口点击→spinner→回记账页的 UI 交互建议用户跑一次模拟器确认。
- 本片"回记账页"是临时终态;切片 03 把成功后改为弹结果卡片(复用 TransactionEditor + 折叠原文 + 改/删),届时本片肉眼场景 5 被结果卡片替代。
- `failureTitle/failureMessage` 的 `.noKey` 分支在本片是死代码(无 Key 走 showKeyBlockedAlert 早退,永不产生 .failed(.noKey)),为 exhaustive switch 防御性写法,无害。

## 下一次开发

1. 读取 `current.json.next_trd`，确认值仍为 `docs/design/nodes/n03-deepseek-text/03-result-card-fallback-debug-trd.md`。
2. 读取该 TRD 同目录的 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `docs/design/nodes/n03-deepseek-text/03-result-card-fallback-debug-trd.md`，只实现该 TRD 切片。

补充说明：
- 下一个 TRD:`docs/design/nodes/n03-deepseek-text/03-*-trd.md`(切片 03:识别成功结果卡片 + 失败转手动带原文 + DEBUG 运行时 mock 开关)。
- 恢复步骤:读 `current.json.next_trd` 确认切片 03 路径 → 读该 TRD + 本目录 `99-slice-progress.md` + `.claude/jflow/features/n03-deepseek-text/handoff.md` → 进 `jflow-dev` 只实现切片 03。
- 切片 03 将改动本片:`TextRecognitionView.recognize()` 成功后从 `dismiss()` 改为弹结果卡片;失败 alert 从纯提示改为带"转手动填写(预填原文)/重试";加 DEBUG 运行时 mock 行为开关(替代当前编译期 #if DEBUG 固定 mock)。
- 分支:`feat/n03`(本节点已用)。本片提交后仍在此分支。
