import SwiftUI
import PhotosUI

/// 截图识别说明卡（原型 app.js:266 openScreenshotSheet）：
/// 快捷指令主入口讲解 + 两步指引 +「从相册选图」备选 +「演示」占位（N06）。
/// 「从相册选图」= PhotosPicker 免权限选图 → 本机 OCR → 回调 onRecognized 交出文本，
/// 上层 RecordTabView 换 fullScreenCover item 切到复用识别页（source=.screenshotAlbum）。
struct ScreenshotIntakeSheet: View {
    // OCR provider 无状态（Vision 无存储 / mock behavior 识别时不变），故用 let，body 重算传新实例无害，
    // 不必照抄 N04 VoiceCaptureView 的 @State 持有（那是因 AVAudioSession 跨录音生命周期有状态）。
    let recognizer: any TextRecognizing
    let onRecognized: (String) -> Void      // OCR 出文本 → 上层切 .recognizing 复用识别页

    @Environment(\.dismiss) private var dismiss
    @State private var pickedItem: PhotosPickerItem?
    @State private var ocrPhase: ScreenshotOCRPhase = .idle
    @State private var showDemoPlaceholder = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    introHero        // 快捷指令主入口讲解（app.js:270）
                    twoStepGuide     // 两步设置指引（app.js:273-274）
                    // 「演示：模拟快捷指令截图」占位（app.js:276，后台链路属 N06）
                    Button("▶︎ 演示：模拟收到一张快捷指令截图") { showDemoPlaceholder = true }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    orDivider
                    // 「从相册选图」备选（app.js:278）= 本节点核心入口，PhotosPicker 免相册授权
                    PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                        Label("从相册选一张图识别", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(ocrPhase == .recognizing)
                }
                .padding()
            }
            .navigationTitle("截图识别")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(ocrPhase == .recognizing)
                }
            }
            .overlay { if ocrPhase == .recognizing { ocrRecognizingOverlay } }   // 本机读字中遮罩
            .animation(.default, value: ocrPhase)
            .alert("敬请期待", isPresented: $showDemoPlaceholder) {
                Button("好", role: .cancel) { }
            } message: {
                Text("快捷指令截图后台入账将在后续版本提供。")
            }
            // 空结果 / OCR 失败 → 对应提示，可重选（对齐 PRD §5 / 验收 5）。
            // 复位由 ocrFailedBinding 的 set（alert 关闭即 phase→idle）统一负责，「好」按钮不重复置位。
            .alert("这张图没能识别", isPresented: ocrFailedBinding) {
                Button("好", role: .cancel) { }
            } message: {
                Text(ocrFailedMessage)
            }
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }   // 用户取消选图不触发（pickedItem 不变），天然静默回说明卡
                Task { await runOCR(item) }
            }
        }
    }

    // MARK: - 说明卡文案（逐字对齐 demo app.js:270/273-274）

    private var introHero: some View {
        VStack(spacing: 12) {
            Text("📷➜🌅").font(.largeTitle)
            Text("主用法：在支付宝/微信/银行的付款结果页，用 iOS 快捷指令随手一截，图片会自动发给 Aubade，后台识别并直接入账，只弹一条通知告诉你结果——不用切来切去。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var twoStepGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepRow(1, "去「快捷指令」App 新建：截屏 → 发送给 Aubade")
            stepRow(2, "之后付完款触发它（背面轻点 / 分享菜单 / 语音）即可")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepRow(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            Text(text).font(.subheadline)
            Spacer(minLength: 0)
        }
    }

    private var orDivider: some View {
        HStack {
            VStack { Divider() }
            Text("或").font(.caption).foregroundStyle(.secondary)
            VStack { Divider() }
        }
    }

    // MARK: - 本机读字中遮罩（视觉对齐 N03 recognizingOverlay）

    private var ocrRecognizingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("正在识别截图…")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("本机读取文字，图片不离开手机")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .transition(.opacity)
    }

    // MARK: - 失败态 alert 绑定 + 文案

    private var ocrFailedBinding: Binding<Bool> {
        Binding(
            get: { if case .failed = ocrPhase { return true } else { return false } },
            set: { if !$0 { ocrPhase = .idle } }
        )
    }

    private var ocrFailedMessage: String {
        guard case .failed(let error) = ocrPhase else { return "" }
        switch error {
        case .empty:  return "没从这张图读出文字，换一张或手动记。"
        case .failed: return "这张图没能识别，换一张或转手动填写。"
        }
    }

    // MARK: - 选图 → 取 Data → 本机 OCR → 成功回调 / 失败态

    private func runOCR(_ item: PhotosPickerItem) async {
        ocrPhase = .recognizing
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                ocrPhase = .failed(.failed); pickedItem = nil; return   // 取不到图片数据
            }
            let text = try await recognizer.recognizeText(in: data)
            ocrPhase = .idle
            pickedItem = nil                    // 复位选择器，成功交回上层后可再次选图
            onRecognized(text)                  // 交出 OCR 文本 → 上层切 .recognizing 复用识别页
        } catch let error as TextRecognizeError {
            ocrPhase = .failed(error); pickedItem = nil
        } catch {
            ocrPhase = .failed(.failed); pickedItem = nil
        }
    }
}

/// 说明卡内 OCR 局部状态机（对齐 RecognitionPhase 风格；成功不停留——交回上层复用识别页）。
enum ScreenshotOCRPhase: Equatable {
    case idle
    case recognizing                    // 本机读字中（遮罩"正在识别截图…本机读取文字"）
    case failed(TextRecognizeError)     // 空结果 / OCR 失败 → 对应提示，可重选
}
