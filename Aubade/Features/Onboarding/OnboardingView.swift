import SwiftUI
import SwiftData

/// 首次启动两步引导（N07 切片 03）。全新安装第一次打开时由 `ContentView` 分流进入：
/// ① 录初始总额（可跳过）→ ② 提示配 DeepSeek Key（可跳过）→ 落记账 Tab。
/// 走完（无论是否跳过）置 `hasOnboarded = true`，`ContentView` body 重算切 `RootTabView`（默认落 `.record`）。
///
/// 线性两步用 `@State step` 驱动，非 NavigationStack push——引导无需返回栈，步进用顶部 "1/2" 文案表达。
/// 红线：两步都能跳过、跳过不阻塞；标志只在两步走完置位（中途退出不续引导，下次从头，见 TRD「不做什么」）。
struct OnboardingView: View {
    enum Step {
        case balance   // ① 录初始总额
        case key       // ② 提示配 Key
    }

    @Environment(\.modelContext) private var modelContext
    // 完成置位 → ContentView body 重算自动切 RootTabView，无需手动导航。
    @AppStorage(AppConfig.hasOnboardedKey) private var hasOnboarded = AppConfig.hasOnboardedDefault

    @State private var step: Step = .balance
    @State private var balanceInput: String = ""
    @State private var showingKeySheet = false

    // 注入 modelContext 构造，非链式 container().mainContext（避免悬垂 context）。
    private var store: LedgerStore { LedgerStore(modelContext) }

    /// 解析后的有效初始总额：非空、可转 Decimal、且 >= 0（照抄 InitialBalanceSheet 校验范式）。
    /// 显式 posix locale 钉死小数点为 `.`，避免逗号小数分隔地区把 decimalPad 输入解析错。
    private var parsedAmount: Decimal? {
        let trimmed = balanceInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")),
              value >= 0 else { return nil }
        return value
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            header
            Spacer(minLength: 24)
            switch step {
            case .balance: balanceStep
            case .key: keyStep
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 配 Key sheet 关闭不自动完成：用户可能填完想看一眼，由步②「开始记账」按钮显式 finish。
        .sheet(isPresented: $showingKeySheet) {
            KeySetupSheet()
        }
    }

    // MARK: - 顶部品牌区（对齐原型 renderOnboard：logo 🌅 + 标题 Aubade + 步进/说明）

    private var header: some View {
        VStack(spacing: 12) {
            Text("🌅")
                .font(.system(size: 56))
            Text("Aubade")
                .font(.largeTitle.bold())
            Text(step == .balance ? "第 1 步 / 共 2 步" : "第 2 步 / 共 2 步")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 步① 录初始总额

    private var balanceStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("你现在大约有多少钱？")
                    .font(.title3.weight(.semibold))
                Text("所有账户加起来的合计，作为剩余金额的起点。之后每记一笔收支会自动加减。可以先跳过，稍后在「我的」里设置。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("例如 12345", text: $balanceInput)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.title2)
                .padding(.vertical, 12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 12) {
                // 主按钮「下一步」：有值落基线再进；无值直接进（等价跳过）。始终可点，不阻塞。
                Button {
                    if let amount = parsedAmount {
                        try? store.setBalanceBaseline(initialAmount: amount, establishedAt: Date())
                    }
                    step = .key
                } label: {
                    Text("下一步")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                // ghost「先跳过」：不落基线直接进步②（剩余此后显示「未设置」）。
                Button("先跳过") {
                    step = .key
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 步② 提示配 Key

    private var keyStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("要开启智能识别吗？")
                    .font(.title3.weight(.semibold))
                Text("识别记账（截图 / 语音 / 文本）需要 DeepSeek Key，手动记账不受影响。可以先跳过，之后在「我的」里补。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                // 主按钮「去填写」：开 KeySetupSheet（填不填都不阻塞）。sheet 关闭后停在步②，由「开始记账」finish。
                Button {
                    showingKeySheet = true
                } label: {
                    Text("去填写")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                // 「开始记账」：完成引导（无论上一步是否填了 Key）→ finish 落记账页。
                Button("开始记账") {
                    finish()
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 完成

    /// 置引导完成标志 → ContentView body 重算切 RootTabView（默认落 .record 记账页）。
    private func finish() {
        hasOnboarded = true
    }
}

#Preview {
    OnboardingView()
        .modelContainer(PersistenceController.makeInMemoryContainer())
}
