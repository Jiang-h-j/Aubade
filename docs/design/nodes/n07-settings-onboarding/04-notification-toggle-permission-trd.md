# TRD 04 - 通知开关 gating + 权限被拒统一降级提示

## 给用户看的摘要

收尾两件事：① **通知开关**——不想要截图后台入账的通知了，在「我的」页一键关掉；关掉只是不弹通知，账还是照记（关的是通知、不是记账）。② **权限被拒说法统一**——麦克风、语音、通知这些权限如果你拒了，App 给的提示统一成一致的说法：告诉你哪个功能受影响、去哪开、以及**手动记账永远不受影响**，不会因为拒了权限就卡死。

## 本 TRD 负责什么

- `UNUserNotificationCenterNotifier.send` 发送前读 `AppConfig.notificationsEnabled`，关则不发（入账不受影响）。
- 我的页"通知开关"设置项 + 系统级权限被拒时"去系统设置"引导。
- 统一权限降级提示组件/文案（覆盖麦克风/语音/通知），把 `VoiceCaptureView:232` 纯文本收敛到一致范式。
- 通知开关 gating 单测。

## 当前代码事实与上下游

- `UNUserNotificationCenterNotifier`（`UNUserNotificationCenterNotifier.swift:7`）：无状态 struct、实现 `NotificationSending`；`send`（`:23`）内 `:27` `requestAuthorization([.alert,.sound])` → `guard granted else { return }` → `center.add(request)`。
- `BackgroundIntakeService`（`:14` 持 `notifier: any NotificationSending`）经 `.send(...)` 发通知（`:28/34/49/59`）；`RecordAubadeScreenshotIntent:25` 实例化 `UNUserNotificationCenterNotifier()`。
- `SpyNotifier`（`BackgroundIntakeServiceTests:29`）：注入断言"发了哪类"——gating 加在 `send` 内部则**不影响** service 逻辑与 spy 断言（spy 是另一个 `NotificationSending` 实现，不含 gating）。
- `AppConfig.notificationsEnabledKey/Default`（切片 01 已定义，默认 true）。
- 语音降级：`VoiceCaptureView.failedMessage:232-243` 纯文本，`.microphoneDenied/.speechDenied` 文案"需要麦克风和语音识别权限。请到「设置」开启后再试；手动记账、文本识别不受影响。"——**无跳系统设置按钮**。
- 通知被拒：`send:27-28` 被拒静默 return（无用户可见降级）。
- 相册：`PhotosPicker` 免授权（`ScreenshotIntakeSheet.swift:34`）——无降级需求。
- 权限串：pbxproj `INFOPLIST_KEY_*`（麦克风+语音，走 `GENERATE_INFOPLIST_FILE`）；无独立 Info.plist。

## 设计方案

### 1. 通知开关 gating（`UNUserNotificationCenterNotifier.send`）

在 `requestAuthorization` 前先读开关，关则直接 return（PRD 已确认约定 6：gating 加在发送前）：

```swift
func send(_ notification: IntakeNotification) async {
    // 通知总开关（N07）：关则不发——入账已完成、不受影响（约定 6）。
    guard Self.notificationsEnabled() else { return }

    let center = UNUserNotificationCenter.current()
    let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    guard granted else { return }
    ...
}

/// 通知开关读取（脱 @AppStorage，供发送器非视图上下文读 + 单测注入）。
static func notificationsEnabled(_ defaults: UserDefaults = .standard) -> Bool {
    defaults.object(forKey: AppConfig.notificationsEnabledKey) as? Bool ?? AppConfig.notificationsEnabledDefault
}
```

- **为什么加在发送器内而非装饰器**（用户拍板）：发送器是后台链路唯一真实发送点，`send` 前读一次配置最小改动；`BackgroundIntakeService`/注入点/`SpyNotifier` 全零改动，入账链路照常落库。
- **可测性**：gating 判定抽成 `static notificationsEnabled(_:)`，单测直接调它断言"开→true、关→false、未设→默认 true"，无需起真系统通知。
- `object(forKey:) as? Bool ?? default`：未设值走默认 true（不用 `bool(forKey:)`——后者未设返回 false，会让"没配过"退化成默认关）。

### 2. 我的页通知开关 Section

```swift
@AppStorage(AppConfig.notificationsEnabledKey) private var notificationsEnabled = AppConfig.notificationsEnabledDefault
@State private var systemNotifDenied = false   // 系统级权限是否被拒（onAppear 查一次）

private var notificationSection: some View {
    Section {
        Toggle("截图入账通知", isOn: $notificationsEnabled)
        if systemNotifDenied {
            Button("通知权限被拒，去系统设置开启") { openSystemSettings() }
                .font(.footnote)
        }
    } header: {
        Text("通知")
    } footer: {
        Text("关闭后，截图后台入账不再弹通知；账单仍会正常记录。")
    }
}

private func openSystemSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
}
```

- 系统级被拒检测：`.task`/`.onAppear` 查 `UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied` → 置 `systemNotifDenied`（异步、@MainActor）。
- `openSettingsURLString` 跳系统设置（PRD 把"是否跳转"留 TRD → **定为做**：一致降级要求"去系统设置入口"，通知开关旁给跳转最自然）。

### 3. 统一权限降级提示（新增 `Aubade/Features/Permission/PermissionDenialNotice.swift`）

一个可复用的降级提示"文案源 + 呈现组件"，覆盖麦克风/语音/通知：

```swift
/// 被拒权限类型（决定"哪个功能受影响"文案）。
enum DeniedPermission {
    case microphoneOrSpeech   // 语音记账（麦克风/语音识别，N04 合并——两者同一功能面）
    case notification         // 截图入账通知（N06）

    var affectedFeature: String {
        switch self {
        case .microphoneOrSpeech: return "语音记账"
        case .notification: return "截图入账通知"
        }
    }
}

/// 统一降级文案：受影响功能 + 去系统设置 + 手动记账不受影响（三要素）。
enum PermissionDenialCopy {
    static func message(for p: DeniedPermission) -> String {
        "\(p.affectedFeature)需要相应权限。可到「设置」开启；手动记账不受影响。"
    }
}

/// 统一降级呈现：文案 + "去系统设置"按钮（可选内嵌于各降级点）。
struct PermissionDenialNotice: View {
    let permission: DeniedPermission
    var body: some View {
        VStack(spacing: 8) {
            Text(PermissionDenialCopy.message(for: permission))
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("去系统设置") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                .font(.footnote)
        }
    }
}
```

**接入点**：
- **语音**（`VoiceCaptureView`）：`failedMessage` 的 `.microphoneDenied/.speechDenied` 分支改为渲染 `PermissionDenialNotice(permission: .microphoneOrSpeech)`（把 `:232` 纯文本替换为统一组件 + 去设置按钮）。`.onDeviceUnavailable/.empty/.failed` 分支**不改**（非权限问题，保持原文案）。
- **通知**：我的页开关旁的"去系统设置"引导即通知降级呈现（§2 已含）；后台被拒仍静默不发（不弹 UI 是后台正确行为），可视降级收敛到我的页开关状态。
- **相册**：免授权、**不接入**（无降级需求，PRD 现状事实）。

> 统一的是**文案三要素 + 去设置入口的一致呈现**，不改各权限**申请时机**（语音仍 `SpeechVoiceTranscriber` 首次 start 内申请、通知仍首次发通知申请）。

### 4. Info.plist 权限串

- 现有麦克风/语音串（pbxproj `INFOPLIST_KEY_NS*UsageDescription`）保留。
- 通知/相册**不新增串**：通知走 `requestAuthorization`（无需 Usage 串）、相册 `PhotosPicker` 免授权。本片不动 pbxproj。

## 修改点

- **改** `Aubade/Features/Recognition/Shortcut/UNUserNotificationCenterNotifier.swift`：`send` 开头加开关 gating；加 `static notificationsEnabled(_:)`。
- **改** `Aubade/Features/AppShell/RootTabView.swift`：`ProfilePlaceholderView` 加 `@AppStorage notificationsEnabled` + `@State systemNotifDenied` + `notificationSection` + `.task` 查系统权限态，插入 List。
- **新增** `Aubade/Features/Permission/PermissionDenialNotice.swift`：`DeniedPermission` + `PermissionDenialCopy` + `PermissionDenialNotice`。
- **改** `Aubade/Features/Recognition/Voice/VoiceCaptureView.swift`：`.microphoneDenied/.speechDenied` 分支的 `statusText` 渲染改用 `PermissionDenialNotice`（其余错误分支不动）。
- **无签名改动**：`NotificationSending` 协议、`BackgroundIntakeService`、`RecordAubadeScreenshotIntent` 注入点全不改。

## 验证点

- **可编译**：发送器 + 我的页 + 降级组件 + 语音面板编译通过。
- **通知开关 gating 单测**（新增，注入独立 `UserDefaults(suiteName:)`）：
  - `notificationsEnabled` 未设 → `notificationsEnabled()` 返回 true（默认开）。
  - 设 false → 返回 false；设 true → 返回 true。
  - > 说明：`send` 真发通知依赖 `UNUserNotificationCenter`（系统），单测覆盖 gating **判定**（`static notificationsEnabled(_:)`）即可；"关时 send 提前 return 不发"由判定正确 + 代码路径审阅保证，端到端由 DEBUG 演示肉眼验（关开关 → 点演示 → 不弹通知但账入库）。
- **可观察**：
  - 我的页关通知开关 → N06「演示」跑后台入账 → **不弹通知、但账单出现在列表/统计**；重开开关 → 演示恢复弹通知（验收 6）。
  - 系统级通知权限被拒时，我的页开关旁显示"去系统设置"、点击跳系统设置页。
  - 拒麦克风/语音 → 语音面板显示统一降级（受影响功能 + 去系统设置 + 手动不受影响），App 不崩不卡，手动记账可用；相册免授权选图不受影响（验收 7）。
- **回归**：`BackgroundIntakeServiceTests`（SpyNotifier）全绿——gating 在真实发送器内、不影响 service 逻辑与 spy 断言；通知开关默认开 → 现有后台通知行为不变；语音其余错误分支文案不变。

## 不做什么

- 不改各权限申请时机（语音首次 start 申请、通知首次发申请——不动）。
- 不为相册硬造权限申请/降级（`PhotosPicker` 免授权现状）。
- 不改通知内容/构造/点击深链路由/后台入账链路（N06 已做，只在发送前加 gating）。
- 不做通知的细分开关（成功/失败/无 Key 分类开关）——一个总开关（PRD 未要求细分）。
- 不做"我的页集中展示所有权限状态列表"（PRD 留 TRD → 本片只在通知开关旁给系统被拒引导 + 语音降级点统一组件，不额外造权限中心页）。
- 不新增 Info.plist 权限串（通知/相册无需）。
