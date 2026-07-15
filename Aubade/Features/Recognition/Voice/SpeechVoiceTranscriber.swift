import Foundation
import Speech
import AVFoundation

/// 真实「按住说话 → 本机转中文文字」实现（切片 01 只有协议 + mock）。
/// 强制 requiresOnDeviceRecognition：语音绝不离开设备；本机不支持即降级，不回退云端。
/// 权限在首次 start() 内申请（进面板不弹）；录音最长 60s 自动收尾。
@MainActor
final class SpeechVoiceTranscriber: VoiceTranscribing {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    private var autoStopWork: DispatchWorkItem?
    private var tapInstalled = false

    /// 最终转写收敛信号：识别器回调 isFinal/error 时置位；finish() 据此取文本。
    private var finalReceived = false
    private var finalContinuation: CheckedContinuation<String, Never>?

    /// PRD §5 确认项 10：单次录音最长 60s，到点自动收尾。
    private static let maxDuration: TimeInterval = 60
    /// 最终识别回调的有限等待上限，防回调不来时挂起。
    /// 长录音 endAudio() 后 on-device 引擎收敛需数秒，取 8s 让正常路径走 isFinal 回调、不误读空文本。
    private static let finalWaitTimeout: TimeInterval = 8

    // MARK: - VoiceTranscribing

    func start() async throws {
        // 0) 重入防御：上一轮未 finish/cancel 就再 start，先复位采音与 task，避免 tap 重装崩溃/task 泄漏
        stopAudioCapture()
        cleanup()
        // 1) 权限：首次按下录音才申请（进面板不弹）
        guard await Self.ensureSpeechAuthorized() else { throw VoiceTranscribeError.speechDenied }
        guard await Self.ensureMicrophoneAuthorized() else { throw VoiceTranscribeError.microphoneDenied }
        // 2) 本机识别可用性（隐私边界：不回退云端）
        guard let recognizer, recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            throw VoiceTranscribeError.onDeviceUnavailable
        }
        // 3) 音频会话 + 请求（强制 on-device）——起动失败归为 .failed
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true          // 语音不外传
            request.shouldReportPartialResults = false          // MVP 不做实时转写
            self.request = request
            latestTranscript = ""
            finalReceived = false

            let input = audioEngine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [request] buffer, _ in
                // 实时音频线程回调：捕获局部 request 常量（非 @MainActor 的 self.request），append 允许跨线程
                request.append(buffer)
            }
            tapInstalled = true
            task = recognizer.recognitionTask(with: request) { result, error in
                // 回调可能在任意线程：仅取值，hop 回 main 更新状态
                let transcript = result?.bestTranscription.formattedString
                let done = (result?.isFinal ?? false) || error != nil
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let transcript { self.latestTranscript = transcript }
                    if done { self.signalFinal() }
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            stopAudioCapture()
            cleanup()
            throw VoiceTranscribeError.failed
        }

        // 4) 60s 自动收尾：仅停采音（幂等），转出文本仍由 finish() 取
        let work = DispatchWorkItem { [weak self] in self?.stopAudioCapture() }
        autoStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxDuration, execute: work)
    }

    func finish() async throws -> String {
        stopAudioCapture()
        request?.endAudio()
        // 等最终识别回调收敛（on-device 通常快；有限等待避免早读空/挂起）
        let text = await waitForFinalTranscript()
        cleanup()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VoiceTranscribeError.empty }
        return trimmed
    }

    func cancel() {
        task?.cancel()
        stopAudioCapture()
        signalFinal()   // 解脱任何正在等待的 finish（防御，正常单线程串行不会并发）
        cleanup()
    }

    // MARK: - 私有

    private func stopAudioCapture() {
        autoStopWork?.cancel(); autoStopWork = nil
        if audioEngine.isRunning { audioEngine.stop() }
        // removeTap 与 isRunning 解耦：起 engine 失败时 tap 已装但 engine 未跑，仍须移除，否则重试 installTap 崩溃
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func cleanup() {
        task = nil; request = nil
    }

    /// 有限等待最终转写收敛：已收敛直接返回；否则挂起等回调 signalFinal 或超时兜底读 latestTranscript。
    private func waitForFinalTranscript() async -> String {
        if finalReceived { return latestTranscript }
        return await withCheckedContinuation { cont in
            finalContinuation = cont
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.finalWaitTimeout) { [weak self] in
                self?.signalFinal()   // 超时兜底：读当前 latestTranscript
            }
        }
    }

    /// 置位收敛并 resume 等待者（continuation 只 resume 一次，由 nil 化保证幂等）。
    private func signalFinal() {
        finalReceived = true
        if let cont = finalContinuation {
            finalContinuation = nil
            cont.resume(returning: latestTranscript)
        }
    }

    // MARK: - 权限（首次按下录音申请；iOS 17 单分支）

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
