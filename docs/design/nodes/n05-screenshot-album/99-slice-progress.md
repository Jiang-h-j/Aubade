# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n05-screenshot-album/02-album-picker-wiring-debug-trd.md`
- 下一个 TRD：`全部完成`
- 更新时间：2026-07-15T15:57:39+08:00

## 上一次 TRD 开发

N05 切片02「相册选图 + 说明卡 + 入口接线 + 状态机 + DEBUG mock」——N05 最后一个切片。把切片01 的「图片→本机 OCR 文本」底座接成用户可用的截图记账入口：记账页📷入口（原占位）→ 无 Key 拦截 → 截图说明卡（快捷指令主入口讲解 + 两步指引 +「从相册选图」备选 +「演示」占位）→ PhotosPicker 免权限选图 → 本机 Vision OCR 出文本 → 复用 N03/N04 那整套「预置文本自动识别 → 入账(source=.screenshotAlbum) → 结果卡片/失败转手动」。DEBUG 补截图 mock 开关（成功/空/OCR 失败三态），模拟器无真图片也能走通全链路与降级。对 N03/N04 零签名改动、三入口 provider/parser 互不污染。

## 涉及文件和符号

新增（1 个）：
- `Aubade/Features/Recognition/Screenshot/ScreenshotIntakeSheet.swift`：说明卡 View（introHero 快捷指令讲解 + twoStepGuide 两步指引 + 「演示」占位 alert + PhotosPicker 免权限选图）+ `ScreenshotOCRPhase`（idle/recognizing/failed）局部状态机 + runOCR（loadTransferable→本机 OCR→成功回调 onRecognized/失败态可重选）+ 本机读字遮罩（视觉对齐 N03）+ empty/failed 两文案。provider 用 let（无状态，不照抄 N04 @State 持有）。

修改（2 个，扩展不替换）：
- `Aubade/Features/Record/RecordTabView.swift`：新增 `ScreenshotRoute`(intro/recognizing) enum（照抄 VoiceRoute 避坑范式）；📷入口 `:236` 从占位改真接线（无 Key 拦截→说明卡）；新增 `fullScreenCover(item: $screenshotRoute)` 驱动（intro 说明卡→recognizing 复用 TextRecognitionView source=.screenshotAlbum）；注入 `makeTextRecognizer()`(DEBUG MockTextRecognizer/Release VisionTextRecognizer)、`screenshotParser`(DEBUG .screenshotSample/Release DeepSeekClient)、`screenshotRawText`(`[截图识别]\n`前缀)；截图无 Key alert + Key sheet。**删除死代码**：四入口全接线后，`placeholderEntryTitle` state 与外层「敬请期待」alert 永不触发，已删（全项目零残留引用）。
- `Aubade/Debug/DebugMenuView.swift`：新增 `DebugScreenshotMockSettings`（key=debug.screenshotMockBehavior，与文本/语音各自独立）+ 「N05 调试（截图 OCR mock）」Picker Section（成功/空结果/OCR 失败）。

（Screenshot/ 子目录经 PBXFileSystemSynchronizedRootGroup 自动纳入 target，无 pbxproj / Info.plist 改动——PhotosPicker 免权限，不加 NSPhotoLibraryUsageDescription。）

## 验证情况

- 编译 + 单测：iPhone 17 模拟器 Debug，`xcodebuild test` **114 个测试全绿 TEST SUCCEEDED**（切片01 ScreenshotOCRProviderTests 4 + VoiceProviderTests 6 等无回归）；采纳评审非阻断建议微调后 `xcodebuild build` **BUILD SUCCEEDED**。本切片以 UI/接线为主，按 TRD §262 不新增脱 View 单测（UI 状态机与转场靠 DEBUG mock 端到端人工走查 + 切片01 单测覆盖 source=.screenshotAlbum/provider 分支）。
- jflow-review：**2 轮，第 1 轮即 PASS，零阻断**。两个独立只读子 agent：①iOS/SwiftUI/Vision/PhotosUI API 正确性 + 代码事实——PhotosPicker 免授权选图、单一 fullScreenCover(item:) 三 cover 互斥不同帧冲突、@MainActor 并发无阻塞无双 resume、OCR 状态机复位可重选、所有引用符号/行号/签名属实；②守纪 + PRD 覆盖 + 范围边界——严格落在 TRD 范围未越界 N06/N07、验收 1/2/3/5/6/7/8/10 全覆盖（验收 4 权限被拒因 PhotosPicker 免权限合理划出、验收 9 单测在切片01）、三套 mock/parser 独立 @AppStorage key 互不污染、零签名改动、死代码删除安全、无过度设计。阻断项：无。
- 采纳的非阻断微调（行为等价/可读性，不影响 PASS）：①`ocrFailedBinding` 复位路径唯一化（原 set 闭包与 alert「好」按钮都置 idle，改为仅 set 负责）；②补 provider 无状态注释、三 cover 互斥约束注释。

## 遗留风险和注意事项

- 真实链路未自动化（脱真图片设计使然，已确认约定 8）：真机「真付款截图 → Vision 本机 OCR → 真实 DeepSeek 解析 → 入账(截图相册)」端到端留用户真机自测，不阻塞节点门禁。模拟器 DEBUG mock 恒返定值（88.5/星巴克/食）可肉眼走通全链路 + 三态降级。
- 非阻断（不影响当前正确性）：①Swift 6 complete concurrency 下 `VisionTextRecognizer` 的 cgImage 跨 DispatchQueue.global 捕获、`makeTextRecognizer()` 构造 @MainActor mock 可能告警（切片01 遗留，与 N04 makeVoiceTranscriber 同构，当前 Swift 5 模式无碍）；②loadTransferable 超大原图瞬时内存，当前截图尺寸无碍，N06 若接任意相册图再评估。
- DEBUG 下走截图 mock 仍需在相册真选一张图触发 .onChange（mock 忽略图片内容恒返定值）。

## 下一次开发

全部 TRD 已完成。下一次若继续，请从 PRD 验收标准和最终验证情况开始检查。

补充说明：
**N05 全部切片已完成**（切片01 provider 底座 + 切片02 相册选图接线）。下一步是节点收尾 + 找下一节点：

1. 更新 DAG `docs/design/aubade-v1-dev-dag.md`：把 N05 节点状态标为完成。
2. 找下一个可开发节点：**N06 快捷指令后台入账**（依赖 N05 OCR 能力，已满足——切片01 的 `TextRecognizing`/`VisionTextRecognizer` 脱 View 可被 N06 后台链路独立调用；本切片「演示」按钮仅占位，后台链路属 N06）。
3. `next_action` 指向生成 N06 PRD（走 jflow-start 或对应节点 PRD 流程）。

提交：本切片改动在分支 `feat/n05`（切片01 commit b09be90 已在此分支），沿用不新开分支。
