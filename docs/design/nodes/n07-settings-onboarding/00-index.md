# N07 设置/预算/Key/首次引导/权限收尾 — TRD 索引

> 节点 PRD：`docs/prd/nodes/n07-settings-onboarding-prd.md`（已评审通过）。
> 上游代码事实：N00 数据层 + N01 手动/编辑器 + N02 剩余/统计/预算读写 + N03 DeepSeek/Key/KeySetupSheet + N04 语音 + N05 截图·相册 + **N06 快捷指令后台入账 + 通知**（均已完成）。
> UI 与交互事实来源：已实现原型 demo `prototype/app/`（`app.js:74-99 renderOnboard` 引导 / `app.js:680-697 renderMine` 我的页 Key 行 + 分类只读标签 + 预算输入）。
> 本节点无 `.codegraph/` 索引，代码事实来自逐文件阅读，行号为写作时快照（可能 ±1 漂移）。

## 里程碑意义

N07 是 Aubade v1 开发 DAG 的**第八个、也是最后一个节点（收尾节点）**。它把散落在 N02~N06 各节点里"只有消费侧、没有正式设置入口"的配置项与异常提示，收进**一个统一的「我的」页**和**一条首次引导流程**：

- **首次引导两步**（净新增）：全新安装 → 录初始总额（可跳过）→ 提示配置 DeepSeek Key（可跳过）→ 落空账本记账页。
- **我的页正式设置**（净新增 UI，消费既有读写）：周/月预算设置、超支提示阈值（默认 80% 可配）、DeepSeek Key 状态行、分类只读查看、通知开关。
- **权限被拒统一降级**（净新增）：麦克风/语音/通知被拒时给出一致范式的降级提示（受影响功能 + 去系统设置 + 手动记账不受影响）。

做完后 App 从"能用"变成"配置完整、异常有交代"。

## 关键设计前提（用户本轮拍板 + 核对后确认，TRD 直接据此落地）

1. **首次引导走两步（对齐 DAG，非原型一步）**：`录初始总额（可跳过）→ 提示配置 Key（可跳过）→ 落记账页`。比原型 `renderOnboard` 多一个 Key 提示步。跳过不阻塞、手动记账不受影响。
2. **超支阈值可配、默认 80%**：`budgetProgress` 加阈值入参（保持纯函数、可单测），默认 80 与现状一致。
3. **通知开关 gating 加在发送器内部**：`UNUserNotificationCenterNotifier.send` 内 `requestAuthorization` 前先读开关，关则不发——对 `BackgroundIntakeService`/`SpyNotifier` 单测零改动，入账链路照常落库。
4. **生产配置集中管理**：`onboarding 完成标志 / 通知开关 / 超支阈值` 三项用一个集中的 `enum AppConfig` 定义 key + 默认值，视图用 `@AppStorage(key)` 绑定、非视图（发送器/聚合器调用方）读 `UserDefaults.standard`。Key（DeepSeek）仍走 Keychain、不进 UserDefaults。
5. **我的页 = 扩展既有 `ProfilePlaceholderView` List、不新建页面**：追加 Section，复用其 `@Query`/`store`/sheet 范式与 `InitialBalanceSheet` 的 Decimal 校验。
6. **完成门禁延续 N03~N06 约定**：可编译 + 可观察行为达成 + 单测覆盖（阈值驱动/预算落库/通知开关 gating/onboarding 分流）。无独立真机专项。

## 核对后确认的关键代码事实（决定 TRD 落地方式，含 PRD 未点明的调用点）

| 事实 | 核对结论 | 对 TRD 的影响 |
|---|---|---|
| `budgetProgress` 唯一**生产**调用点 | `AnalyticsTabView.budgetProgressView:310`（PRD 行号准确） | 切片 01 加阈值入参后同步传参 |
| `budgetProgress` **测试**调用点（PRD 漏点） | `StatisticsAggregatorTests.swift:184-200` 直接调 `budgetProgress(spent:budget:)` **6 处**（`:184/185/186/187/190/198`） | 切片 01 改签名后加默认值入参，这 6 处不传新参仍编译、行为不变（回归保护）——PRD 只提了生产调用点，TRD 显式补上 |
| `InitialBalanceSheet` 可见性 | **`private struct`**（`RootTabView.swift:127`），当前只在 `RootTabView.swift` 内用 | 切片 02/03 复用其 Decimal 校验范式：抽一个共享金额输入组件或按范式另写一个预算 sheet（不 `public` 化 private 类型，详见切片 02 §设计） |
| `KeySetupSheet` 保存后行为 | 只 `dismiss()`、**无完成回调**（`KeySetupSheet.swift:34-35`） | 切片 02 Key 状态行即时刷新：sheet dismiss 后视图 body 重算重读 `KeychainStore.shared.isConfigured`（用 `@State` 触发点刷新，详见切片 02 §设计） |
| 生产 UserDefaults 现状 | **生产零 UserDefaults**；仅 `#if DEBUG` 内 3 个 mock key（`DebugMenuView.swift:7/13/19`，`@AppStorage`） | 切片 01 首次引入生产 `AppConfig` key，照 DEBUG 集中范式 |
| 通知发送器形态 | `UNUserNotificationCenterNotifier` 是**无状态 struct**、`send` 内 `requestAuthorization`（`:27`）；`BackgroundIntakeService` 持 `notifier: any NotificationSending`（`:14`）、`RecordAubadeScreenshotIntent:25` 实例化真实发送器 | 切片 04 gating 加在 `send` 内读 `UserDefaults`——不改协议、不改 service、不改注入点 |
| 语音降级文案 | `VoiceCaptureView.failedMessage:232` 纯文本、**无跳系统设置按钮**；`VoiceTranscribeError.microphoneDenied/.speechDenied`（`VoiceTranscribing.swift:5-6`） | 切片 04 统一降级组件：把纯文本降级收敛到一致范式 + 加"去系统设置"入口 |
| 相册权限 | 走 `PhotosPicker` **免授权**（`ScreenshotIntakeSheet.swift:34`），无权限申请/降级 | 切片 04 不为相册硬造降级（现状事实） |
| 预置分类数据源 | `PresetCategories.expense/income`（静态串）+ `LedgerCategory`（`isPreset`/`sortOrder`/`direction`）；`LedgerStore.presetCategories()` 按 sortOrder 升序（`:38`） | 切片 02 分类只读查看：`@Query` 取 `isPreset==true`、按 `direction` 分组 + `sortOrder` 排序 |
| 根路由挂点 | `ContentView` 极薄、仅包 `RootTabView()`（`ContentView.swift:6-9`）；`AubadeApp.task` 做预置分类装载 + 清临时图（`AubadeApp.swift:15-18`） | 切片 03 onboarding 分流挂 `ContentView`：读标志决定进引导 or `RootTabView` |
| `setBudget` / `setBalanceBaseline` | 均按唯一化写侧收敛（`LedgerStore.swift:83/104`），`setBudget(periodType:amount:)` 按 periodType 唯一 | 切片 02 预算设置、切片 03 引导录初始总额直接调，零签名改动 |
| 清空预算语义参考 | `DebugMenuView.clearBudgets():166` 删所有 Budget | 切片 02"清空预算"= 删该 periodType 的 Budget（详见切片 02 §设计） |

## 切片划分与顺序

N07 拆成 **4 个单一职责切片**，按"先立配置底座与唯一签名改动 → 我的页纯新增 UI → 引导流程与根分流 → 通知开关与权限降级"排序，每片可独立编译、独立验证：

| 切片 | 名称 | 单一职责 | 依赖 | 覆盖 PRD 验收 |
|---|---|---|---|---|
| 01 | 生产配置中心 + 超支阈值可配（含签名改造 + 全调用点同步） | **唯一有签名波及的地基先立住**：新增 `AppConfig` 集中配置 key + 默认值；`budgetProgress` 加 `nearThreshold` 入参（默认 80）；同步更新**生产调用点 `AnalyticsTabView:310` + 测试调用点 `StatisticsAggregatorTests:184-200`**；我的页加"超支提示阈值"设置项（读写 `AppConfig`）；阈值驱动单测（80/50 两组） | N02 | 验收 3/8（设置侧）、9（阈值驱动）、10（唯一签名改动收口） |
| 02 | 我的页预算设置 + Key 状态行 + 分类只读查看 | **纯新增 UI 消费既有读写、零签名改动**：`ProfilePlaceholderView` List 追加"预算设置"（周/月，调 `setBudget`）+"智能识别"Key 状态行（读 `isConfigured`，点击开既有 `KeySetupSheet`，dismiss 后即时刷新）+"分类（预置）"只读 Section；预算设置落库单测 | N02/N03/N00、切片 01 | 验收 2（预算即时生效）、4（Key 状态）、5（分类只读） |
| 03 | 首次引导两步流程 + onboarding 完成标志 + 根路由分流 | **净新增引导 + 根分流**：`OnboardingView`（① 录初始总额可跳过 → ② 提示配 Key 可跳过 → 置标志落记账 Tab）；`ContentView` 按 `AppConfig.hasOnboarded` 分流；引导录初始总额调 `setBalanceBaseline`、配 Key 复用 `KeySetupSheet`；onboarding 分流单测 | 切片 01/02 | 验收 1（引导两步）、8（标志持久） |
| 04 | 通知开关 gating + 权限被拒统一降级提示 | **发送前 gating + 统一降级范式**：`UNUserNotificationCenterNotifier.send` 内读 `AppConfig.notificationsEnabled`（关则不发、入账不受影响）；我的页"通知开关"+ 权限被拒"去系统设置"引导；统一 `PermissionDenialNotice` 组件/文案（覆盖语音/麦克风/通知），把 `VoiceCaptureView:232` 纯文本收敛；通知开关 gating 单测 | N06/N04、切片 01/02 | 验收 6（通知开关不误伤入账）、7（权限降级一致） |

### 为什么这样拆

- **切片 01 先立配置底座 + 收口唯一签名改动**：`budgetProgress` 加阈值入参是**本节点唯一有编译波及**的改动，波及生产调用点 + 测试调用点共 6 处。先做它，把"改签名 → 同步全部调用点 → 回归默认 80% 行为"一次性验证通过，后续三片都在"零签名改动"的安全区里加 UI。`AppConfig` 集中配置也在此片落地（后续三片都要读它）。
- **切片 02 是纯增量 UI**：预算设置、Key 状态行、分类只读，全是"在既有 List 加 Section、消费既有读写能力"，互不依赖、可一次验证。三者共用切片 01 的金额输入范式与 `AppConfig`。
- **切片 03 引导 + 根分流独立成片**：它改的是**根路由分流点**（`ContentView`），风险面与我的页正交；且要复用切片 02 已接好的 `KeySetupSheet` 调用手法与切片 01 的 `AppConfig.hasOnboarded`。放在我的页之后，引导页"配 Key"直接复用同一套 sheet 唤起。
- **切片 04 通知开关 + 权限降级收尾**：gating 依赖切片 01 的 `AppConfig.notificationsEnabled`；统一降级组件是横切 N04/N06 的呈现层收敛，放最后统一做，避免与前三片的新增 UI 交叉。

## 切片文件

- `01-config-center-budget-threshold-trd.md`
- `02-profile-budget-key-category-trd.md`
- `03-onboarding-flow-trd.md`
- `04-notification-toggle-permission-trd.md`

## 全节点共用的关键约束（四片都遵守）

1. **唯一既有签名改动 = `budgetProgress` 加 `nearThreshold` 入参**（PRD 已确认约定 10）：连带同步**生产调用点 `AnalyticsTabView:310`** 与**测试调用点 `StatisticsAggregatorTests:184-200`**；其余全为新增 UI 消费既有能力，不改 `LedgerStore`/`KeychainStore`/`Budget`/`LedgerCategory`/通知发送器对外签名。
2. **金额一律纯 `Decimal`、不经 `Double`**（对齐 `InitialBalanceSheet` 范式 + `DecimalPrecisionTests`）：预算/初始总额输入走 posix locale `Decimal(string:)` 校验（`RootTabView.swift:136-142` 范式）。
3. **生产配置集中管理、Key 仍走 Keychain**（PRD 已确认约定 8、业务规则 12）：`onboarding 标志/通知开关/超支阈值` 集中在 `AppConfig`（UserDefaults）；DeepSeek Key 不进 UserDefaults、仍 `KeychainStore`、判定只看非空、不联网测活。
4. **我的页扩展 `ProfilePlaceholderView`、不新建页面**（PRD 已确认约定 9）：追加 Section，复用其 `@Query`/`store`/`InitialBalanceSheet` 范式；DEBUG 调试入口与硬编码保留（不删既有调试能力）。
5. **不误伤既有行为是红线**：默认阈值 80% 与现状一致（回归安全）；通知开关默认开（关的是通知、不是入账）；未配 Key 前后台拦截（N03/N06）行为不变；手动记账永远不受权限影响。
6. **不越界**（PRD "不做什么"）：不做记账入口本身、不重造 Key 填写/拦截、不做 Key 联网测活、不做分类增删改、不重做统计计算/图表、不改各权限申请时机、不碰通知内容/路由/后台链路、不动存储架构（App Group/扩展/迁移）。
7. **可测性延续 N02~N06 范式**（XCTest 平铺 `AubadeTests/`）：阈值驱动、预算落库、通知开关 gating、onboarding 分流均补单测；复用 `SpyNotifier`（`BackgroundIntakeServiceTests:29`）、in-memory 容器（`PersistenceController.makeInMemoryContainer()`）注入范式。
