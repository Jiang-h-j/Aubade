# TRD 02 - 真实 SFSpeech 本机转文字 provider + 权限申请与降级

## 给用户看的摘要

这一片实现**真正调用 iPhone 语音识别**的那段代码(切片 01 只搭了协议和假实现)。它做四件事:

1. 用系统的 `SFSpeechRecognizer` + `AVAudioEngine` 实现"按住录音 → 在**本机**把中文语音转成文字",**强制本机识别、声音绝不离开手机**;录音最长 60 秒自动收尾。
2. **第一次按下录音键**时,才向系统申请麦克风和语音识别两项权限(不是一进面板就弹,避免打扰)。
3. 权限被拒、本机识别不支持、没说话——每种情况都给一句**明确的中文提示**、不崩溃不卡死,手动记账和文本识别照常能用。
4. 在 App 配置里写好两句权限用途说明(系统弹窗会显示),说清"用于语音记账、本机识别"。

做完这片,真机上"按住说话就能转出文字"这段就通了;把文字接到界面、记成账单在切片 03。本片仍可在**真机**上单独验证录音转文字,模拟器无麦克风则靠切片 01 的 mock。

## 本 TRD 负责什么

单一职责:**语音转文字契约 `VoiceTranscribing` 的真实系统实现 + 语音记账自身必需的权限申请与被拒降级 + Info.plist 用途说明**。

- 新增 `SpeechVoiceTranscriber: VoiceTranscribing`(真实 `SFSpeechRecognizer(zh-CN)` + `AVAudioEngine`,强制 `requiresOnDeviceRecognition`,60s 上限)。
- 权限申请封装进 `start()`:麦克风(`AVAudioApplication.requestRecordPermission`)+ 语音识别(`SFSpeechRecognizer.requestAuthorization`),被拒/受限抛 `VoiceTranscribeError`。
- 先检查 `supportsOnDeviceRecognition`,不可用抛 `.onDeviceUnavailable`(不回退云端)。
- Info.plist 新增 `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription`(经 `INFOPLIST_KEY_*` build setting)。

不含语音面板 UI、`RecordTabView` 接线、DEBUG 开关、状态机(切片 03);不含 provider 协议/mock/落库(切片 01)。

## 当前代码事实与上下游

- **切片 01 已交付契约**:`VoiceTranscribing`(`@MainActor` 协议,`start() async throws` / `finish() async throws -> String` / `cancel()`)、`VoiceTranscribeError`(`microphoneDenied/speechDenied/onDeviceUnavailable/empty/failed`),文件 `Aubade/Features/Recognition/Voice/VoiceTranscribing.swift`。本片新增真实实现放同目录。
- **项目当前无任何 OS 权限代码**:`import Speech`/`SFSpeech`/`AVAudioSession`/`AVAudioApplication`/`requestAuthorization`/`requiresOnDeviceRecognition` 在 `Aubade/` 下**零命中**——本片首次引入。可借鉴的仅 N03"前置 guard → 弹 alert 引导 → 主流程不受影响"的**交互范式**(`TextRecognitionView.swift:120-126/184-187`),非现成权限代码。
- **部署目标 iOS 17.0**（`Aubade.xcodeproj/project.pbxproj:255/311/334` `IPHONEOS_DEPLOYMENT_TARGET = 17.0`）——麦克风权限**直接用 iOS 17 `AVAudioApplication.requestRecordPermission`**,无需 iOS16 前 `AVAudioSession.requestRecordPermission` 分支(PRD §5 列了旧 API 作兜底,此处按实际部署目标单分支即可,更简)。
- **Info.plist 走 `GENERATE_INFOPLIST_FILE = YES`**（`project.pbxproj:328/355`），已有若干 `INFOPLIST_KEY_*` 键（`:329-333`）——新增 UsageDescription 沿用 `INFOPLIST_KEY_*` build setting 形式，无独立 .plist 文件。
- **无既有调用方**:真实 provider 是全新类型,本片不接入口(切片 03 才在 `RecordTabView` Release 分支注入 `SpeechVoiceTranscriber`),故本片对既有链路**零影响**。

## 设计方案

### 1. 真实实现 `SpeechVoiceTranscriber`（新增 `Aubade/Features/Recognition/Voice/SpeechVoiceTranscriber.swift`）

```swift
import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechVoiceTranscriber: VoiceTranscribing {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    private var autoStopWork: DispatchWorkItem?

    private static let maxDuration: TimeInterval = 60   // PRD 已确认约定 10

    // MARK: - VoiceTranscribing

    func start() async throws {
        // 1) 权限：首次按下录音才申请（PRD 已确认约定 9）
        guard await Self.ensureSpeechAuthorized() else { throw VoiceTranscribeError.speechDenied }
        guard await Self.ensureMicrophoneAuthorized() else { throw VoiceTranscribeError.microphoneDenied }
        // 2) 本机识别可用性（隐私边界：不回退云端）
        guard let recognizer, recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            throw VoiceTranscribeError.onDeviceUnavailable
        }
        // 3) 音频会话 + 请求（强制 on-device）
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true          // 语音不外传
        request.shouldReportPartialResults = false          // MVP 不做实时转写
        self.request = request
        latestTranscript = ""

        let input = audioEngine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            if let result { self?.latestTranscript = result.bestTranscription.formattedString }
        }
        audioEngine.prepare()
        try audioEngine.start()

        // 4) 60s 自动收尾：仅停采音（停 tap/engine），转出文本仍由 finish() 取
        let work = DispatchWorkItem { [weak self] in self?.stopAudioCapture() }
        autoStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxDuration, execute: work)
    }

    func finish() async throws -> String {
        stopAudioCapture()
        request?.endAudio()
        // 等最终识别回调收敛（on-device 通常快；给有限等待，避免早读空）
        let text = await waitForFinalTranscript()
        cleanup()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VoiceTranscribeError.empty }
        return trimmed
    }

    func cancel() {
        task?.cancel()
        stopAudioCapture()
        cleanup()
    }

    // MARK: - 私有

    private func stopAudioCapture() {
        autoStopWork?.cancel(); autoStopWork = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func cleanup() {
        task = nil; request = nil
    }

    /// 有限等待最终转写收敛（轮询 latestTranscript 稳定或 task 结束；上限 ~1.5s 防挂起）。
    private func waitForFinalTranscript() async -> String { /* 见"实现要点"，用 task 完成/超时二选一 */ }

    // MARK: - 权限（首次按下录音申请）

    private static func ensureSpeechAuthorized() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
            }
        default: return false   // denied / restricted
        }
    }

    private static func ensureMicrophoneAuthorized() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .undetermined:
            return await withCheckedContinuation { cont in
                AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
            }
        default: return false   // denied
        }
    }
}
```

### 实现要点（把 iOS 系统 API 焊准）

- **强制本机、不外传**:`request.requiresOnDeviceRecognition = true` + 先 `supportsOnDeviceRecognition` guard(PRD 验收 8、已确认约定 1)。中文本机不支持 → `.onDeviceUnavailable`,**不设 `requiresOnDeviceRecognition=false` 回退云端**。
- **权限顺序**:先语音识别再麦克风(任一 `notDetermined` 触发系统弹窗,`denied/restricted` 直接返回 false → `start()` 抛对应 error,不 `installTap`、不起 engine)。仅进面板不调 `start()`,故不弹权限(PRD 已确认约定 9)。
- **60s 上限(职责切分)**:provider 内 `asyncAfter` 到点只 `stopAudioCapture()`(停采音,幂等),**不驱动 UI、不主动出文本**——provider 不持有 UI 回调。面板(切片 03)**另设自己的 60s 计时**,到点触发与"松手"等价的 `finish()` 流转取文本。两处计时几乎同时到点:provider 侧先停采音(防继续录音),面板侧 `finish()` 时 `stopAudioCapture()` 幂等再调无副作用,`finish()` 照常从已收敛的识别结果取文本。切片 03 需实现面板 60s 计时与 UI 呈现;provider 侧计时是"即使面板漏调也不会一直录"的兜底。
- **`waitForFinalTranscript`**:`shouldReportPartialResults=false` 时最终 result 经 recognitionTask 回调一次(`isFinal`/error);用 continuation 在该完成回调 resume,加 **~8s** 超时兜底(超时读 `latestTranscript`),防回调不来时挂起。**超时须足够长以覆盖接近 60s 长录音 `endAudio()` 后 on-device 引擎数秒收敛**——过短(如 1.5s)会在 `isFinal` 到来前先超时、读到空文本误报 `.empty`。**具体用 continuation+超时,不引第三方**。
- **重入与 tap 生命周期**:`start()` 开头先 `stopAudioCapture()`+`cleanup()` 复位(防未 finish/cancel 就重按导致 tap 重装崩溃/task 泄漏);`installTap` 后置 `tapInstalled=true`,`stopAudioCapture()` 里 `removeTap` **与 `isRunning` 解耦**、按 `tapInstalled` 无条件移除(起 engine 失败时 tap 已装而 engine 未跑,仍须移除,否则重试 `installTap` 崩溃)。
- **生命周期**:`finish()`/`cancel()` 都经 `stopAudioCapture()`(移除 tap、停 engine、`setActive(false)`)+ `cleanup()`(释放 task/request),避免 audio session 泄漏与 tap 重复安装崩溃。
- **`AVAudioSession` 归 `AVFoundation`**;`AVAudioApplication`(iOS17)亦在 `AVFoundation`,`import AVFoundation` 即可。

### 2. Info.plist 用途说明（改 `project.pbxproj` build settings）

在两个 build config（Debug/Release）的 `INFOPLIST_KEY_*` 段（`:328-333` 邻近）新增:

```
INFOPLIST_KEY_NSMicrophoneUsageDescription = "语音记账需要使用麦克风录制你的语音，用于在本机转成文字后记账。";
INFOPLIST_KEY_NSSpeechRecognitionUsageDescription = "语音记账在本机把你的语音转成文字，用于识别记账，语音不会离开你的设备。";
```

- 文案说明**用途=语音记账、本机识别、不外传**(PRD §5)。
- 走 `INFOPLIST_KEY_*` 与既有键一致，无需创建独立 Info.plist(保持 `GENERATE_INFOPLIST_FILE=YES`)。

## 修改点

| 文件 | 改动 | 类型 |
|---|---|---|
| `Aubade/Features/Recognition/Voice/SpeechVoiceTranscriber.swift` | 新增：真实 `VoiceTranscribing` 实现（SFSpeech+AVAudioEngine、权限、on-device、60s） | 新增文件 |
| `Aubade.xcodeproj/project.pbxproj` | 两个 build config 新增 `INFOPLIST_KEY_NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription` | 工程配置 |

（新源文件 `SpeechVoiceTranscriber.swift` 由同步文件夹自动纳入 target，无需手改 pbxproj；pbxproj 改动**仅为新增两条 `INFOPLIST_KEY_*`**。）

（本片真实实现依赖真机+真麦克风+系统授权，**不写脱环境单测**；provider 契约的分支单测已由切片 01 mock 覆盖，切片 03 用 mock 走 UI 全路径。真机录音转文字为可选真机自测，不阻塞节点——对齐 PRD 已确认约定 6。）

## 验证点

- **编译**:`import Speech`/`AVFoundation` 通过;`SpeechVoiceTranscriber` 满足 `VoiceTranscribing`(`@MainActor` 一致)。
- **真机自测(可选,不阻塞)**:真机首次按下录音 → 依次弹语音识别+麦克风系统授权;同意后说"打车花了 20 块" → `finish()` 返回含该文本;`requiresOnDeviceRecognition=true` 下断网仍能转出(本机)。
- **降级(真机)**:设置里关掉麦克风/语音识别权限 → `start()` 抛 `.microphoneDenied`/`.speechDenied`;不崩溃。
- **Info.plist**:系统授权弹窗显示上述中文用途说明。
- **隐私核对**:代码中 `requiresOnDeviceRecognition = true` 且无 `= false` 回退路径;无音频/文件上传。

## 不做什么

- **不做语音面板 UI、`RecordTabView` 接线、状态机、DEBUG 开关**（切片 03）——本片只交付可被注入的真实 provider。
- **不做 iOS16 前麦克风 API 分支**（`AVAudioSession.requestRecordPermission`）:部署目标 17.0,直接 `AVAudioApplication`,不为已不支持的系统写兜底。
- **不做实时转写 / partial results**:`shouldReportPartialResults = false`,MVP 只出最终文本（与切片 01 协议一致）。
- **不做权限统一收口 / 我的页权限状态 / 首次引导集中申请**（N07）——本片只在 `start()` 内做语音记账自身必需的一次申请。
- **不回退云端识别**：本机不可用即降级提示，`requiresOnDeviceRecognition` 恒 true（隐私边界）。
- **不写真实 provider 的脱环境单测**：其分支语义已由切片 01 `MockVoiceTranscriber` 单测覆盖；真实类依赖硬件与系统授权，真机自测为准。
