# TRD 切片进度

- 最近完成 TRD：`无（TRD 刚生成，尚未进入开发）`
- 下一个 TRD：`docs/design/nodes/n04-voice-capture/01-voice-provider-source-trd.md`
- 更新时间：2026-07-14T22:50:00+08:00

## 当前阶段

N04 语音记账的 TRD 已拆成 3 个单一职责切片并写完文档，**尚未开始编码**。等待 TRD 用户评审通过后，从切片 01 进入 `jflow-dev`。

## 切片清单与顺序

1. **01 语音转文字 provider 底座 + `recognizeAndSave` 参数化**（纯逻辑，脱 UI/硬件，可全单测）——`docs/design/nodes/n04-voice-capture/01-voice-provider-source-trd.md`
2. **02 真实 SFSpeech provider + 权限申请与降级**（真机系统 API + Info.plist）——`docs/design/nodes/n04-voice-capture/02-speech-provider-permission-trd.md`
3. **03 语音面板 UI + 状态机 + 入口接线 + 结果卡片复用 + DEBUG mock**（可用闭环 + 模拟器 mock 验收）——`docs/design/nodes/n04-voice-capture/03-voice-panel-wiring-debug-trd.md`

## 关键设计决策（开发时须遵守）

- **对 N03 的签名改动仅两处、均向后兼容**：(a) `recognizeAndSave` 加 `source: = .text`、`rawText: = nil`（切片 01）;(b) `TextRecognitionView` 加 `presetText`/`source`/`rawTextOverride`（切片 03，带默认值）。N03 现有调用零改。除此不改 `LedgerStore`/`RecognitionResultCard`/`TransactionEditor` 签名。
- **核心接缝 = 复用而非提升可见性**：N03 `RecognitionResultCard` 是 `private struct`（`TextRecognitionView.swift:249`）。切片 03 **不**把它提为 public，而是给 `TextRecognitionView` 加 `presetText`/`source`/`rawTextOverride`（默认值向后兼容），让语音转出文本后复用整个文本识别成功/失败/结果卡片链路。
- **rawText 前缀分离**：parse 收纯口语（真实 DeepSeek 不吞前缀），落库 `rawText` = `[语音转文字]\n"<口语>"`；靠切片 01 `rawText ?? text` 把 parse 输入与落库原文分开。
- **验收定值来自新增 `MockTransactionParser.voiceSample`（20/支出/"行"）**，与 N03 `.success`（256/京东/其他）并存不替换。
- **权限 API 走 iOS17 单分支**（部署目标 17.0）：麦克风用 `AVAudioApplication.requestRecordPermission`，不写 iOS16 前兜底。
- **强制 on-device 不外传**：`requiresOnDeviceRecognition = true` + 先 `supportsOnDeviceRecognition` guard，不回退云端。

## 待开发涉及文件（预计）

新增：
- `Aubade/Features/Recognition/Voice/VoiceTranscribing.swift`（协议 + 错误，切片 01）
- `Aubade/Features/Recognition/Voice/MockVoiceTranscriber.swift`（切片 01）
- `Aubade/Features/Recognition/Voice/SpeechVoiceTranscriber.swift`（切片 02）
- `Aubade/Features/Recognition/Voice/VoiceCaptureView.swift`（切片 03）
- `AubadeTests/VoiceProviderTests.swift` / `RecognitionEntryVoiceTests.swift`（切片 01）

改动：
- `TextRecognitionView.swift`（`recognizeAndSave` 参数化 [01]；`TextRecognitionView` 加预置文本自动识别 [03]）
- `MockTransactionParser.swift`（`.voiceSample` [01]）
- `RecordTabView.swift`（🎤 接线 + provider 注入 + 成功转场 [03]）
- `DebugMenuView.swift`（语音 mock 开关 [03]）
- `Aubade.xcodeproj/project.pbxproj`（新文件登记 + Info.plist UsageDescription [02]）

未改：`LedgerStore.createTransaction` 签名、`RecognitionResultCard`/`TransactionEditor` 签名、`RecognitionError`、N01/N02/N03 既有行为。

## 验证情况

尚未开发，无验证记录。各切片验证点见对应 TRD「验证点」章节。可观察验收以 DEBUG mock 端到端 + 切片 01 单测为准（PRD 已确认约定 6），真机真麦克风 + 真实 Key 为用户后续自测。

## 下一次开发

TRD 用户评审通过后，从切片 01 开始 `jflow-dev`：先落 provider 协议 + mock + `recognizeAndSave` 参数化 + 语音 mock 定值 + 单测（纯逻辑，风险最低），再切片 02（真实 SFSpeech + 权限），最后切片 03（面板 UI + 接线 + 结果卡片复用 + DEBUG 开关）。
