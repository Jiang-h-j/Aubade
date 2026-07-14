# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n04-voice-capture/01-voice-provider-source-trd.md`
- 下一个 TRD：`docs/design/nodes/n04-voice-capture/02-speech-provider-permission-trd.md`
- 更新时间：2026-07-15T00:10:28+08:00

## 上一次 TRD 开发

N04 语音记账切片01「语音转文字 provider 底座 + recognizeAndSave 参数化」纯逻辑地基完成(零 UI、脱真麦克风、可全单测):
- 新增 `VoiceTranscribing` 协议(@MainActor,start/finish/cancel 三时点)+ `VoiceTranscribeError`(五 case 可区分:microphoneDenied/speechDenied/onDeviceUnavailable/empty/failed),对齐 N03 `TransactionParsing`/`RecognitionError` 范式。
- 新增 `MockVoiceTranscriber`(Behavior 五态:success/empty/microphoneDenied/speechDenied/onDeviceUnavailable;授权/能力失败在 start 抛、empty 在 finish 抛、success 返 "打车花了 20 块")。
- `RecognitionEntry.recognizeAndSave` 向后兼容参数化:尾加 `source: TransactionSource = .text`、`rawText: String? = nil`,拆开 parse 输入(纯口语)与落库原文(带前缀);落库 `source: source`、`rawText: rawText ?? text`。N03 唯一调用方零改、逐字节等价。
- `MockTransactionParser.Behavior` 追加 `.voiceSample`(金额 20 / 支出 / 分类"行",对齐 demo data.js:45),与 `.success`(256/京东)并存不替换。

## 涉及文件和符号

新增:
- `Aubade/Features/Recognition/Voice/VoiceTranscribing.swift`(协议 `VoiceTranscribing` + 错误 `VoiceTranscribeError`)
- `Aubade/Features/Recognition/Voice/MockVoiceTranscriber.swift`(`MockVoiceTranscriber` + `Behavior` 五态 + `sampleSpokenText`)
- `AubadeTests/VoiceProviderTests.swift`(mock 五态 + 错误集合守卫)
- `AubadeTests/RecognitionEntryVoiceTests.swift`(source=.voice 落库 / rawText 前缀分离 / nil 回落 / 向后兼容默认 .text)

改动:
- `Aubade/Features/Recognition/TextRecognitionView.swift`(`RecognitionEntry.recognizeAndSave` 尾加 `source`/`rawText` 带默认值参数)
- `Aubade/Features/Recognition/Parsing/MockTransactionParser.swift`(`Behavior` 加 `.voiceSample` + parse 分支)
- `docs/design/nodes/n04-voice-capture/01-voice-provider-source-trd.md`(四态→五态笔误修正)

未改(守纪):`LedgerStore.createTransaction` 签名、`RecognitionError`、`TransactionEditor`/`RecognitionResultCard`、N01/N02/N03 既有行为。

## 验证情况

- **单测**:iPhone 17 模拟器,`VoiceProviderTests`(6)+`RecognitionEntryVoiceTests`(3)+ 防回归 `RecognitionEntryTests`(4)+`MockParserTests`(3)= 16 全绿;吸收评审建议增强测试后重跑新增 9 个仍全绿。编译通过,新增 .swift 经同步文件夹自动纳入 target。
- **jflow-review**:1/3 轮 PASS,零阻断。两只读子 agent 独立评审:①向后兼容与 TRD 守纪五项全满足(签名仅尾加带默认值参数、N03 调用零改、未越界、`.voiceSample` 追加不替换、无 SFSpeech/UI/权限代码、失败不落脏账不变量保持);②协议契约自洽、测试断言能真捕获回归(rawText 前缀双向断言、Decimal 精确)。吸收 3 条非阻断增强:Behavior 集合断言替脆弱 count、voiceSample 用例补金额/分类断言、TRD 文档笔误修正。

## 遗留风险和注意事项

- **切片02/03 待接**:本片 provider 只有协议 + mock,真实 `SFSpeechRecognizer`/`AVAudioEngine` + 权限 + on-device + 60s 在切片02;面板 UI + 状态机 + `RecordTabView` 🎤 接线 + 结果卡片复用(扩展 `TextRecognitionView` 加 presetText/rawTextOverride)+ DEBUG 语音 mock 开关在切片03。
- **分层盲区(评审记录,非阻断)**:`MockTransactionParser.parse` 忽略 text 入参,故"recognizeAndSave 喂纯口语而非带前缀原文给 parser"这一点本层测试无法证明;真正拼前缀在 View 层(切片03),届时端到端验收补齐。
- **本片首次提交前需确认分支**:current 分支 feat/n04;首次提交前按 Jflow 规则询问用户「直接提交当前分支还是新开 feature 分支」。

## 下一次开发

1. 读取 `current.json.next_trd`，确认值仍为 `docs/design/nodes/n04-voice-capture/02-speech-provider-permission-trd.md`。
2. 读取该 TRD 同目录的 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `docs/design/nodes/n04-voice-capture/02-speech-provider-permission-trd.md`，只实现该 TRD 切片。

补充说明：
- 文件:`docs/design/nodes/n04-voice-capture/02-speech-provider-permission-trd.md`
- TRD:N04 切片02「真实 SFSpeech provider + 权限申请与降级」
- 下一步动作:进入 `jflow-dev` 实现切片02——`SpeechVoiceTranscriber`(真实 `SFSpeechRecognizer(zh-CN)` + `AVAudioEngine`,`requiresOnDeviceRecognition=true` 且先 check `supportsOnDeviceRecognition`、60s 上限)+ 麦克风/语音识别权限(首次按下录音申请,iOS17 单分支 `AVAudioApplication.requestRecordPermission`)+ 被拒/不可用降级 + Info.plist UsageDescription(需改 project.pbxproj)。它只实现切片01 的 `VoiceTranscribing` 协议,不接入口,对既有链路零影响。
