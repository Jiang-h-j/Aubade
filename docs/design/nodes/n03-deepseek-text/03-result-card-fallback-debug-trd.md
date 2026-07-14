# TRD 03 - 结果卡片（复用 TransactionEditor）+ 失败转手动 + DEBUG 调试

> 节点 PRD：`docs/prd/nodes/n03-deepseek-text-prd.md`。依赖：切片 02（识别页/状态机/入账）。
> 行号为写作时快照，可能 ±1 漂移。

## 给用户看的摘要

这一片把识别的"最后一公里"补齐——识别完能**当场看、当场改、当场撤**：

- 识别成功后不再是默默入账，而是弹出一张**结果卡片**：头部「✓ 已记一笔」，金额/方向/分类/时间/商户/备注一目了然，还能展开看「识别到的原始文本」。哪项不对当场改，点「完成」保存；这笔根本不想要，点「删除这笔」（二次确认）就撤销。
- 识别**没识别出金额**时，不再只是干提示——弹「没能识别出金额」，点「转手动填写」直接跳到手动记账页，且**把原文带进备注**，你补个金额就能记。
- 网络失败/超时也能选「重试」或「转手动」。
- 顺带给开发者调试菜单加两个开关：填/清 DeepSeek Key（真机填真 Key 自测）、切换 mock 识别结果（成功/失败/无金额），方便把上面这些路径一条条点出来看。

## 本 TRD 负责什么

识别结果的完整交互（PRD 目标 5，需求范围 §5/§7-转手动/§8）：

1. **结果卡片**：识别成功后（切片 02 现为 dismiss 回记账页）改为**弹结果卡片** = 复用 `TransactionEditor` 的 `.edit(tx)` 模式（tx 已入账），预填识别结果，头部示意"已记一笔"。
2. **TransactionEditor 新增折叠原文 Section**：消费其已声明的 `rawText` 参数（`:24`，当前 body 未渲染），edit 模式且 `rawText != nil` 时显示可折叠原文（**不改签名**）。
3. **结果卡片 onDelete = 撤销入账**：注入二次确认 → `LedgerStore.delete(tx)`。
4. **失败转手动带原文**：`.noAmount` 等失败 → 「转手动填写」进 `ManualEntryView` 变体，用原文预填 `note`；网络类失败加"重试"。
5. **DEBUG 调试**：`DebugMenuView` 补写/清 Key + mock 解析行为开关。

## 当前代码事实与上下游

- **`TransactionEditor`**（`Aubade/Features/Editor/TransactionEditor.swift:16`）：`EditorMode`（`:5`）= `.create(direction:)` / `.edit(Transaction)`。body（`:70-101`）字段序 amount/direction/category/date/merchant(showsMerchant)/note + `if let onDelete { deleteSection }`（`:79`）。**`rawText: String?`（`:24`）已声明、init 已接（`:35/:40`），但 body 未渲染**——本片新增折叠原文 Section。`showsMerchant`（`:51`）edit 模式为 true（识别结果需显示商户）。`deleteSection`（`:163`）已是 `role:.destructive` 按钮。
- **`EditorActions`**（`Aubade/Features/Editor/EditorActions.swift:7`）：`makeUpdate(store:tx:)`（`:11`）回写 amount/direction/category/occurredAt/merchant/note（**不含 cardTail/source/rawText**——结果卡片"完成"走 update 时，这三字段保持入账时的值，正确）；`makeDelete(store:tx:)`（`:26`）删 tx。二次确认 UI 由调用方套（`:25` 注释）。
- **`RecordTabView` 编辑 sheet 范式**（`:53` `.sheet(item:$editingTransaction)` / `:131` `editSheet`）：`.edit(tx)` + `EditorActions.makeUpdate`。结果卡片可仿此，但需注入 `rawText` + `onDelete`。
- **`TransactionEditor` 现有调用点（3 处，均受默认参数保护、加可选参数零影响）**：`ManualEntryView:14`（`.create`）、`RecordTabView.editSheet:134`（`.edit`）、`TransactionDetailView:23`（`.edit`，且 `:27` 已注入 `onDelete` + `:29` `.confirmationDialog` 二次确认——N01 已落地的 onDelete+确认范式，本片复用同构）。
- **`ManualEntryView`**（`Aubade/Features/Record/ManualEntryView.swift:8`）：`.create(.expense)` + `createTransaction(source:.manual)`；当前无 init 参数，唯一调用 `ManualEntryView()`（`RecordTabView:51`）。转手动需**带原文预填 note**（见 §4，经 TransactionEditor 新增 `initialNote` 实现）。
- **切片 02 产物**：`TextRecognitionView`（识别成功现 dismiss）、`RecognitionPhase`（`.failed(RecognitionError)`）、`MockTransactionParser`。
- **`DebugMenuView`**（`Aubade/Debug/DebugMenuView.swift:7`，`#if DEBUG`）：已有 N02 调试 Section 范式（`:46-51`）+ `lastMessage`（`:13`）。本片补 Key/mock Section。
- **demo 契约**：`app.js:378` `openResultCard`（头部「✓ 已记一笔」/ 金额方向分类时间商户备注 / 折叠原文 `r-raw` / 删除+完成）；删除二次确认（`:424-428`「删除这笔账单？删除后无法恢复」）；完成回写（`:416-422`）；失败转手动 `recognizeFailed`（`app.js:370-374`）→ `openManualForm({note: raw 去[前缀]})`（`:373`）。

## 设计方案

### 1. TransactionEditor 新增折叠原文 Section（改 `TransactionEditor.swift`）

在 body（`:70-100` Form 内）`noteSection` 之后、`deleteSection` 之前插入：

```
// 识别原文折叠区（原型 §4.3）：仅当注入 rawText 时渲染（手动入口 rawText=nil 不显示）。
if let rawText, !rawText.isEmpty {
    Section {
        DisclosureGroup("查看识别到的原始文本") {
            Text(rawText).font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- **纯增量、不改签名/init/现有 Section**：`rawText` 参数早已声明（`:24`）、手动入口恒传 nil（`ManualEntryView` 不传 → 默认 nil → 不渲染），仅结果卡片传入即显示。edit 模式下与其它 Section 共存，字段序对齐原型 §4.3（原文置末，折叠默认收起）。

### 2. 结果卡片 = 预填的 TransactionEditor（`.edit(tx)`）

**关键决策：识别成功 → 先入账（切片 02 已做）→ 拿到入账后的 `Transaction` → 弹 `.edit(tx)` 结果卡片。** 走 edit 模式而非新增 `.result` 模式，理由：

- demo `recognizeFlow` 就是"先 push bill 再 openResultCard"（`app.js:363-366`），账单已存在；结果卡片的"删除"= 撤销这笔已存在的账单，天然是 edit 语义。
- `.edit(tx)` 直接复用 `EditorActions.makeUpdate`（完成）/`makeDelete`（删除），`TransactionDraft(from: tx)`（`:26`）自动回填，无需新增 `EditorMode` case 与新回填路径——最小改动。

**改切片 02 的成功分支**：`recognize()` 成功入账拿到 `tx` 后，不 `dismiss`，而是 `@State private var resultTx: Transaction?` = tx 触发结果卡片：

```
// TextRecognitionView 新增：
@State private var resultTx: Transaction?
// 成功分支（替换切片 02 的 dismiss）：
let tx = try store.createTransaction(...source:.text, rawText: trimmed)
phase = .idle
resultTx = tx        // 触发结果卡片
// body 挂：
.sheet(item: $resultTx) { tx in resultCard(for: tx) }
```

```
private func resultCard(for tx: Transaction) -> some View {
    let store = LedgerStore(modelContext)
    return TransactionEditor(
        mode: .edit(tx),
        categories: categories,
        onSave: EditorActions.makeUpdate(store: store, tx: tx),   // 完成=回写
        onDelete: { confirmingDelete = true },                    // 删除=先弹二次确认（见 §3），确认后才 delete
        rawText: tx.rawText                                       // 折叠原文（=入账时落的用户原文）
    )
}
// 结果卡片关闭（resultTx 归 nil）后回记账页：识别页 onChange 主动 dismiss。
// .onChange(of: resultTx) { _, new in if new == nil { dismiss() } }
```

- **头部标题：从简，接受 edit 模式默认标题"编辑账单"，不为它加参数。** 虽然本片已（经用户拍板）放宽"可加向后兼容可选参数"，但那是为验收 6 的 note 预填这一**功能必需**开的口；demo 的「✓ 已记一笔」头部纯属视觉锦上添花，不值得再为它加第二个可选参数。结果卡片头部沿用 `.edit` 的"编辑账单"（若后续确需定制编辑器标题，归 N07 统一处理）。本片对 `TransactionEditor` 的改动 = 新增折叠原文 Section（§1）+ 新增 `initialNote` 可选参数（§4，供转手动预填），**均向后兼容、N01 现有调用零影响**。
- 结果卡片改分类/金额等后「完成」→ `makeUpdate` 回写 → `@Query` 驱动记账页/账单/剩余/统计自动刷新（验收 2）。
- **关闭链**：`TransactionEditor.save()`（`:172`）内部 `dismiss()` 只关结果卡片这层 sheet → `resultTx` 经 `.sheet(item:)` 绑定自动归 nil → 识别页 `onChange(of: resultTx)` 检测到 nil 后 `dismiss()` 自身（`.fullScreenCover`），回到记账页。删除路径同理（确认删除后手动置 `resultTx = nil`）。

### 3. 删除二次确认（撤销入账）

`TransactionEditor.deleteSection`（`:163`）当前直接 `delete()`。二次确认由调用方套（`EditorActions.swift:25` 注释明确"UI 由调用方套"）。结果卡片的 `onDelete` 需先弹确认：

- 在 `TextRecognitionView` 用 `@State private var confirmingDelete = false` + `.confirmationDialog` 或 `.alert`，「删除这笔」→ 确认 → `store.delete(tx)` + `resultTx = nil`（关卡片，经关闭链回记账页）。
- 或将二次确认封进注入的 `onDelete` 闭包外层（编辑器点删除 → 调 onDelete → 闭包内触发确认态）。**决策：确认态放识别页**（editor 的 `deleteSection` 保持"点即调 onDelete"，onDelete 闭包置 `confirmingDelete=true`，识别页 `.alert` 确认后真正 `delete`）——与 demo `r-del`（`app.js:424-428`）二次确认一致，且不改 editor 删除按钮语义。**此二次确认范式 N01 `TransactionDetailView`（`:27` 注入 onDelete + `:29` `.confirmationDialog`）已落地验证**，本片复用同构写法（结果卡片是识别链路上的 onDelete 注入方，非全项目首个）。

文案对齐 demo：「删除这笔账单？」/「删除后无法恢复」/「删除」(destructive)/「取消」。

### 4. 失败转手动带原文（改失败分支 + TransactionEditor 加 initialNote 可选参数）

切片 02 失败仅提示；本片补转手动 + 重试。转手动要把识别原文**预填进备注**（验收 6），需让 `.create` 表单接受初始 note：

- **`TransactionEditor` 新增 `initialNote: String? = nil`**（用户已拍板放宽 PRD"不改签名"为"允许追加向后兼容可选参数"，见本片"关于 PRD 签名措辞"）：`init` 加该参数（默认 nil），`.create` 分支构造草稿时把它写进 `draft.note`：
  ```
  init(mode:categories:onSave:onDelete:rawText:initialNote: String? = nil) {
      ...
      case .create(let direction):
          var d = TransactionDraft(direction: direction, occurredAt: Date())
          if let initialNote { d.note = initialNote }        // 仅 create 预填；edit 从 tx 回填不受影响
          _draft = State(initialValue: d)
      case .edit(let tx): _draft = State(initialValue: TransactionDraft(from: tx))
  }
  ```
  - **默认 nil → N01 现有 3 处调用（`ManualEntryView:14`、`RecordTabView editSheet:134`、`TransactionDetailView:23`）零影响**：都不传 initialNote，`.create` 走 `if let` 不进、`.edit` 分支本就不碰它。`TransactionDraft.note`（`:13`）是可变 `var`，直接赋值即可，**不改 `TransactionDraft`**。
- **`ManualEntryView` 加 `init(prefillNote: String? = nil)`**：把 `prefillNote` 透传给 `TransactionEditor(... initialNote: prefillNote)`。现有唯一调用 `ManualEntryView()`（`RecordTabView:51`）默认 nil、不受影响。转手动即 `ManualEntryView(prefillNote: text)`。
- **失败 alert 分支**（`.failed(error)`）：

| 错误 | 按钮 |
|---|---|
| `.noAmount` | 「转手动填写」（带原文进 ManualEntryView）/「取消」 |
| `.network`/`.timeout`/`.invalidResponse` | 「重试」(重新 `recognize()`)/「转手动填写」/「取消」 |

- **原文预填**：转手动带入的是识别页输入框的 `text`（用户原文），对齐 demo（demo 去 `[xxx]` 前缀是因其 raw 带模拟前缀；本片原文就是用户输入，无前缀，直接带入 note）。
- 转手动经 `.sheet`/`.fullScreenCover` 呈现 `ManualEntryView(prefillNote: text)`，保存走既有 `.manual` 落库。

### 5. DEBUG 调试（改 `DebugMenuView.swift`，`#if DEBUG` 内）

仿 N02 Section 范式（`:46-51`）新增：

```
Section("N03 调试（DeepSeek Key / mock 识别）") {
    // Key：写样例/清除 + 显示 isConfigured
    Text("Key 状态：\(KeychainStore.shared.isConfigured ? "已配置" : "未配置")")
    Button("写入测试 Key") { KeychainStore.shared.setDeepSeekKey("sk-debug-xxx"); lastMessage = "已写 Key" }
    Button("清除 Key", role: .destructive) { KeychainStore.shared.clearDeepSeekKey(); lastMessage = "已清 Key" }
    // mock 行为开关：写入 @AppStorage / 静态开关，供 RecordTabView 注入 mock 时读取
    Picker("mock 识别结果", selection: $mockBehavior) {
        Text("成功").tag(...); Text("无金额").tag(...); Text("网络失败").tag(...); Text("超时").tag(...)
    }
}
```

- **mock 行为如何贯通到识别页**：DEBUG 下 `RecordTabView` 注入 `MockTransactionParser(behavior: 读自 @AppStorage 的 mockBehavior)`。用 `@AppStorage("debug.mockBehavior")` 存枚举 rawValue（仅 DEBUG 用，非 Key、非业务数据，可入 UserDefaults）。
- 真机填**真实 Key**（非 debug 占位）后，`RecordTabView` 生产分支用 `DeepSeekClient` → 可真机联网自测（用户后续自测，不阻塞验收）。

## 修改点

| 文件 | 改动 |
|---|---|
| `Aubade/Features/Editor/TransactionEditor.swift` | ① body 新增折叠原文 Section（消费已声明的 `rawText`）；② init 新增 `initialNote: String? = nil`，`.create` 分支预填 `draft.note`（供转手动带原文）。**两处均向后兼容默认参数，N01 现有 3 处调用零影响；不改 `TransactionDraft`** |
| `Aubade/Features/Recognition/TextRecognitionView.swift` | 成功分支改 dismiss 为弹结果卡片（`.sheet(item:$resultTx)`）+ 关闭链 `onChange(of:resultTx)`；删除二次确认 `.alert`；失败分支补转手动/重试按钮 |
| `Aubade/Features/Record/ManualEntryView.swift` | 新增 `init(prefillNote: String? = nil)`，透传 `TransactionEditor(initialNote:)`（默认 nil，现有 `ManualEntryView()` 调用不受影响） |
| `Aubade/Debug/DebugMenuView.swift` | 新增 N03 调试 Section（写/清 Key + mock 行为 Picker）；`RecordTabView` DEBUG 注入读 `@AppStorage` mock 行为 |
| `AubadeTests/ResultCardActionsTests.swift` | **新增**：完成回写 / 删除撤销 / 转手动预填单测（见验证点） |

## 验证点

单测（`@MainActor`，内存容器**持有 container**）：

1. **完成回写（验收 2）**：入账 tx（source=.text）→ 构造改了金额/分类的 draft → `EditorActions.makeUpdate` → `tx.amount/category` 更新，`tx.source==.text` 与 `tx.rawText` **保持不变**（makeUpdate 不碰这两字段）。
2. **删除撤销（验收 3）**：入账 tx → `store.delete(tx)` → `fetch(Transaction.self).isEmpty`。
3. **转手动预填（验收 6）**：`TransactionEditor(mode:.create(...), initialNote:"原文X")` 的初始 `draft.note == "原文X"`；不传 `initialNote` 时 `.create` 的 `draft.note == ""`（N01 手动入口不受影响）。
4. **折叠原文渲染**：（快照/逻辑）`rawText != nil` 时 editor 渲染原文 Section；nil（手动）不渲染——以 `showsMerchant` 同风格的计算属性或视图存在性断言（或留肉眼）。

肉眼（模拟器，DEBUG mock）：

5. **结果卡片全交互（验收 2/4）**：识别成功 → 弹结果卡片（标题"编辑账单"，头部「✓ 已记一笔」视觉不做，见 §2），金额 256/分类/时间/商户京东商城预填；展开「查看识别到的原始文本」见原文；改分类 → 完成 → 记账页/账单/剩余/统计（N02）同步变。
6. **删除撤销（验收 3）**：结果卡片「删除这笔」→ 二次确认 → 确认 → 账单消失、列表/剩余/统计同步。
7. **无金额转手动（验收 6）**：DEBUG mock 切"无金额" → 识别 → 「没能识别出金额」→「转手动填写」→ 手动页 note 已带原文 → 补金额可记；**不误记脏账**。
8. **网络失败重试（验收 7）**：mock 切"网络失败" → 失败提示带「重试」→ 切回"成功" → 重试成功入账；原文保留。
9. **卡尾号不暴露（已确认约定 6）**：结果卡片编辑 UI **无卡尾号字段**（cardTail 已落库但不在 editor 显示），可经账单详情或 DEBUG 侧证 cardTail=1234 已存。

## 关于 PRD "不改 TransactionEditor 签名" 措辞（自评审后经用户拍板放宽）

PRD `:79`/`:140` 原文写"不改 `TransactionEditor` 签名（仅传入其已有参数）"。但验收 6 要求"识别失败转手动、原文预填进备注"，而 `TransactionEditor.create` 表单的 `note` 在 init 内部初始化、**无外部注入口**——不加参数则验收 6 无法实现。自评审时提请用户裁决，**用户拍板放宽为"允许对 `TransactionEditor` 追加向后兼容的可选参数"**。据此本片新增 `initialNote: String? = nil`（§4）。

边界：放宽仅限**向后兼容默认参数**（现有调用方零影响），不改现有必填参数、不改 `TransactionDraft`；纯视觉诉求（如"✓已记一笔"标题）仍从简不加参数（§2）。此放宽属 N03 局部决策，PRD 该措辞相应理解为"允许追加向后兼容可选参数"。

## 不做什么

- **不新增 `EditorMode.result`**：结果卡片走 `.edit(tx)` 复用现有回填/update/delete（本 TRD 决策）。
- **不改 `EditorActions.makeUpdate` 回写字段集**：cardTail/source/rawText 不进 update（入账时已定，完成时保持）。
- **不加编辑器标题定制参数**：结果卡片头部沿用"编辑账单"，「✓已记一笔」视觉不做（§2）。
- **不改 `TransactionDraft`**：note 预填在 `TransactionEditor.create` 分支赋值现有可变 `note`，不动 `TransactionDraft` 结构。
- **不做** 卡尾号编辑字段（已确认约定 6，仅落库）；我的页 Key 行/完整状态展示（N07）；语音/截图（N04/N05）；真实 Key 联网验收门禁（用户自测）。
- **不改** N01/N02 既有行为、`LedgerStore` 现有方法签名、`imageRef`（恒 nil）。
