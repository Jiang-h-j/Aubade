# TRD 切片进度

- 最近完成 TRD：`（尚未开发，TRD 设计阶段）`
- 下一个 TRD：`docs/design/nodes/n01-manual-ledger/01-shell-category-style-trd.md`
- 更新时间：2026-07-13（TRD 生成，待 jflow-review 自评审 + 用户 TRD 评审通过）

## 切片计划（3 片，硬依赖顺序 01 → 02 → 03）

| 序号 | 切片 | 文件 | 状态 |
|---|---|---|---|
| 01 | 4-Tab 主框架 + 分类展示映射 | `01-shell-category-style-trd.md` | 待开发 |
| 02 | 可复用编辑组件 + 手动记账 + 记账 Tab | `02-editor-manual-entry-trd.md` | 待开发 |
| 03 | 账单列表 + 筛选 + 编辑删除闭环 | `03-ledger-list-filter-trd.md` | 待开发 |

## 拆片依据（摘要）

N01 是纯 UI 构建、界面面广，且带一条对下游 N03~N06 的接口承诺（可复用编辑组件 `TransactionEditor`），存在"组件先于消费方"的实现顺序边界，故拆 3 片（N00 为单片）。

- 01 立地基：TabView 主框架替换 `ContentView` 占位 + `CategoryStyle`（分类名/direction→色+emoji，端上兜底，02/03 共用）。
- 02 做核心复用件 + 写入闭环：`TransactionEditor`（新建/编辑双模式）+ 手动记账 + 记账 Tab（今日已记/四入口/最近记录）。必须先于 03 落地。
- 03 做读取闭环：账单列表（日期分组/彩标/方向色）+ 分类/时间筛选 + 编辑（复用 02 组件）+ 删除二次确认。

## 涉及文件和符号（计划）

新增源码（`Aubade/Features/`，N01 引入此界面代码根）：
- AppShell/RootTabView.swift（`AppTab` 枚举、`RootTabView`、Analytics/Profile 正式占位、记账/账单临时占位）
- Shared/CategoryStyle.swift、Shared/AmountFormat.swift
- Editor/TransactionDraft.swift、Editor/TransactionEditor.swift（`EditorMode`）
- Record/ManualEntryView.swift、Record/RecordTabView.swift
- Ledger/LedgerTabView.swift、Ledger/LedgerRowView.swift、Ledger/LedgerFilter.swift、Ledger/TransactionDetailView.swift

新增测试（`AubadeTests/`）：CategoryStyleTests、TransactionDraftTests、AmountFormatTests、LedgerFilterTests。

改：`Aubade/ContentView.swift`（占位 → `RootTabView`）。
不改：`AubadeApp`、`PersistenceController`、`PresetCategories`、所有 `Models/*`、`LedgerStore`（签名不动）、`DebugMenuView`（迁入「我的」DEBUG 区）。

## 关键约束（贯穿三片，来自 N00 与 PRD 已确认约定）

- 读写经注入 `ModelContext`/`LedgerStore`，**不自建 `ModelContainer`**；**禁止链式 `container().mainContext`**（N00 SIGTRAP 悬垂 context 坑）。
- 分类模型名一律 `LedgerCategory`（非 `Category`，ObjC runtime 冲突）。
- 手动新建表单**不含商户**（约定 1）；日期**禁未来**（约定 2）；今日已记按 `createdAt`、列表/最近记录按 `occurredAt` 倒序（约定 3）；金额收入绿+正号、支出深色+减号，千分位（约定 4 + 验收 1）。
- 预置分类 color/icon 为 nil → `CategoryStyle` 端上兜底，不回写库。
- 分类选择器/筛选查全部分类（前向兼容 N07），当前预置 8 条效果等价。

## 遗留风险和注意事项

- 工程用 file-system-synchronized groups（objectVersion 77）：`Aubade/Features/` 新增 `.swift` 自动纳入编译，无需手改 pbxproj；新增测试文件同理进 `AubadeTests`。
- iOS 17 动态 `@Query` 取舍：切片 03 决策为"全量 `@Query` + 内存过滤/分组"（数据量小、可单测、增删改自动刷新），不为假想规模预造动态 predicate。
- 环境：本机 Xcode 26.6 + iOS 26.5 模拟器 runtime（N00 已验证可 build/test）。

## 下一次开发

TRD 尚在设计阶段。下一步：jflow-review 自评审 3 片 TRD → 通过后设 `pending_user_review: trd` 等用户「TRD 评审通过」→ 通过后 git 提交并进入 `jflow-dev` 按序实现切片 01。
恢复文件：`.claude/jflow/current.json`、本目录 `00-index.md` 与三片 TRD、`docs/prd/nodes/n01-manual-ledger-prd.md`。
