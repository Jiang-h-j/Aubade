# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n03-deepseek-text/01-parsing-core-trd.md`
- 下一个 TRD：`docs/design/nodes/n03-deepseek-text/02-text-entry-key-trd.md`
- 更新时间：2026-07-14T16:43:29+08:00

## 上一次 TRD 开发

N03 切片 01「M4 解析底座」——无 UI 的纯逻辑层，正确性由单测焊死：
- 解析协议 `TransactionParsing`（真实/mock 同契约）+ 原始中间结果 `ParsedTransaction`。
- 归一纯函数 `RecognitionNormalizer`：金额→Decimal（不经 Double）、时间兜当前+禁未来 clamp、分类 name+direction 精确匹配+兜底「其他」/「其他收入」+方向矛盾以方向为准+兜底缺失返 nil。
- 5 类可区分错误 `RecognitionError`（noKey/network/timeout/noAmount/invalidResponse）。
- `MockTransactionParser`（success 对齐 data.js MOCK_RECOGNIZE 定值 + 4 失败行为）。
- `DeepSeekClient`（URLSession 调 OpenAI 兼容 /chat/completions，编译交付，不自动重试）。
- `KeychainStore`（DeepSeek Key 读/写/删 + isConfigured，写侧先 delete 再 add 唯一化）。

## 涉及文件和符号

全为新增，未改任何 N00/N01/N02 文件（文件系统同步组自动纳入 target）：
- `Aubade/Features/Recognition/Parsing/TransactionParsing.swift`（ParsedTransaction + 协议）
- `Aubade/Features/Recognition/Parsing/RecognitionError.swift`
- `Aubade/Features/Recognition/Parsing/RecognitionNormalizer.swift`（amount/occurredAt/category）
- `Aubade/Features/Recognition/Parsing/MockTransactionParser.swift`
- `Aubade/Features/Recognition/Parsing/DeepSeekClient.swift`
- `Aubade/Persistence/KeychainStore.swift`
- `AubadeTests/RecognitionNormalizerTests.swift`（验证点 1-6、8）
- `AubadeTests/MockParserTests.swift`（验证点 7 + Keychain 冒烟）

## 验证情况

- 编译：`xcodebuild test`（scheme Aubade / iPhone 17 模拟器）全量编译通过，仅项目既有 AppIntents 元数据 warning。
- 测试：11 条聚焦测试全绿（RecognitionNormalizerTests 8 + MockParserTests 3），覆盖 TRD 验证点 1-8 + Keychain set→get→clear 冒烟。
- Jflow Review：1/3 轮 PASS，零阻断。两个只读子 agent 独立评审——代码正确性+安全（归一边界/Keychain/DeepSeek 分支/测试无假绿全过）、TRD 契约+范围守纪（8 文件到位 100%、8 验证点覆盖 100%、"不做什么"守纪合格）。
- 采纳非阻断建议：DeepSeekClient 裸数字 amount 由 `Decimal(Double)` 改为 `Decimal.self` 直解，守金额精度红线；修复后重编译+重跑测试仍全绿。

## 遗留风险和注意事项

- `DeepSeekClient` 未联网验收（已确认约定 1：编译交付，联网端到端由用户后续自测）；prompt/schema/超时 20s/无重试均已落地。
- `MockParserTests.testKeychainSetGetClear` 用真实 `KeychainStore.shared`：无 defer 清理（断言中途失败会残留 sk-test-*，下次开头 clear 可自愈）；CI 宿主若缺 keychain entitlement，SecItemAdd 可能静默失败致断言挂。切片 02 若加更多 Keychain 测试，考虑抽 KeychainStoring 协议注入假实现。
- `DeepSeekClient.parseDate` 未设 timeZone，按系统时区解析（对本地短信时间合理）。

## 下一次开发

1. 读取 `current.json.next_trd`，确认值仍为 `docs/design/nodes/n03-deepseek-text/02-text-entry-key-trd.md`。
2. 读取该 TRD 同目录的 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `docs/design/nodes/n03-deepseek-text/02-text-entry-key-trd.md`，只实现该 TRD 切片。

补充说明：
- 下一个 TRD：`docs/design/nodes/n03-deepseek-text/02-text-entry-key-trd.md`（文本识别入口 + 无 Key 拦截 + 最小 Key sheet + 识别状态机 + 识别成功入账）。
- 下一步动作：进入 `jflow-dev` 实现切片 02。它将消费本片的 `TransactionParsing`（注入 mock/真实）、`RecognitionError`（入口分支：noKey→拦截、noAmount→转手动、network/timeout/invalidResponse→提示失败）、`KeychainStore.isConfigured`（无 Key 拦截判据）、`RecognitionNormalizer`（识别成功→归一→入账）。
- 分支：`feat/n03`（本节点已用，已建上游）。本片提交后即在此分支。
