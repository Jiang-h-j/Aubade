# TRD 03 - 首次引导两步流程 + onboarding 完成标志 + 根路由分流

## 给用户看的摘要

给全新安装的第一次打开加一条引导，不再一进来就对着空账本发愣：先请你**录一个初始总额**（现在所有账户加起来大约多少钱，作为剩余金额的起点，可以先跳过）→ 再**提示填一下 DeepSeek Key**（识别记账要用，也可以先跳过、之后在「我的」里补）→ 然后落到记账页开始记账。走完（无论是否跳过）就记住"已引导"，以后打开直达主界面、不再出现。

## 本 TRD 负责什么

- 新增 `OnboardingView`：两步引导（① 录初始总额可跳过 → ② 提示配 Key 可跳过 → 落记账 Tab）。
- `ContentView` 按 `AppConfig.hasOnboarded` 分流：未完成进引导、完成进 `RootTabView`。
- 引导录初始总额调既有 `setBalanceBaseline`；配 Key 复用既有 `KeySetupSheet`。
- 走完置 `hasOnboarded = true` → 落记账页。
- onboarding 分流单测。

## 当前代码事实与上下游

- 根路由：`AubadeApp.swift:12 ContentView()` → `ContentView.swift:6-9` 仅 `RootTabView()`。`AubadeApp.task`（`:15-18`）做 `PresetCategories.seedIfNeeded` + `TemporaryImageStore().purgeAll()`。
- `AppConfig.hasOnboardedKey/hasOnboardedDefault`（切片 01 已定义，默认 false）。
- `LedgerStore.setBalanceBaseline(initialAmount:establishedAt:)`（`:104`，清空+插入唯一化）。
- `InitialBalanceSheet`（`RootTabView.swift:127`，private）：录初始总额的校验范式来源；引导步①照此范式（posix Decimal 校验、允许 >= 0）。
- `KeySetupSheet`（`KeySetupSheet.swift:6`）：引导步②"去填写"复用它（切片 02 已验证 sheet 唤起手法）。
- 全仓零 onboarding/hasOnboarded 命中（PRD 核实）——本片首次引入。
- 原型 `renderOnboard`（`app.js:74-99`）：logo 🌅 + 标题 Aubade + lead 说明 + 初始总额输入 + "开始记账"主按钮 + "先跳过，稍后在'我的'里设置"ghost 按钮；跳过/录入都置 `State.onboarded=true` 落 add 页。**原型只一步**——本片按 DAG 补第二步 Key 提示。

## 设计方案

### 1. 根路由分流（`ContentView`）

`ContentView` 从"仅包 RootTabView"改为"按标志分流"：

```swift
struct ContentView: View {
    @AppStorage(AppConfig.hasOnboardedKey) private var hasOnboarded = AppConfig.hasOnboardedDefault

    var body: some View {
        if hasOnboarded {
            RootTabView()
        } else {
            OnboardingView()   // 走完内部置 hasOnboarded=true，body 重算切到 RootTabView
        }
    }
}
```

- `@AppStorage` 置位后 `ContentView` body 重算 → 自动切 `RootTabView`（无需手动导航）。
- 分流挂 `ContentView` 而非 `AubadeApp`：`AubadeApp.task` 的 `seedIfNeeded`/`purgeAll` 与容器注入保持不动（引导期也需预置分类已装载，seed 在 App 层先跑）。
- **落记账 Tab**：`RootTabView` 默认 `selectedTab = .record`（`RootTabView.swift:16`），引导结束切到 `RootTabView` 即天然落记账页，无需额外传参。

### 2. `OnboardingView`（新增文件 `Aubade/Features/Onboarding/OnboardingView.swift`）

两步用 `@State private var step: Step`（枚举 `.balance/.key`）驱动，非 NavigationStack push（引导是线性两步、无需返回栈；步进指示 1/2 用顶部文案）。

```swift
struct OnboardingView: View {
    enum Step { case balance, key }

    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppConfig.hasOnboardedKey) private var hasOnboarded = AppConfig.hasOnboardedDefault

    @State private var step: Step = .balance
    @State private var balanceInput: String = ""
    @State private var showingKeySheet = false

    private var store: LedgerStore { LedgerStore(modelContext) }
    private var parsedAmount: Decimal? { /* 同 InitialBalanceSheet posix 校验，>= 0 */ }

    var body: some View {
        VStack { ... }   // 视觉基调对齐 renderOnboard：logo/标题/说明/内容区/主按钮/ghost 跳过
    }
}
```

**步① 录初始总额**：
- 输入区：`TextField(.decimalPad)` + posix `Decimal(string:)` 校验（照抄 `InitialBalanceSheet:136-142`）。
- 主按钮"下一步"：有值 → `try? store.setBalanceBaseline(initialAmount: amount, establishedAt: Date())` → `step = .key`；无值时按钮文案仍可"下一步"但不落基线（或 disabled 引导先填/跳过——见下）。
- ghost"先跳过" → 不落基线 → `step = .key`（剩余此后显示"未设置"，对齐 `BalanceCalculator` nil 语义 + 原型 skip 分支）。
- **交互定**：主按钮"下一步"始终可点；有值则落库再进、无值直接进（等价跳过）；另留显式"先跳过"ghost 按钮语义更清晰。二选一实现时定为：主按钮"下一步"（有值落库、无值也进）+ 不再单列 skip（简化）——**待实现时按原型双按钮语义确认**：原型是"开始记账"（读值）+"先跳过"两个按钮，本片步①对齐原型双按钮（下一步 + 先跳过），只是"下一步/开始记账"后面接第二步而非直接落页。

**步② 提示配 Key**：
- 说明文案："识别记账（截图/语音/文本）需要 DeepSeek Key，手动记账不受影响，可以先跳过、之后在「我的」里补。"
- 主按钮"去填写" → `showingKeySheet = true`（`.sheet { KeySetupSheet() }`，复用切片 02 手法）；填不填都不阻塞。
- ghost"先跳过" → 直接完成。
- **完成动作**（去填写保存后 or 跳过）：`finish()` → `hasOnboarded = true`（→ `ContentView` 切 RootTabView 落记账页）。

```swift
private func finish() {
    hasOnboarded = true   // @AppStorage 置位，ContentView body 重算切 RootTabView（默认落 .record）
}
```

- Key sheet 关闭不自动 finish（用户可能填完想看一眼），由步②的按钮触发 finish；或 sheet dismiss 后停在步② 由用户点"完成/开始记账"。**定**：步② 主按钮在"去填写"与"完成"之间——去填写开 sheet，sheet 关后按钮变"开始记账"→ finish；未填则"先跳过"→ finish。实现时保持"两步都能跳过、跳过不阻塞"红线即可。

### 3. onboarding 期的数据前提

- 预置分类：`AubadeApp.task seedIfNeeded` 在 App 启动即跑（引导页之前），引导录初始总额不依赖分类，安全。
- 引导录初始总额 → `setBalanceBaseline` 落库 → 完成后 RootTabView 剩余总额/账单页即显示该值（验收 1 后半 + 验收 9）。

## 修改点

- **改** `Aubade/ContentView.swift`：加 `@AppStorage hasOnboarded`，body 按标志分流 `RootTabView` / `OnboardingView`。
- **新增** `Aubade/Features/Onboarding/OnboardingView.swift`：两步引导视图 + 完成置标志。
- **无签名改动**：`setBalanceBaseline`/`KeySetupSheet` 照现状调用；`RootTabView` 不改（默认 `.record` 天然落点）。
- **不改** `AubadeApp.swift`（容器注入/seed/purge 保持）。

## 验证点

- **可编译**：`ContentView` + `OnboardingView` 编译通过。
- **onboarding 分流单测**（新增，注入独立 `UserDefaults(suiteName:)`）：
  - `hasOnboarded` 未置位（默认 false）→ 分流选择 `OnboardingView`（可测：抽一个纯函数/computed `shouldShowOnboarding(_ defaults:) -> Bool` 断言，或断言 `AppConfig` 读取 false）。
  - 置 `hasOnboarded = true` → 分流选择 `RootTabView`。
  - > 说明：SwiftUI View body 分流难直接单测，故把"是否进引导"的判据做成可测的 `AppConfig.hasOnboarded(_:)` 读取 + 一个纯 bool 判定；断言标志读写正确即覆盖分流逻辑。
- **可观察**（模拟器全新安装 or 手动清 `hasOnboarded` key）：
  - 首次启动 → 进"录初始总额"页 → 输入数字"下一步" → 进"提示配 Key"页 →（填或跳过）→ 落记账 Tab（空账本）。
  - 重启 App → 不再进引导、直达 RootTabView（验收 1）。
  - 录了初始总额的 → 我的页/账单页剩余总额显示该值；两步都跳过的 → 剩余"未设置"、手动记账可用、识别类走既有未配 Key 拦截（验收 1 后半）。
- **配置持久**：`hasOnboarded` 跨重启保持（验收 8）。

## 不做什么

- 不改 `RootTabView` 默认 Tab（`.record` 已是默认落点）。
- 不做引导页的花哨动画/多于两步/可回退的复杂导航（线性两步，跳过不阻塞）。
- 不在引导里做 Key 联网测活、不做分类选择/自定义（步②只提示配 Key，复用既有 sheet）。
- 不改 `AubadeApp` 的 seed/purge/容器注入。
- 不做"引导中途退出 App 后重进从第几步继续"的断点续引导（未完成即从头，标志只在两步走完置位）。
- 不做多语言/引导页营销文案打磨（对齐原型基调即可）。
