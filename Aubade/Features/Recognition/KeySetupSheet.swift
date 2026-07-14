import SwiftUI

/// 最小 Key 填写 sheet：能填、能存、能被 `isConfigured`/`DeepSeekClient` 读到即可。
///
/// 完整"已配置✓/去填写"状态卡、我的页 Key 行、联网测活 → N07。
struct KeySetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    // 预填已存的 Key（若有），便于修改；SecureField 不明文回显。
    @State private var keyText = KeychainStore.shared.deepSeekKey ?? ""

    private var trimmedKey: String {
        keyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("DeepSeek API Key", text: $keyText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Key 只存于本机钥匙串，不上传、不写入账单。识别类记账需要它，手动记账不受影响。")
                }
            }
            .navigationTitle("DeepSeek API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        KeychainStore.shared.setDeepSeekKey(trimmedKey)
                        dismiss()
                    }
                    .disabled(trimmedKey.isEmpty)
                }
            }
        }
    }
}
