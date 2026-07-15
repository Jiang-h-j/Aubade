#if DEBUG
import SwiftUI
import SwiftData

/// DEBUG mock 识别行为的持久化设置：调试菜单写、RecordTabView 读（TRD 03 §5）。
/// 仅 DEBUG 调试用（非 Key、非业务数据），存 UserDefaults 无妨。
enum DebugMockSettings {
    static let behaviorKey = "debug.mockBehavior"
}

/// DEBUG 语音转文字 mock 行为的持久化设置（N04 切片 03）：调试菜单写、RecordTabView 读。
/// 与文本 mock 分开一个 key，两入口互不污染（PRD §6）。
enum DebugVoiceMockSettings {
    static let behaviorKey = "debug.voiceMockBehavior"
}

/// DEBUG 截图 OCR mock 行为的持久化设置（N05 切片 02）：调试菜单写、RecordTabView 读。
/// 与文本/语音 mock 各分开一个 key，三入口互不污染（PRD §6）。
enum DebugScreenshotMockSettings {
    static let behaviorKey = "debug.screenshotMockBehavior"
}

/// 临时验证入口（仅 DEBUG）：手动触发插入样例账单 / 列出预置分类 / 清库重置，
/// 供真机或模拟器肉眼确认容器单点共享（PRD 验收 6）。Release 构建不含此入口。
struct DebugMenuView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query private var transactions: [Transaction]

    @State private var lastMessage: String = ""
    // N03 mock 行为选择（与 RecordTabView 共用同一 @AppStorage key）。
    @AppStorage(DebugMockSettings.behaviorKey) private var mockBehaviorRaw = MockTransactionParser.Behavior.success.rawValue
    // N04 语音 mock 行为选择（与 RecordTabView 共用同一 @AppStorage key）。
    @AppStorage(DebugVoiceMockSettings.behaviorKey) private var voiceMockRaw = MockVoiceTranscriber.Behavior.success.rawValue
    // N05 截图 OCR mock 行为选择（与 RecordTabView 共用同一 @AppStorage key）。
    @AppStorage(DebugScreenshotMockSettings.behaviorKey) private var screenshotMockRaw = MockTextRecognizer.Behavior.success.rawValue

    var body: some View {
        List {
            Section("库状态") {
                Text("预置分类：\(categories.filter { $0.isPreset }.count) 条")
                Text("账单：\(transactions.count) 笔")
                if !lastMessage.isEmpty {
                    Text(lastMessage).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("分类清单") {
                ForEach(categories) { category in
                    HStack {
                        Text(category.name)
                        Spacer()
                        Text(category.direction == .expense ? "支出" : "收入")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("操作") {
                Button("插入一笔样例账单") { insertSample() }
                Button("重新装载预置分类") {
                    PresetCategories.seedIfNeeded(context)
                    lastMessage = "已调用 seedIfNeeded（幂等）"
                }
                Button("清空全部数据", role: .destructive) { resetAll() }
            }

            Section("N02 调试（预算 / 初始总额）") {
                Button("写月预算 1500") { setBudget(.monthly, 1500, "月预算 1500") }
                Button("写周预算 800") { setBudget(.weekly, 800, "周预算 800") }
                Button("写初始总额 12000") { setBaseline(12000) }
                Button("清空预算", role: .destructive) { clearBudgets() }
            }

            Section("N03 调试（DeepSeek Key / mock 识别）") {
                Text("Key 状态：\(KeychainStore.shared.isConfigured ? "已配置" : "未配置")")
                Button("写入测试 Key") {
                    KeychainStore.shared.setDeepSeekKey("sk-debug-placeholder")
                    lastMessage = "已写入测试 Key（占位，非真 Key）"
                }
                Button("清除 Key", role: .destructive) {
                    KeychainStore.shared.clearDeepSeekKey()
                    lastMessage = "已清除 Key"
                }
                Picker("mock 识别结果", selection: $mockBehaviorRaw) {
                    Text("成功").tag(MockTransactionParser.Behavior.success.rawValue)
                    Text("无金额").tag(MockTransactionParser.Behavior.noAmount.rawValue)
                    Text("网络失败").tag(MockTransactionParser.Behavior.network.rawValue)
                    Text("超时").tag(MockTransactionParser.Behavior.timeout.rawValue)
                    Text("非法响应").tag(MockTransactionParser.Behavior.invalidResponse.rawValue)
                }
            }

            Section("N04 调试（语音 mock）") {
                Text("模拟器无真麦克风：切换行为，走通语音 → 入账 / 各降级路径")
                    .font(.footnote).foregroundStyle(.secondary)
                Picker("mock 语音结果", selection: $voiceMockRaw) {
                    Text("成功（打车花了 20 块）").tag(MockVoiceTranscriber.Behavior.success.rawValue)
                    Text("空结果").tag(MockVoiceTranscriber.Behavior.empty.rawValue)
                    Text("麦克风被拒").tag(MockVoiceTranscriber.Behavior.microphoneDenied.rawValue)
                    Text("语音被拒").tag(MockVoiceTranscriber.Behavior.speechDenied.rawValue)
                    Text("本机不可用").tag(MockVoiceTranscriber.Behavior.onDeviceUnavailable.rawValue)
                }
            }

            Section("N05 调试（截图 OCR mock）") {
                Text("模拟器无真图片：切换行为，走通截图 → 入账 / 各降级路径（仍需在相册选一张图触发）")
                    .font(.footnote).foregroundStyle(.secondary)
                Picker("mock OCR 结果", selection: $screenshotMockRaw) {
                    Text("成功（星巴克 88.5）").tag(MockTextRecognizer.Behavior.success.rawValue)
                    Text("空结果（没读出字）").tag(MockTextRecognizer.Behavior.empty.rawValue)
                    Text("OCR 失败").tag(MockTextRecognizer.Behavior.failed.rawValue)
                }
            }
        }
        .navigationTitle("调试菜单")
    }

    private func insertSample() {
        let store = LedgerStore(context)
        do {
            let category = try store.presetCategories().first
            try store.createTransaction(
                amount: Decimal(string: "35.55")!, direction: .expense,
                occurredAt: Date(), category: category,
                merchant: "样例商户", source: .manual)
            lastMessage = "已插入样例账单 35.55"
        } catch {
            lastMessage = "插入失败：\(error)"
        }
    }

    private func resetAll() {
        do {
            for tx in transactions { context.delete(tx) }
            for category in categories { context.delete(category) }
            try context.save()
            lastMessage = "已清空全部数据"
        } catch {
            lastMessage = "清空失败：\(error)"
        }
    }

    // MARK: - N02 调试：写预算 / 初始总额（正式设置界面在 N07）

    private func setBudget(_ periodType: BudgetPeriodType, _ amount: Decimal, _ desc: String) {
        do {
            try LedgerStore(context).setBudget(periodType: periodType, amount: amount)
            lastMessage = "已写\(desc)"
        } catch {
            lastMessage = "写预算失败：\(error)"
        }
    }

    private func setBaseline(_ amount: Decimal) {
        do {
            try LedgerStore(context).setBalanceBaseline(initialAmount: amount, establishedAt: Date())
            lastMessage = "已写初始总额 \(AmountFormat.plainString(amount))"
        } catch {
            lastMessage = "写初始总额失败：\(error)"
        }
    }

    private func clearBudgets() {
        do {
            let store = LedgerStore(context)
            for budget in try store.fetch(Budget.self) { context.delete(budget) }
            try context.save()
            lastMessage = "已清空预算"
        } catch {
            lastMessage = "清空预算失败：\(error)"
        }
    }
}
#endif
