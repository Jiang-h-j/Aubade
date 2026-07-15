# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n04-voice-capture/02-speech-provider-permission-trd.md`
- 下一个 TRD：`docs/design/nodes/n04-voice-capture/03-voice-panel-wiring-debug-trd.md`
- 更新时间：2026-07-15T10:40:41+08:00

## 上一次 TRD 开发

N04 语音记账切片02「真实 SFSpeech 本机转文字 provider + 权限申请与降级 + Info.plist 用途说明」完成(纯系统集成层,零 UI,不接入口):
- 新增 `SpeechVoiceTranscriber: VoiceTranscribing`——真实 `SFSpeechRecognizer(zh-CN)` + `AVAudioEngine`,`requiresOnDeviceRecognition=true` 且先 check `supportsOnDeviceRecognition`/`isAvailable`(隐私边界:本机不支持即抛 `.onDeviceUnavailable`,不回退云端),`shouldReportPartialResults=false`。
- 权限封装进 `start()`:先语音识别(`SFSpeechRecognizer.requestAuthorization`)后麦克风(iOS17 单分支 `AVAudioApplication.requestRecordPermission`),notDetermined 弹系统窗、denied/restricted 直接抛对应 `VoiceTranscribeError`;仅进面板不调 start 故不弹权限。
- 60s 上限:provider 内 `asyncAfter` 到点只 `stopAudioCapture()`(幂等停采音),不驱动 UI、不主动出文本;面板 60s 计时留切片03。
- `finish()` 经 `waitForFinalTranscript`(continuation + 8s 超时兜底)取最终转写、trim 后空则抛 `.empty`;`finish()`/`cancel()` 都走 `stopAudioCapture()`(移 tap、停 engine、setActive(false))+ `cleanup()`(释放 task/request)。
- pbxproj 两个 build config(Debug/Release)各新增 `INFOPLIST_KEY_NSMicrophoneUsageDescription`/`INFOPLIST_KEY_NSSpeechRecognitionUsageDescription`,文案声明"语音记账、本机识别、语音不离开设备"。

## 涉及文件和符号

新增:
- `Aubade/Features/Recognition/Voice/SpeechVoiceTranscriber.swift`(`SpeechVoiceTranscriber` 满足 `VoiceTranscribing`,@MainActor)

改动:
- `Aubade.xcodeproj/project.pbxproj`(Debug :332-333、Release :361-362 两条 INFOPLIST_KEY UsageDescription)
- `docs/design/nodes/n04-voice-capture/02-speech-provider-permission-trd.md`(同步 waitForFinalTranscript 超时 1.5s→8s 说明、补充重入与 tap 生命周期要点,消除文档与实现漂移)

未改(守纪):切片01 的 `VoiceTranscribing`/`VoiceTranscribeError`/`MockVoiceTranscriber` 契约、`recognizeAndSave`、`LedgerStore.createTransaction`、`TextRecognitionView`/`RecognitionResultCard`、N01/N02/N03 既有行为。真实 provider 无生产代码调用方(切片03才在 Release 分支注入),对既有链路零影响。

## 验证情况

- **编译**:iPhone 17 模拟器 `xcodebuild build`,首次通过;第1轮评审修复后重新编译仍 BUILD SUCCEEDED。`import Speech`/`AVFoundation` 通过,`SpeechVoiceTranscriber` 满足 `VoiceTranscribing`(@MainActor 一致)。
- **隐私核对**:`requiresOnDeviceRecognition=true` 唯一,全文件无 `=false` 云端回退,无音频/文件上传。
- **jflow-review**:2/3 轮 PASS。第1轮双只读子 agent 独立评审——①系统API/并发角度 FAIL,发现 3 项:removeTap 被 isRunning 错误守卫(起 engine 失败后 tap 残留、重试 installTap 崩溃)、start() 无重入守卫(重复调用重装 tap 崩溃+task 泄漏)、1.5s 超时对长录音误报 .empty;②守纪/PRD 角度 PASS(范围守纪、零影响、on-device 隐私边界、权限时机、60s、Info.plist 全达标),同样把 1.5s 超时列为切片03注入前必修头号项。已修复全部 3 项:removeTap 用 tapInstalled 标志与 isRunning 解耦、start() 开头 stopAudioCapture+cleanup 复位、超时 1.5s→8s、附带 tap 闭包捕获局部 request 常量消除数据竞争。修复后重新编译通过,第2轮人工复核三处修复落地、无遗漏,守 TRD 范围(保持 on-device 强制、partial=false),PASS 零阻断。
- **未写脱环境单测**:真实 provider 依赖真机+真麦克风+系统授权(对齐 PRD 约定6/TRD:真机录音转文字为可选真机自测、不阻塞节点);其分支语义已由切片01 `MockVoiceTranscriber` 单测覆盖,切片03 用 mock 走 UI 全路径。

## 遗留风险和注意事项

- **真机自测未做(可选,不阻塞)**:模拟器无麦克风,"真机首次按下依次弹语音+麦克风授权→说话→finish 返回文本→断网仍能本机转出→关权限抛 denied 不崩溃"这条真机链路尚未实跑,留待有真机时验;节点门禁走 mock 不受阻。
- **超时 8s 是经验值**:长录音 endAudio 后 on-device 收敛时间因设备而异,8s 为覆盖接近60s录音的兜底;若真机自测发现极慢设备仍偶发 .empty,可再上调或改内部 partial 累积(需同步 TRD)。
- **60s 双计时职责**:provider 侧计时只是"面板漏调也不会一直录"的兜底;切片03 必须实现面板自己的 60s 计时 + UI 呈现 + 到点触发等价 finish()。
- **本 feature 首次提交前需确认分支**:current 分支 feat/n04;按 Jflow 规则首次提交前询问用户「直接提交当前分支还是新开 feature 分支」,尚未提交。

## 下一次开发

1. 读取 `current.json.next_trd`，确认值仍为 `docs/design/nodes/n04-voice-capture/03-voice-panel-wiring-debug-trd.md`。
2. 读取该 TRD 同目录的 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `docs/design/nodes/n04-voice-capture/03-voice-panel-wiring-debug-trd.md`，只实现该 TRD 切片。

补充说明：
- 文件:`docs/design/nodes/n04-voice-capture/03-*.md`(切片03,当前 TRD 目录下第三片)
- TRD:N04 切片03「语音面板 UI + 状态机 + RecordTabView 🎤 接线 + 结果卡片复用 + DEBUG 语音 mock 开关」
- 下一步动作:切片02 完成后 `next_trd` 应指向切片03。进入 `jflow-dev` 实现切片03——扩展 `TextRecognitionView` 加 presetText/rawTextOverride 复用结果卡片(而非提升 private 卡片可见性)、语音面板状态机(按住说话→识别中→结果/失败转手动带原文)、面板侧 60s 计时、`RecordTabView` 🎤 入口注入(Release 注入 `SpeechVoiceTranscriber`、DEBUG 可切 `MockVoiceTranscriber`)。切片03 Release 注入真实 provider 前,建议先真机自测切片02 的录音转文字链路。
