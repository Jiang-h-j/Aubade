import Foundation
import Security

/// DeepSeek API Key 的 Keychain 读写（技术基线 §7.4：不落库 / 不进 UserDefaults / 不入源码）。
/// 最小闭环：读 / 写 / 删 + "已配置"判定。完整状态展示与我的页 Key 行 → N07。
struct KeychainStore {
    static let shared = KeychainStore()

    private let service = "com.aubade.deepseek"
    private let account = "api-key"

    /// 通用查询基底（service + account 唯一定位一条 generic password）。
    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// 读取 Key（不存在 / 解码失败 → nil）。
    var deepSeekKey: String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    /// 写入 Key：先 delete 再 add 保证唯一（与 LedgerStore.setBudget 写侧唯一化同风格）。
    func setDeepSeekKey(_ key: String) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let data = key.data(using: .utf8) else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    /// 删除 Key。
    func clearDeepSeekKey() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// "已配置" = 非空 Key 存在（无 Key 拦截的判据，切片 02 消费）。
    /// 不做 Key 格式 / 联网校验（→ N07）。
    var isConfigured: Bool {
        (deepSeekKey?.isEmpty == false)
    }
}
