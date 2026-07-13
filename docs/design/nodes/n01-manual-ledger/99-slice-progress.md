# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n01-manual-ledger/02-editor-manual-entry-trd.md`
- 下一个 TRD：`docs/design/nodes/n01-manual-ledger/03-ledger-list-filter-trd.md`
- 更新时间：2026-07-13T21:56:39+08:00

## 上一次 TRD 开发

N01 切片 02：打通"手动记一笔"完整闭环。新增可复用账单编辑组件 `TransactionEditor`（create 新建 / edit 既有双模式，字段集对齐原型 §4.3，为 N03~N06 识别结果卡片预留复用点）；手动记账入口 `ManualEntryView`（create 模式 + createTransaction 落库，商户恒 nil）；记账 Tab 真实视图 `RecordTabView` 替换切片 01 的 `RecordTabPlaceholder`（今日已记 chip、四入口网格仅手动可用余三占位提示、最近 4 笔 occurredAt 倒序、点击进 edit sheet 即接 updateTransaction 落库、「全部 ›」跳账单 Tab、空态占位）。编辑落库经共享 `EditorActions` 收敛为单一来源，供切片 03 列表进编辑复用。

## 涉及文件和符号

新增：
- `Aubade/Features/Editor/TransactionDraft.swift`：纯值表单模型。`init(direction:occurredAt:)` 空草稿 / `init(from tx:)` 编辑回填；`parsedAmount`（`Decimal(string:)` trim 后解析，空/非数字→nil）、`isValid`（解析成功且 >0）、`normalizedMerchant/normalizedNote`（去空白空→nil）。
- `Aubade/Features/Editor/TransactionEditor.swift`：`EditorMode`（`.create(direction:)`/`.edit(Transaction)`）+ 双模式 Form 视图。方向过滤分类按 sortOrder、切方向清空不符分类；`DatePicker(in: ...Date())` 禁未来；create 隐藏商户行、edit 显示；`onSave` 注入落库、`onDelete?` 占位钩子（本片不传）、`rawText` 预留不渲染；`isValid==false` 禁用保存。
- `Aubade/Features/Editor/EditorActions.swift`：`makeUpdate(store:tx:)` 产出 edit 的 onSave（updateTransaction 回写 draft 全字段）、`makeDelete(store:tx:)` 产出 delete 闭包（切片 03 套二次确认）。
- `Aubade/Features/Shared/AmountFormat.swift`：`signedString(_:direction:)`（NSDecimalNumber 喂 NumberFormatter 保精度，支出 `-`/收入 `+` 千分位 2 位小数）、`plainString`、`color(for:)`（收入绿/支出 .primary）。
- `Aubade/Features/Record/ManualEntryView.swift`：`@Query` 全部分类，包 `TransactionEditor(.create(.expense))`，onSave 走 `LedgerStore(modelContext).createTransaction(... source:.manual, merchant:nil)`。
- `Aubade/Features/Record/RecordTabView.swift`：`@Binding selection: AppTab` 跨 Tab；`todayCount`（allTransactions 内存过滤 isDateInToday createdAt）；`EntryButton` 四入口、`RecentTransactionRow`（CategoryStyle emoji+主 API 取色、AmountFormat 金额）；edit sheet 经 `EditorActions.makeUpdate`。
- `AubadeTests/TransactionDraftTests.swift`（13 例）、`AubadeTests/AmountFormatTests.swift`（7 例）。

改：
- `Aubade/Features/AppShell/RootTabView.swift`：record 分支 `RecordTabPlaceholder` → `RecordTabView(selection: $selectedTab)`，删除已不用的 `RecordTabPlaceholder`（保留 `LedgerTabPlaceholder` 待切片 03）。

不改（确认无回归）：`LedgerStore`（create/update/fetch/presetCategories 签名不动）、`Models/*`、`Enums`、`AubadeApp`、`PersistenceController`、`PresetCategories`、`CategoryStyle`、`project.pbxproj`（file-system-synchronized groups 自动纳编）。

## 验证情况

- 编译：`xcodebuild -scheme Aubade -destination 'platform=iOS Simulator,name=iPhone 17' build` → **BUILD SUCCEEDED**（验证点 1）。
- 单测：`xcodebuild test` → **38 例全绿**（新增 TransactionDraft 13 + AmountFormat 7；既有 18 例无回归）。覆盖金额解析合法/空/空白/零/负/非数字、isValid、商户备注归一、create 默认、edit 全字段回填、EditorActions update 真落库读回、千分位符号 `-35.55`/`+8,000.00`、Decimal 无浮点误差（0.1+0.2=0.30）、方向色（验证点 1/2/7 单测侧）。
- **jflow-review 自评审：1/3 轮 PASS**。两个只读子 agent（代码正确性+TRD符合度 / 上游一致性+范围边界+SwiftUI陷阱）均 PASS，**阻断项：0**。采纳两 agent 共同点名的非阻断修复：3 处 `.alert(isPresented: .constant(...))` 常量绑定→真 `Binding`（系统可回写关闭）、分类 Picker 项 `Label(systemImage:"")` hack→`Text`；修复后重跑 38 例仍全绿。
- 未做：验证点 2/3/4/5/6/7/8 的模拟器肉眼 UI 交互（真机/模拟器点手动输入填表保存看最近记录刷新、今日已记+1、日期无法选未来、方向切换分类过滤清空、三占位仅弹提示、编辑回填改存刷新、全部跳 Tab）——无头环境无法肉眼验收，编译+单测+Preview 就绪，留待有界面环境确认。

## 遗留风险和注意事项

- **切片 03 复用 EditorActions**：列表进编辑（push 呈现）复用 `EditorActions.makeUpdate` 落库；`makeDelete` 已备好但本片零调用方，切片 03 注入 `onDelete` 时需在调用前套二次确认 UI（`.confirmationDialog`），并注意 `makeDelete` 内 `try? store.delete` 吞了异常，如需删除失败反馈要在切片 03 补。
- **CategoryStyle 取色规范延续**：`RecentTransactionRow` 已正确用主 API `CategoryStyle.color(name: tx.category?.name, direction: tx.direction)`（nil 分类走 direction 兜底）；切片 03 账单列表标签取色务必同样走主 API，勿用便利 `color(for: nil)`（返回中性灰、丢方向）。
- **金额 i18n**：`Decimal(string:)` 恒以 `.` 为小数点，逗号小数区域（如 de_DE）输入会解析失败；zh_CN happy path 无碍，i18n 留待后续换 `Decimal(string:locale:)`。
- **@Query 全量过滤**：todayCount / recentTransactions 取全表内存过滤，当前数据量小 TRD 已认可；数据量大后可换带 fetchLimit/predicate 的 FetchDescriptor（N02 汇总或数据膨胀时评估）。
- **edit 回填尾零**：`NSDecimalNumber.stringValue` 回填 88.80 显示为 "88.8"，纯展示层、落库数值无误差，不影响正确性。

## 下一次开发

1. 读取 `current.json.next_trd`，确认值仍为 `docs/design/nodes/n01-manual-ledger/03-ledger-list-filter-trd.md`。
2. 读取该 TRD 同目录的 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `docs/design/nodes/n01-manual-ledger/03-ledger-list-filter-trd.md`，只实现该 TRD 切片。

补充说明：
1. 读取 `.claude/jflow/current.json` 的 `next_trd`，应为 `docs/design/nodes/n01-manual-ledger/03-ledger-list-filter-trd.md`。
2. 读取该 TRD 同目录 `99-slice-progress.md` 和 `.claude/jflow/handoff.md`（本片刚更新）。
3. 打开切片 03 TRD（`03-ledger-list-filter-trd.md`），以其实际范围为准，只实现该切片。预计涉及账单 Tab 流水列表 + 从列表进编辑页（复用 `TransactionEditor(.edit)` + `EditorActions.makeUpdate`，push 呈现）+ 删除（注入 `onDelete` = 二次确认 + `EditorActions.makeDelete`），替换 `RootTabView` 的 `LedgerTabPlaceholder`；细节以 TRD 为准。
- 复用资产：`TransactionEditor` 双模式组件、`EditorActions.makeUpdate/makeDelete`、`AmountFormat`、`CategoryStyle`（取色走主 API）。
