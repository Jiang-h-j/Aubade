import SwiftUI

/// 语音面板（原型 demo `openVoiceCapture` app.js:310）：🎤 大图标 + 「按住说话」+ 示例「打车花了 20 块」。
///
/// 职责边界：只负责"按住录音 → 松手 → 本机转出纯口语文本"这段。成功后经 `onRecognized` 把**纯口语**
/// 交回上层（RecordTabView），由上层切到复用 N03 的 `TextRecognitionView`（预置文本自动识别 → 结果卡片）；
/// 面板自身不入账、不弹结果卡片。权限/本机不可用/空结果各降级提示，不崩溃。
struct VoiceCaptureView: View {
    /// 面板局部状态机（对齐 RecognitionPhase 风格；成功不在本机停留，交上层复用 N03）。
    enum VoicePhase: Equatable {
        case idle           // 待按住
        case recording      // 按住录音中
        case transcribing   // 松手后本机转文字中
        case failed(VoiceTranscribeError)
    }

    // @State 持有：View 生命周期内单实例，父视图 body 重算不会换掉正在录音的 transcriber。
    @State private var transcriber: any VoiceTranscribing
    let onRecognized: (String) -> Void   // 成功回调：把纯口语文本交回上层驱动转场

    @Environment(\.dismiss) private var dismiss

    @State private var phase: VoicePhase = .idle
    @State private var startTask: Task<Void, Never>?     // start() 结果经 phase 反映；finish 前 await 它确保 start 完成
    @State private var autoStopTask: Task<Void, Never>?  // 面板侧 60s 计时（provider 侧计时只是兜底，见切片 02）
    // 一次物理按压的闸门：DragGesture.onChanged 会高频连触发，用它保证「按下→松手」间只起一次录音；
    // onEnded 复位。与 phase 正交——尤其 start() 抛权限错后 phase=.failed，若仅靠 phase 守卫，手指未松开时
    // onChanged 会反复放行重启 start()（每秒数十次抖 AVAudioSession），故必须用按压闸门而非 phase 判断。
    @State private var isPressing = false
    @State private var didClose = false                  // 取消后置位，短路仍在途的手势回调（防双指取消竞态）

    /// PRD 已确认约定 10：单次录音最长 60s，到点自动收尾（等价松手）。
    private static let maxDuration: TimeInterval = 60

    init(transcriber: any VoiceTranscribing, onRecognized: @escaping (String) -> Void) {
        _transcriber = State(initialValue: transcriber)
        self.onRecognized = onRecognized
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                statusIcon
                statusText
                Spacer()
                hint
                pushToTalkButton
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .navigationTitle("语音记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { close() }
                        .disabled(phase == .transcribing)   // 转文字中不打断
                }
            }
            .animation(.default, value: phase)
        }
        .interactiveDismissDisabled()   // 只经取消按钮关闭，避免录音中误关
        .onDisappear {
            // 面板关闭（含成功切 route）兜底：停采音 + 取消在途计时/启动 Task，避免视图销毁后 Task 仍存活 60s。
            startTask?.cancel(); autoStopTask?.cancel()
            transcriber.cancel()
        }
    }

    // MARK: - 顶部状态区

    private var statusIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 72))
            .foregroundStyle(iconColor)
            .symbolEffect(.pulse, isActive: phase == .recording)
    }

    private var iconName: String {
        switch phase {
        case .idle, .recording: return "mic.fill"
        case .transcribing:     return "waveform"
        case .failed:           return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch phase {
        case .recording: return .red
        case .failed:    return .orange
        default:         return .accentColor
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch phase {
        case .idle:
            Text("按住下面的按钮说话")
                .font(.headline)
        case .recording:
            VStack(spacing: 6) {
                Text("正在聆听…松手结束")
                    .font(.headline)
                Text("最长 60 秒")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .transcribing:
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("正在转文字…")
                    .font(.headline)
            }
        case .failed(.microphoneDenied), .failed(.speechDenied):
            // 权限被拒收敛到统一降级组件（N07）：受影响功能 + 去系统设置 + 手动不受影响。
            PermissionDenialNotice(permission: .microphoneOrSpeech)
                .padding(.horizontal)
        case .failed(let err):
            // 非权限错误（本机不可用 / 空结果 / 录音出错）保持原文案，不套用权限降级范式。
            Text(failedMessage(err))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    // MARK: - 示例提示 + 按住按钮

    private var hint: some View {
        Text("试试说：打车花了 20 块")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var pushToTalkButton: some View {
        // 用 DragGesture(minimumDistance:0) 实现"按住录音、松手结束"（Button 无法表达按住语义）。
        Capsule()
            .fill(phase == .recording ? Color.red : Color.accentColor)
            .frame(height: 64)
            .overlay {
                Label(buttonTitle, systemImage: "mic.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .opacity(phase == .transcribing ? 0.5 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in beginRecording() }   // 首次按下（onChanged 会连触发，靠 phase 守卫只首次生效）
                    .onEnded { _ in endRecording() }
            )
            .disabled(phase == .transcribing)
    }

    private var buttonTitle: String {
        switch phase {
        case .recording:    return "正在聆听…"
        case .transcribing: return "转文字中…"
        default:            return "按住说话"
        }
    }

    // MARK: - 录音状态机

    /// 按下（onChanged 首次）：靠 isPressing 闸门保证一次物理按压只起一次录音。
    /// 不用 phase 判断放行——start() 抛权限错后 phase=.failed，手指未松时 onChanged 仍高频触发，
    /// 若按 phase 放行会反复重启 start()（抖 AVAudioSession）；isPressing 直到松手（onEnded）才复位。
    private func beginRecording() {
        guard !didClose, !isPressing else { return }   // 已取消 / 本次按压已起录音 → 忽略后续连触发
        isPressing = true
        phase = .recording
        startTask = Task {
            do {
                try await transcriber.start()
                guard phase == .recording else { return }   // start 期间已松手/失败则不起计时
                startAutoStopTimer()
            } catch let err as VoiceTranscribeError {
                phase = .failed(err)
            } catch {
                phase = .failed(.failed)
            }
        }
    }

    /// 松手（onEnded）：复位按压闸门；仅录音中触发 finish（start 已失败则 phase 非 .recording，转手动重按）。
    private func endRecording() {
        isPressing = false
        if phase == .recording {
            finishRecording()
        }
    }

    private func finishRecording() {
        guard phase == .recording else { return }   // 防重入：首次置 .transcribing 后再进即短路
        phase = .transcribing
        autoStopTask?.cancel(); autoStopTask = nil
        Task {
            await startTask?.value                       // 确保 start 完成（mock 下瞬间；真机等权限/起采音）
            guard phase == .transcribing, !didClose else { return } // start 期间抛错已置 .failed；已取消则不回调
            do {
                let spoken = try await transcriber.finish()
                guard !didClose else { return }          // finish 期间被取消：不弹识别页
                onRecognized(spoken)                     // 成功：交纯口语给上层，切到复用 N03 的识别页
            } catch let err as VoiceTranscribeError {
                phase = .failed(err)
            } catch {
                phase = .failed(.failed)
            }
        }
    }

    /// 面板侧 60s 计时：到点若仍在录音，触发与松手等价的收尾（防用户一直按不松）。
    private func startAutoStopTimer() {
        autoStopTask?.cancel()
        autoStopTask = Task {
            try? await Task.sleep(for: .seconds(Self.maxDuration))
            guard !Task.isCancelled, phase == .recording else { return }
            finishRecording()
        }
    }

    private func close() {
        // 置 didClose + 复位 phase：双指场景（一指按住录音、另一指点取消）下，后续松手的 onEnded 会被
        // didClose / phase!=.recording 短路，不会在已取消后又 finish() 并弹出识别页。
        didClose = true
        isPressing = false
        phase = .idle
        startTask?.cancel(); autoStopTask?.cancel()
        transcriber.cancel()
        dismiss()
    }

    // MARK: - 派生

    private func failedMessage(_ err: VoiceTranscribeError) -> String {
        switch err {
        case .microphoneDenied, .speechDenied:
            return "需要麦克风和语音识别权限。请到「设置」开启后再试；手动记账、文本识别不受影响。"
        case .onDeviceUnavailable:
            return "当前设备/语言暂不支持本机语音识别，可改用文本识别或手动记账。"
        case .empty:
            return "没听清，请再说一次。"
        case .failed:
            return "录音出错了，请重试。"
        }
    }
}
