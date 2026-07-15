# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n05-screenshot-album/01-ocr-provider-source-trd.md`
- 下一个 TRD：`docs/design/nodes/n05-screenshot-album/02-album-picker-wiring-debug-trd.md`
- 更新时间：2026-07-15T15:33:11+08:00

## 上一次 TRD 开发

N05 切片01「Vision OCR provider 底座 + 截图 mock 定值」——纯逻辑地基，零 UI、脱真图片可测。新增「图片 → 本机中文 OCR 文本」的可注入能力（真实 Vision + 三态 mock），并补齐截图成功解析定值与全分支单测，把「图片→文本→记成 `.screenshotAlbum` 账单」核心逻辑用测试焊死。对 N03/N04 零签名改动。

## 涉及文件和符号

新增（5 个）：
- `Aubade/Features/Recognition/Screenshot/TextRecognizing.swift`：`protocol TextRecognizing { recognizeText(in:) }` + `enum TextRecognizeError { empty, failed }`（@MainActor，对齐 N04 VoiceTranscribing 范式）
- `Aubade/Features/Recognition/Screenshot/VisionTextRecognizer.swift`：真实 `VNRecognizeTextRequest` 中文本机 OCR，Data→CGImage→文本；perform 派 `DispatchQueue.global` 后台执行 + `withCheckedThrowingContinuation` 单次 resume
- `Aubade/Features/Recognition/Screenshot/MockTextRecognizer.swift`：`Behavior { success, empty, failed }` + `sampleRecognizedText`
- `AubadeTests/ScreenshotOCRProviderTests.swift`：三态可区分 + `Behavior.allCases` 全集断言
- `AubadeTests/RecognitionEntryScreenshotTests.swift`：`recognizeAndSave` 截图路径落库断言 + 语音不回归

修改（2 个，并存不替换）：
- `Aubade/Features/Recognition/Parsing/MockTransactionParser.swift`：`Behavior` 加 `screenshotSample`；parse() 加对应 case（88.50/支出/星巴克/食）
- `AubadeTests/MockParserTests.swift`：补 `.screenshotSample` 返回值断言

（Screenshot/ 子目录经 PBXFileSystemSynchronizedRootGroup 自动纳入 target，无 pbxproj 改动。）

## 验证情况

- 编译 + 单测：iPhone 17 模拟器 Debug，`xcodebuild test` **19 个测试全绿 TEST SUCCEEDED**（新增 ScreenshotOCRProviderTests 4 + RecognitionEntryScreenshotTests 2 + MockParserTests 补 1；N03/N04 回归 RecognitionEntryVoiceTests 3 + VoiceProviderTests 6 无回归）。
- jflow-review：1/3 轮 PASS，两个独立只读子 agent（①iOS/Vision API 正确性+代码事实 ②TRD/PRD 守纪+范围边界）第 1 轮均零阻断。阻断项：无。
- 断言覆盖 PRD 验收 9：source=.screenshotAlbum、Decimal("88.50") 无浮点误差、rawText 带 `[截图识别]` 前缀且与纯 OCR 文本分离、imageRef=nil、provider 三态可区分、语音路径不被污染。

## 遗留风险和注意事项

- 真实 `VisionTextRecognizer` 无自动化单测（脱真图片设计使然，已确认约定 8）：真机「真付款截图 → Vision 本机 OCR → 真实 DeepSeek 解析 → 入账」链路留切片02 手动验收或真机自测，不阻塞节点门禁。
- 非阻断（不影响当前正确性）：①若日后切 Swift 6 complete concurrency，`cgImage` 捕获进 global 队列 @Sendable 闭包可能告警，届时可改 `VNImageRequestHandler(data:options:)` 把解码也移入后台；②`VNImageRequestHandler` 未传 orientation，截图场景可忽略，N06 若接相机来源图再评估；③mock 样例文本内时间(13:10)与 parser sampleOccurredAt(15:22) 不一致——因 mock 恒返定值不解析文本内时间，不影响断言。

## 下一次开发

1. 读取 `current.json.next_trd`，确认值仍为 `docs/design/nodes/n05-screenshot-album/02-album-picker-wiring-debug-trd.md`。
2. 读取该 TRD 同目录的 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `docs/design/nodes/n05-screenshot-album/02-album-picker-wiring-debug-trd.md`，只实现该 TRD 切片。

补充说明：
- 下一个 TRD：`docs/design/nodes/n05-screenshot-album/02-album-picker-wiring-debug-trd.md`（切片02：相册选图 + 说明卡 ScreenshotIntakeSheet + RecordTabView📷 接线 + PhotosPicker 选图→OCR→复用 N03 单一 fullScreenCover + OCR provider 注入 + DebugMenu 截图 mock 开关）。
- 下一步动作：`jflow-dev` 实现切片02。核心接缝照抄 N04 `VoiceRoute` 单一 `fullScreenCover(item:)`（RecordTabView.swift:7-16）与「经 TextRecognitionView 预置文本复用整页绕开 private RecognitionResultCard」手法。rawText 前缀 `[截图识别]\n` 拼接在切片02 的 RecordTabView（对齐 N04 voiceRawText，RecordTabView.swift:84-86）。
- 切片02 是 N05 最后一个切片，完成后需更新 DAG `docs/design/aubade-v1-dev-dag.md` 的 N05 状态，并找下一个可开发节点（N06 快捷指令后台入账依赖 N05 OCR 能力）。
- 切片01 消费方：切片02 注入 `VisionTextRecognizer`（生产）/`MockTextRecognizer`（DEBUG），调用 `recognizeText(in: Data)` 拿 OCR 文本 → `recognizeAndSave(text: ocr, source: .screenshotAlbum, rawText: "[截图识别]\n"+ocr)`。
