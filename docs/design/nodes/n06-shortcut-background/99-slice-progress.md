# TRD 切片进度

- 最近完成 TRD：`无（N06 刚出 TRD，尚未开发）`
- 下一个 TRD：`docs/design/nodes/n06-shortcut-background/01-background-intake-intent-trd.md`
- 更新时间：2026-07-15（TRD 定稿，待自评审 + 用户评审）

## 切片清单

| 切片 | 文件 | 单一职责 | 状态 |
|---|---|---|---|
| 01 | `01-background-intake-intent-trd.md` | 后台链路核心单元 `BackgroundIntakeService`（脱 View 编排 OCR→读 Key→解析入账→发通知意图）+ `NotificationSending`/`IntakeNotification` 抽象 + `RecordAubadeScreenshotIntent`(AppIntent)+`AubadeShortcuts` + `AppModelContainer` 共享容器持有点 + 后台各分支全单测 | 待开发 |
| 02 | `02-notification-deeplink-demo-trd.md` | `UNUserNotificationCenterNotifier` 真实通知 + 权限/被拒降级 + `TemporaryImageStore` 失败原图留存清理 + `AppDelegate`/`DeepLinkRouter` 点击深链（成功→编辑卡片/失败→补录带原文原图/无Key→Key配置）+「演示」按钮接后台链路 + DEBUG 端到端 | 待开发 |

## 开发顺序与依赖

- 切片 01 先行：脱 View 纯逻辑底座，后台各分支单测焊死"不落脏账"与"发哪类通知"；App Intent 只是薄壳；共享容器持有点是后台拿 context 的唯一合法通道。**本片可独立编译**（Intent `perform()` 先注入 `NoOpNotifier`/`NoOpFailedImageStore` + TODO(切片02)）。
- 切片 02 依赖 01：把通知协议用真实 `UNUserNotificationCenter` 实现、接点击深链、接演示按钮、实现原图留存清理。可观察验收（DEBUG 演示 mock 端到端）在此片达成。

## 关键实现约束（开发时必守，来自代码事实核对）

1. **共享容器持有点必须 `let` 长期持有容器再取 `.mainContext`**——绝不链式 `makeContainer().mainContext`（N00 SIGTRAP 悬垂陷阱，见 memory `swiftdata-dangling-context-crash`）。
2. **`recognizeAndSave` 无 imageRef 参数**（`TextRecognitionView.swift:18-24`）：成功入账 imageRef 恒 nil；失败保留原图**不经** recognizeAndSave，由 `BackgroundIntakeService` 失败分支单独 `imageStore.save`。
3. **零签名改动**：`recognizeAndSave`/`TextRecognizing`/`DeepSeekClient`/`LedgerStore.createTransaction` 不改；只新增 `source: .screenshotShortcut` 调用方；`ManualEntryView` 若加原图入参照 `prefillNote` 加带默认值参数。
4. **`RecognitionResultCard` 是 private**（`TextRecognitionView.swift:268`）：通知成功点击落点不碰它，复用 `RecordTabView` 的编辑 sheet（补 `onDelete` 使可删）。
5. **分类模型类型名 `LedgerCategory`**（非裸 `Category`，见 memory `aubade-model-category-naming`）。
6. **测试宿主可真实读写 Keychain**（`MockParserTests.swift:53-69` 已证）：无 Key 单测直接 `KeychainStore.shared` clear/set 造态，不抽 `KeyProviding` 协议。
7. **前缀 `[快捷指令]`**（对齐 N05 `[截图识别]`/N04 `[语音转文字]`）；`.screenshotShortcut` 当前零调用方，N06 首次用。

## 验证情况

- 单测：待开发（切片 01 `BackgroundIntakeServiceTests` 后台各分支；切片 02 notifier userInfo 构造/imageStore/router 解析）。
- jflow-review：TRD 自评审待运行。

## 遗留风险和注意事项

- **真机验证项（不阻塞节点门禁，用户自测）**：真快捷指令传图机制、后台执行时间预算能否容纳一次 DeepSeek 往返、后台通知交付。**若真机实测后台预算普遍不足 → 触发技术基线 §7.3 方案 B 降级**（后台只做 OCR + 存原文 + 发通知，解析入账改前台完成），本节点默认不实现，届时另行调整 TRD。
- `IntentFile` 传图与 `image.data` 取值的真机行为属真机自测；本片按 `IntentFile.data` 编译交付。
- 深链"点通知跳转"在 App 冷启/后台唤醒/前台三态的时序，模拟器可 mock 部分（本地通知可在模拟器触发点击），真机全覆盖自测。

## 下一次开发

从切片 01 `01-background-intake-intent-trd.md` 开始（`按照 TRD 开发`）。分支已在 `feat/n06`。
