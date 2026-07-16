import SwiftUI

/// 被拒权限类型（决定"哪个功能受影响"文案）。N07 收尾：把散落各处的权限被拒提示统一成一致范式。
enum DeniedPermission {
    case microphoneOrSpeech   // 语音记账（麦克风 / 语音识别，N04 合并——两者同一功能面）
    case notification         // 截图入账通知（N06）

    var affectedFeature: String {
        switch self {
        case .microphoneOrSpeech: return "语音记账"
        case .notification: return "截图入账通知"
        }
    }
}

/// 统一降级文案：受影响功能 + 去系统设置 + 手动记账不受影响（三要素）。
/// 脱离视图便于复用与断言；各降级点渲染 PermissionDenialNotice 即得一致文案。
enum PermissionDenialCopy {
    static func message(for permission: DeniedPermission) -> String {
        "\(permission.affectedFeature)需要相应权限。可到「设置」开启；手动记账不受影响。"
    }
}

/// 统一降级呈现：文案三要素 + "去系统设置"按钮。可内嵌于各降级点（语音面板等）。
struct PermissionDenialNotice: View {
    let permission: DeniedPermission

    var body: some View {
        VStack(spacing: 8) {
            Text(PermissionDenialCopy.message(for: permission))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("去系统设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.footnote)
        }
    }
}
