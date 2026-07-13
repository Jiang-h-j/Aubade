# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n01-manual-ledger/01-shell-category-style-trd.md`
- 下一个 TRD：`docs/design/nodes/n01-manual-ledger/02-editor-manual-entry-trd.md`
- 更新时间：2026-07-13T20:53:55+08:00

## 上一次 TRD 开发

N01 切片 01：把 App 从 N00 占位根视图换成底部四 Tab 主框架（记账/账单/统计/我的，默认落记账），并新增分类展示映射 `CategoryStyle`（分类名·方向 → emoji + 颜色，端上兜底、不回写库），供切片 02/03 复用。记账/账单为临时占位（02/03 替换），统计/我的为正式占位（N02/N07 才填），N00 的 DEBUG 调试入口迁入「我的」页 DEBUG 区。

## 涉及文件和符号

新增：
- `Aubade/Features/Shared/CategoryStyle.swift`：`CategoryStyle`（`emoji/color(name:direction:)` 主 API + `emoji/color(for: LedgerCategory?)` 便利 API），8 类预置固定 emoji/色，nil→🏷️、未知名按 direction 兜底 📦/💰。纯函数、无 context/save。
- `Aubade/Features/AppShell/RootTabView.swift`：`AppTab`（record/ledger/analytics/profile）、`RootTabView`（`TabView(selection:)` 默认 .record）、`AnalyticsPlaceholderView`、`ProfilePlaceholderView`（DEBUG 内 NavigationStack + NavigationLink→DebugMenuView）、私有临时占位 `RecordTabPlaceholder`/`LedgerTabPlaceholder`。
- `AubadeTests/CategoryStyleTests.swift`：8 类 emoji/色命中、前 5 支出类色≠兜底灰、nil、未知名兜底、便利 API 一致，共 8 例。

改：
- `Aubade/ContentView.swift`：body 占位 VStack → `RootTabView()`，移除 `DebugNavigationWrapper`，保留 `#Preview` 注入 in-memory 容器。

不改（确认无回归）：`AubadeApp`、`PersistenceController`、`PresetCategories`、`Models/*`、`LedgerStore`、`DebugMenuView`、`project.pbxproj`（file-system-synchronized groups 自动纳编）。

## 验证情况

- 编译：`xcodebuild -scheme Aubade -destination 'platform=iOS Simulator,name=iPhone 17' build` → **BUILD SUCCEEDED**（验证点1）。
- 单测：`xcodebuild test` → **18 例全绿**（CategoryStyleTests 8 例 + N00 既有 10 例无回归；验证点4）。CoreData 落盘目录首次创建的 recovery 日志属正常，不影响结果。
- 纯展示：`grep` 确认 `CategoryStyle.swift` 无 save/insert/delete/context（验证点5）。
- git 改动范围 = TRD「修改点」清单，未触 pbxproj。
- **jflow-review 自评审：1/3 轮 PASS**。两个只读子 agent（代码正确性+TRD符合度 / 上游一致性+范围边界）均 PASS，**阻断项：0**。
- 未做：验证点 2/3 的模拟器肉眼 UI 交互（四 Tab 点切、经「我的」→DEBUG 确认预置分类 8 条）——无头环境无法肉眼验收，编译通过 + Preview 就绪，留待有界面环境时确认。

## 遗留风险和注意事项

- **切片 03 调用规范（两 agent 共同提示）**：渲染「未选分类的收入账单」标签色时，必须走主 API `CategoryStyle.color(name: nil, direction: tx.direction)`，**不要**用便利 API `color(for: nil)`——后者对 nil 返回中性 `.gray`（无 direction 可依），会让收入未分类标签显示灰色而非期望的绿色。代码注释 `CategoryStyle.swift:55-56` 已引导，03 落地时需遵守。
- `presetStyles` 按 name 命中优先、忽略 direction：N07 若出现与预置同名但反方向的用户自建分类（如收入类命名「食」），会取预置配色。此为 TRD §61「名称命中优先」既定规则，非缺陷，N07 留意。
- `CategoryStyleTests` 的 Color 断言依赖系统命名色（`.purple` 等）Equatable；若 N02+ 改用 `Color(red:green:blue:)` 自定义色，相等比较可能变脆，届时改比较语义标识或加容差。

## 下一次开发

1. 读取 `current.json.next_trd`，确认值仍为 `docs/design/nodes/n01-manual-ledger/02-editor-manual-entry-trd.md`。
2. 读取该 TRD 同目录的 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `docs/design/nodes/n01-manual-ledger/02-editor-manual-entry-trd.md`，只实现该 TRD 切片。

补充说明：
- 下一步：进入切片 02 —— `docs/design/nodes/n01-manual-ledger/02-editor-manual-entry-trd.md`（可复用编辑组件 `TransactionEditor` 新建/编辑双模式 + 手动记账表单 + 记账 Tab 真实视图，替换本片 `RecordTabPlaceholder`）。
- 恢复文件：`.claude/jflow/current.json`、`docs/design/nodes/n01-manual-ledger/00-index.md`、`02-editor-manual-entry-trd.md`、节点 PRD `docs/prd/nodes/n01-manual-ledger-prd.md`。
- 复用资产：切片 02 表单选择器、账单标签直接用本片 `CategoryStyle`；记账 Tab 挂到 `RootTabView` 的 `.record` 分支（替换 `RecordTabPlaceholder`）。
