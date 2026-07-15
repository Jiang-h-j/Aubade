# TRD 切片进度

- 最近完成 TRD：`无（TRD 刚生成，尚未进入开发）`
- 下一个 TRD：`docs/design/nodes/n05-screenshot-album/01-ocr-provider-source-trd.md`
- 更新时间：2026-07-15T14:40:00+08:00

## TRD 生成情况

N05 截图·相册选图 TRD 已生成，拆 **2 个单一职责切片**（比 N04 的三片轻——省掉 N04 切片01 的 `recognizeAndSave`/`TextRecognitionView` 参数化底座，N04 已带默认值完成、N05 零签名改动；且用户拍板 PhotosPicker 免权限，省掉相册权限申请/被拒降级/Info.plist key 的复杂度）。

- **切片 01（`01-ocr-provider-source-trd.md`）**：Vision OCR provider 底座 + 截图 mock 定值。纯逻辑地基、零 UI、脱真图片可测。`TextRecognizing` 协议 + `TextRecognizeError`（empty/failed）+ 真实 `VisionTextRecognizer`（`VNRecognizeTextRequest` 中文本机 OCR）+ `MockTextRecognizer`（三态）+ `MockTransactionParser.screenshotSample`（88.5/食/星巴克）+ 全分支单测 + `source=.screenshotAlbum` 落库单测。依赖 N03/N04。覆盖 PRD 验收 9。
- **切片 02（`02-album-picker-wiring-debug-trd.md`）**：相册选图 + 说明卡 + 入口接线 + 状态机 + DEBUG mock。`RecordTabView`📷 接线（无 Key 拦截前置）+ 截图说明卡 `ScreenshotIntakeSheet`（快捷指令讲解 + 两步指引 +「从相册选图」+「演示」占位）+ `PhotosPicker` 选图 → OCR → `.recognizing(ocrText)` 复用 N03（照抄 `VoiceRoute` 单一 `fullScreenCover(item:)`）+ OCR provider 注入 + DebugMenu 截图 mock 开关。依赖切片 01。覆盖 PRD 验收 1/2/3/5/6/7/8/10。

## 关键设计决策（写 TRD 时定）

1. **相册选图用 SwiftUI `PhotosPicker`（免权限），非 `PHPhotoLibrary` 全库授权**（用户拍板）：选图器独立进程、免相册授权、免 `NSPhotoLibraryUsageDescription`。因此 PRD §2/§5 的"相册权限申请 + 被拒降级"、验收点 4、Info.plist key **本节点降为不适用**（不是遗漏，是实现方式使其无从发生）——已在 `00-index.md` 的"对 PRD 的偏离说明"表格显式记录。前台降级只剩：用户取消选图 / OCR 空结果 / OCR 失败。
2. **`VNRecognizeTextRequest` 无 `requiresOnDeviceRecognition` 属性**（区别于 N04 Speech）：Vision 文本识别是纯本机能力、无上云路径，图片天然不外传，无需显式"强制本机"开关。已在 index 约束3 与切片01 §2 写准此 API 事实。
3. **OCR provider 契约入参选 `Data`（非 `UIImage`/`CGImage`）**：PhotosPicker 经 `loadTransferable(type: Data.self)` 直接拿 `Data`，N06 后台收到的也是图片 `Data`，以 `Data` 为边界两个调用方都不必先转 `UIImage`。provider 脱 View、脱相册 UI 可独立调用——为 N06 复用铺路。
4. **对 N03/N04 零签名改动**：`recognizeAndSave`（`TextRecognitionView.swift:18-24`）与 `TextRecognitionView`（`:50-52`）N04 已参数化完成，N05 只新增 `source: .screenshotAlbum` 调用方 + `MockTransactionParser.screenshotSample` 定值（并存不改既有）。核心论证经逐行源码核对属实。
5. **截图 mock 定值 88.5/支出/食/星巴克**（新增 `MockTransactionParser.screenshotSample`），与 N03 `.success`（256/京东）、N04 `.voiceSample`（20/行）并存不替换；`MockParserTests` 无 `Behavior` 全集断言，新增 case 不撞既有测试。
6. **rawText 前缀 `[截图识别]\n<OCR文本>`**（对齐 N04 `[语音转文字]` 与 demo `data.js:44`）：拼接在切片02 `RecordTabView.screenshotRawText`，parse 收纯 OCR 文本、落库带前缀，经 `recognizeAndSave` 的 `text`/`rawText` 分离。

## 写 TRD 时已核对的代码事实（全部属实）

- `recognizeAndSave` 的 `source: = .text`/`rawText: = nil` 默认值（`TextRecognitionView.swift:23-24`）；落库 `rawText ?? text`（`:38`）。
- `TextRecognitionView` 三入参 `presetText`/`source`/`rawTextOverride`（`:50-52`）+ `onAppear` 自动识别（`:165-170`，`hasAutoRecognized` 防重入）。
- `RecognitionResultCard` private（`:268`）——N04 已用"经 `TextRecognitionView` 预置文本复用整页"绕开，N05 照抄。
- `VoiceRoute` 单一 `fullScreenCover(item:)` 范式（`RecordTabView.swift:7-16`、驱动 `:122-138`）；📷 截图入口占位（`:167`）；N04 无 Key 拦截（`:168-175`）/provider 注入（`:60-80`）/敬请期待 alert（`:142-149`）。
- `VoiceTranscribing` provider 协议（`VoiceTranscribing.swift:14-23`）+ `MockVoiceTranscriber` 五态（含 `sampleSpokenText`）+ `VoiceProviderTests` 全集断言范式。
- `TransactionSource.screenshotAlbum`（`Enums.swift:14`，已存在）；`Transaction.imageRef`（`Transaction.swift:16`，本节点恒 nil）。
- `MockTransactionParser.Behavior`（`MockTransactionParser.swift:9`，success/voiceSample/…）+ `sampleOccurredAt`（`:13-21`）。
- `DebugVoiceMockSettings`（`DebugMenuView.swift:13-15`）+ 语音 mock Section（`:88-98`）范式。
- pbxproj `INFOPLIST_KEY_NSMicrophone/SpeechRecognition`（Debug `:332-333`/Release `:361-362`，`GENERATE_INFOPLIST_FILE`）——本节点因 PhotosPicker 免权限不新增相册 key。
- `import Vision`/`Photos`/`PhotosPicker` 在 `Aubade/` 下零命中（净新增）。
- demo `openScreenshotSheet`（`app.js:266-283`）+ `MOCK_RECOGNIZE.screenshot`（`data.js:43`，88.5/支出/食/星巴克/`raw` 带 `[截图本地识别文字]` 语义）。

## 待验收（进入开发后逐片验证）

- 编译：iPhone 模拟器 `xcodebuild build` Debug。
- 单测：切片01 `ScreenshotOCRProviderTests`（provider 三态 + 全集断言）+ `RecognitionEntryScreenshotTests`（`source=.screenshotAlbum` 落库/前缀 rawText/Decimal）+ `MockParserTests` 补 `.screenshotSample`；N03/N04 无回归。
- mock 端到端（模拟器）：切片02 点📷 → 说明卡 → 从相册选图（mock=成功）→ 本机读字遮罩 → 识别中 → 结果卡片（88.5/食/星巴克/截图相册/`[截图识别]` 前缀）；空/失败/无 Key 各降级。

## 下一次开发

按 TRD 切片顺序，从 `01-ocr-provider-source-trd.md` 开始（`jflow-dev`）。

补充说明：
1. **本 feature 首次提交前需询问分支**：current 分支 `feat/n05`（已在此分支），但按 Jflow 规则本 feature 首次提交前需向用户确认「直接提交当前分支 `feat/n05` 还是新开 feature 分支」，用户明确后本 feature 后续切片沿用。commit 信息遵循 `type[scope]:`。
2. **TRD 需先通过用户评审**：TRD 自评审 PASS 后设 `pending_user_review: trd`，等用户明确「TRD 评审通过」才提交推送并进入切片01 开发。
3. **N05 是 DAG 第六节点**：完成后需更新开发 DAG `docs/design/aubade-v1-dev-dag.md` 的 N05 状态，并找下一个可开发节点（N06 快捷指令后台入账依赖 N05 的 OCR 能力，可能是下一个）。
4. **真机自测（可选、不阻塞）**：模拟器无真截图走 mock；真机"选真付款截图 → Vision 本机 OCR 出文本 → 真实 DeepSeek 解析 → 入账"链路留有真机时验，节点门禁走 mock 不受阻。
