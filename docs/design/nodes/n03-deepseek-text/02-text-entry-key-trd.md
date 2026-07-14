# TRD 02 - 文本识别入口 + 无 Key 拦截 + 最小 Key sheet + 识别状态机

> 节点 PRD：`docs/prd/nodes/n03-deepseek-text-prd.md`。依赖：切片 01（解析协议/归一/错误/mock/Keychain）。
> 行号为写作时快照，可能 ±1 漂移。

## 给用户看的摘要

这一片把「文本识别」入口**真正接通**——从点击到入账，一条链路能走：

- 进「记账」Tab，点「📋 文本识别」（原来弹"敬请期待"），进入一个粘贴页：一个大输入框 + 「📋 读取剪贴板」（一键带入刚复制的文字）+ 「识别并记账」。
- 点识别，如果还没配 DeepSeek Key，会弹提示"识别类记账要用 DeepSeek…手动记账不受影响"，点「去填写」当场弹一个小窗填 Key、保存（存进钥匙串），再点识别就不拦了。
- 识别时全屏转圈"正在识别文本…"，识别中不能重复点。
- 识别成功就**直接记成一笔账**，回到记账页——最近记录里立刻多出这一笔（下一片再给它配可当场改的结果卡片）。
- 识别失败（没网/超时/没识别出金额）会提示对应原因，不会崩、不会乱记（转手动补录的完整交互在下一片）。

## 本 TRD 负责什么

文本识别入口主链路（PRD 目标 4/6，需求范围 §4/§6-sheet+拦截/§7-失败提示）：

1. `RecordTabView`「文本识别」`EntryButton`（`:73`）**接线**：替换"敬请期待"占位为进入文本识别页。
2. **文本识别页** `TextRecognitionView`：粘贴 textarea + 「读取剪贴板」（`UIPasteboard`）+ 「识别并记账」。
3. **识别状态机**（`idle → 无 Key 拦截 / 识别中 → 成功入账 / 失败提示`），识别中禁重复提交。
4. **无 Key 拦截** + **最小 Key sheet**（`KeySetupSheet`）：无 Key 时拦截 →「去填写」直开 sheet → 写 Keychain。
5. **识别成功入账**：`LedgerStore.createTransaction(source:.text, rawText:...)` + 归一（切片 01）；本片入账后回记账页（最近记录可见），**结果卡片留切片 03**。
6. **失败提示**：按 `RecognitionError` 分支给文案；本片先做提示 + 不产生脏账，**转手动带原文留切片 03**。

## 当前代码事实与上下游

- **入口挂载点**：`RecordTabView`（`Aubade/Features/Record/RecordTabView.swift:8`）四入口网格，「📋 文本识别」`EntryButton`（`:73`）现为 `placeholderEntryTitle = "文本识别"` 弹敬请期待（`:56-63`）。本片改其 action。已有范式：`@Binding var selection`（`:10`）、`@Environment(\.modelContext)`（`:12`）、`@Query categories`（`:18`，`sort:\.sortOrder` 全量）、`.sheet(isPresented:)`（`:50`）/`.sheet(item:)`（`:53`）、`@State` 驱动 sheet（`:20-22`）。
- **入账落库（消费，不改签名）**：`LedgerStore.createTransaction(amount:direction:occurredAt:category:merchant:note:cardTail:source:rawText:imageRef:)`（`Store/LedgerStore.swift:48`）已含全字段。`ManualEntryView`（`Features/Record/ManualEntryView.swift:14-31`）示范 `.create` + `createTransaction(source:.manual)` 的落库写法——本片识别入账仿此但 `source=.text` 且带 `rawText/merchant/cardTail`。
- **切片 01 产物（消费）**：`TransactionParsing` 协议、`ParsedTransaction`、`RecognitionError`、`RecognitionNormalizer`、`MockTransactionParser`、`KeychainStore`（`isConfigured`/`setDeepSeekKey`/`deepSeekKey`）。
- **解析器注入**：本片需把 `TransactionParsing` 注入识别页。为可测/可 DEBUG 切换，采用**环境注入**：识别页持有 `let parser: TransactionParsing`，由 `RecordTabView` 构造时传入（生产传 `DeepSeekClient()`，DEBUG/预览传 `MockTransactionParser`）。DEBUG 切换 mock 行为的开关在切片 03。
- **分类清单来源**：`RecordTabView` 已有的 `@Query categories`（`:18`）直接传给识别页 → 既用于 `parser.parse(text:categories:)`，也用于 `RecognitionNormalizer.category` 兜底。
- **demo 交互契约**：`app.js:323` `openTextInput`（textarea placeholder 举例工行短信 / 读剪贴板填 `SAMPLE_TEXT` / 识别前 `needKeyBlocked` 拦截 / 空文本 toast）；`app.js:350` `recognizeFlow`（全屏 spinner「正在识别文本…／DeepSeek 提取金额与分类」，`setTimeout` 后成功入账）；`app.js:301` `needKeyBlocked`（文案 + 「去配置」——本片按已确认约定 8 改为「去填写」直开 sheet，**裁去"我的→Key"指向**）。

## 设计方案

新增文件均在 `Aubade/Features/Recognition/`（切片 01 建的目录）。

### 1. 识别状态机（`Recognition/RecognitionState.swift`）

视图局部 `@State` 驱动，不引入额外框架：

```
enum RecognitionPhase: Equatable {
    case idle                       // 编辑文本，可提交
    case recognizing                // 识别中：禁重复提交、显示 spinner
    case failed(RecognitionError)   // 失败：显示对应文案（转手动在切片 03）
    // 成功不设独立 phase——成功即入账并 dismiss 回记账页（切片 03 才在成功后弹结果卡片）
}
```

- `recognizing` 时「识别并记账」按钮 disabled + 全屏盖 spinner（禁重复提交，PRD §4）。
- `failed` 承载 `RecognitionError`，文案见下表。

### 2. 文本识别页（`Recognition/TextRecognitionView.swift`）

```
struct TextRecognitionView: View {
    let parser: TransactionParsing            // 注入（生产 DeepSeekClient / 测试预览 Mock）
    let categories: [LedgerCategory]          // RecordTabView 的 @Query 传入
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var phase: RecognitionPhase = .idle
    @State private var showingKeySheet = false
    @State private var showKeyBlockedAlert = false

    // body：NavigationStack { Form/VStack { textarea; 读剪贴板按钮; 识别并记账按钮 } }
    //   + 识别中全屏 spinner overlay（.recognizing）
    //   + 无 Key 拦截 alert（showKeyBlockedAlert）：「去填写」→ showingKeySheet=true
    //   + .sheet(isPresented:$showingKeySheet){ KeySetupSheet() }
    //   + 失败提示 alert（.failed）
}
```

**识别动作** `recognize()`：

```
func recognize() {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { /* toast/alert "请先粘贴或输入文字" */ return }
    guard KeychainStore.shared.isConfigured else { showKeyBlockedAlert = true; return }  // 无 Key 拦截
    guard phase != .recognizing else { return }                                          // 禁重复提交
    phase = .recognizing
    Task {
        do {
            let parsed = try await parser.parse(text: trimmed, categories: categories)
            let amount = try RecognitionNormalizer.amount(parsed.amountText)             // 无金额→抛 .noAmount
            let now = Date()
            let occurredAt = RecognitionNormalizer.occurredAt(parsed.occurredAt, now: now)
            let category = RecognitionNormalizer.category(name: parsed.categoryName,
                              direction: parsed.direction, in: categories)
            let store = LedgerStore(modelContext)
            try store.createTransaction(
                amount: amount, direction: parsed.direction, occurredAt: occurredAt,
                category: category, merchant: parsed.merchant, cardTail: parsed.cardTail,
                source: .text, rawText: trimmed)                                          // 落原文=用户输入文本
            phase = .idle
            dismiss()      // 本片：回记账页，最近记录 +1（切片 03 改为弹结果卡片）
        } catch let e as RecognitionError {
            phase = .failed(e)
        } catch {
            phase = .failed(.invalidResponse)   // 归一/落库意外统一归为非法响应，不崩
        }
    }
}
```

- **`rawText` 落用户输入的 `trimmed` 原文**（不是 mock 的 raw；真实链路里用户粘的就是原文）。
- **无 Key 拦截先于识别**：`isConfigured==false` 直接弹 alert 不进 `Task`（对齐 demo `needKeyBlocked` 早退）。
- 归一 `amount` 抛 `.noAmount` 被同一 catch 捕获 → `failed(.noAmount)`。
- 呈现方式：识别页用 **`.sheet` 全屏 push 皆可**；本片选 **`.fullScreenCover`**（识别是独立任务流，与 demo 的整页 `openTextInput` 一致，且识别中 spinner 需盖满）。挂在 `RecordTabView`。

### 3. 无 Key 拦截文案（已确认约定 8：不指向 N07 我的页 Key 行）

```
.alert("需要先配置 DeepSeek", isPresented: $showKeyBlockedAlert) {
    Button("去填写") { showingKeySheet = true }
    Button("取消", role: .cancel) { }
} message: {
    Text("识别类记账要用到 DeepSeek。填入你的 API Key 即可，手动记账不受影响。")
}
```

- 文案**裁去** demo 的"请在『我的 → DeepSeek API Key』里填写"——我的页 Key 行属 N07 未建，避免死链。「去填写」直开 `KeySetupSheet`。

### 4. 最小 Key sheet（`Recognition/KeySetupSheet.swift`）

```
struct KeySetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keyText = KeychainStore.shared.deepSeekKey ?? ""
    // NavigationStack { Form { SecureField("DeepSeek API Key", text:$keyText); 说明脚注 } }
    //   toolbar: 取消 / 保存（keyText 去空非空才 enable）
    //   保存: KeychainStore.shared.setDeepSeekKey(trimmed); dismiss()
}
```

- 用 `SecureField`（Key 不明文回显）。保存写 Keychain（切片 01 `setDeepSeekKey` 写侧唯一）。
- **最小闭环**：能填、能存、能被 `isConfigured`/`DeepSeekClient` 读到即可。完整"已配置✓/去填写"状态卡、我的页 Key 行、联网测活 → N07。

### 5. 识别中态 + 失败文案

- **识别中**：`.recognizing` 时全屏半透明遮罩 + `ProgressView` + 「正在识别文本…」+「DeepSeek 提取金额与分类」（对齐 demo `recognizeFlow` 文案），期间按钮 disabled。
- **失败提示**（本片 alert 提示，转手动/重试交互切片 03）：

| 错误 | 文案 | 本片行为 |
|---|---|---|
| `.noAmount` | 「没识别出金额」原文已保留 | alert 提示（切片 03 加"转手动填写"带原文） |
| `.network` | 「网络连接失败」请检查网络后重试 | alert 提示（切片 03 加"重试/转手动"） |
| `.timeout` | 「识别超时」请重试 | 同上 |
| `.invalidResponse` | 「识别失败」返回内容无法解析 | 同上 |

- 本片失败**只提示、不产生脏账、不丢 `text`**（原文留在输入框，用户可改后重试）。完整"转手动带原文预填"是切片 03。

### 6. RecordTabView 接线

- `EntryButton(emoji:"📋", title:"文本识别")` 的 action：`:73` 从 `placeholderEntryTitle = "文本识别"` 改为 `showingTextRecognition = true`。
- 新增 `@State private var showingTextRecognition = false` + `.fullScreenCover(isPresented:)` 呈现 `TextRecognitionView(parser: <注入>, categories: categories)`。
- **parser 注入**：生产用 `DeepSeekClient()`；DEBUG/预览用 `MockTransactionParser`。本片先用编译期条件（`#if DEBUG` 传 mock）保证模拟器可肉眼走通；DEBUG 运行时切换 mock 行为在切片 03。
- 其余三入口（截图/语音）保持占位不动。

## 修改点

| 文件 | 改动 |
|---|---|
| `Aubade/Features/Recognition/RecognitionState.swift` | **新增**：`RecognitionPhase` |
| `Aubade/Features/Recognition/TextRecognitionView.swift` | **新增**：识别页 + `recognize()` 状态机 + 入账 |
| `Aubade/Features/Recognition/KeySetupSheet.swift` | **新增**：最小 Key 填写 sheet |
| `Aubade/Features/Record/RecordTabView.swift` | 「文本识别」`EntryButton`（`:73`）接线；加 `@State showingTextRecognition` + `.fullScreenCover`；注入 parser |
| `AubadeTests/RecognitionEntryTests.swift` | **新增**：mock 注入下入账落库单测（见验证点） |

## 验证点

单测（`@MainActor`，内存容器**持有 container**，`MockTransactionParser` 注入脱网）——把 `recognize()` 的落库核心抽为可测函数（或直接测"mock 解析 → 归一 → createTransaction"组合）：

1. **成功入账**：mock `.success` → 归一 → `createTransaction`；`fetch(Transaction.self)` 得 1 笔，`amount==Decimal(string:"256.00")`（无浮点误差）、`direction==.expense`、`merchant=="京东商城"`、`cardTail=="1234"`、`source==.text`、`rawText==` 输入原文、`category` 命中或兜底。
2. **无金额不入账**：mock `.noAmount`（或 amountText=""）→ 归一抛 `.noAmount` → **库中 0 笔**（不产生脏账）。
3. **网络/超时/非法响应不入账**：mock `.network/.timeout/.invalidResponse` → 对应 `RecognitionError` → 库中 0 笔。
4. **时间不越未来**：mock 返回未来 occurredAt → 入账 tx.occurredAt <= now。

肉眼（模拟器，DEBUG 注入 mock）：

5. **入账链路（验收 1）**：记账页点「文本识别」→ 粘贴页 →「读取剪贴板」带入样例 → 「识别并记账」→ 全屏 spinner → 回记账页，最近记录 +1 笔（¥256、京东商城）。（**注**：此"回记账页"是本片的临时终态；切片 03 把成功后改为弹结果卡片，届时本肉眼场景被结果卡片替代，回归时以切片 03 验证点 5 为准。）
6. **无 Key 拦截（验收 5）**：Keychain 无 Key 时点识别 → 弹拦截 alert（文案不含"我的→Key"）→ 不识别；「去填写」→ Key sheet → 填保存 → 再点识别不再拦截；全程「手动输入」正常可用。
7. **失败提示（验收 7 半）**：DEBUG 切 mock 到 network/noAmount → 点识别 → 对应失败文案，库中无脏账，输入框原文还在。

## 不做什么

- **不做结果卡片**：识别成功本片只入账 + 回记账页；结果卡片（复用 TransactionEditor + 折叠原文 + 改/删）在切片 03。
- **不做失败转手动带原文**：本片失败只提示；「转手动填写」带原文预填、"重试"入口在切片 03。
- **不做 DEBUG 运行时 mock 开关**：本片用编译期 `#if DEBUG` 注入 mock；运行时切成功/失败/无金额开关在切片 03。
- **不做** 我的页 Key 行 / 完整状态展示 / Key 校验（N07）；语音/截图入口（N04/N05）。
- **不改** `TransactionEditor`、`LedgerStore` 签名、N01/N02 既有行为。
